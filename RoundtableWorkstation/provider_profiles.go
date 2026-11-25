package main

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/gateway"
)

const providerProfileVersion = 1

var errProviderProfileMissing = errors.New("找不到所选直接模型配置")
var errProviderKeychain = errors.New("无法访问直接模型的 macOS 钥匙串")
var errProviderWrite = errors.New("无法保存直接模型配置，请检查应用数据目录")

type profileRecord struct {
	profile gateway.CompatibleProfile
	fields  json.RawMessage
}

type providerProfileStore struct {
	mu      sync.RWMutex
	file    string
	extras  json.RawMessage
	records []profileRecord
	key     func(profileID, endpoint string) credentials.Store
}

func openProviderProfiles(dir string, key func(profileID, endpoint string) credentials.Store) (*providerProfileStore, error) {
	s := &providerProfileStore{file: filepath.Join(dir, "provider-profiles.json"), key: key}
	raw, err := os.ReadFile(s.file)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	var decoded struct {
		Version  int               `json:"version"`
		Profiles []json.RawMessage `json:"profiles"`
	}
	if err := json.Unmarshal(raw, &decoded); err != nil || decoded.Version != providerProfileVersion || decoded.Profiles == nil || len(decoded.Profiles) > 64 {
		return nil, errors.New("malformed or unsupported provider profile settings")
	}
	for _, item := range decoded.Profiles {
		var profile gateway.CompatibleProfile
		if err := json.Unmarshal(item, &profile); err != nil || !validProviderID(profile.ID) || profileIndex(s.records, profile.ID) >= 0 {
			return nil, errors.New("malformed or duplicate provider profile")
		}
		profile, err = gateway.NormalizeCompatibleProfile(profile)
		if err != nil {
			return nil, err
		}
		s.records = append(s.records, profileRecord{profile: profile, fields: item})
	}
	s.extras = raw
	return s, nil
}

func validProviderID(id string) bool {
	return len(id) > 0 && len(id) <= 40 && strings.IndexFunc(id, func(r rune) bool {
		return (r < 'a' || r > 'z') && (r < '0' || r > '9') && r != '-'
	}) == -1
}

func profileIndex(records []profileRecord, id string) int {
	return slices.IndexFunc(records, func(r profileRecord) bool { return r.profile.ID == id })
}

func (s *providerProfileStore) Profiles() []gateway.CompatibleProfile {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]gateway.CompatibleProfile, 0, len(s.records))
	for _, r := range s.records {
		out = append(out, r.profile)
	}
	return out
}

func (s *providerProfileStore) ResolveKey(p gateway.CompatibleProfile) (string, error) {
	if p.ID == "" {
		return "", nil
	}
	value, err := s.key(p.ID, p.BaseURL).Resolve()
	if err != nil || (value != "" && !validStoredToken(value)) {
		return "", errProviderKeychain
	}
	return value, nil
}

func (s *providerProfileStore) configured(p gateway.CompatibleProfile) (bool, error) {
	configured, err := s.key(p.ID, p.BaseURL).Configured()
	if err != nil {
		return false, errProviderKeychain
	}
	return configured, nil
}

func (s *providerProfileStore) upsert(update gateway.CompatibleProfile) (gateway.CompatibleProfile, error) {
	normalized, err := gateway.NormalizeCompatibleProfile(update)
	if err != nil {
		return update, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	next := slices.Clone(s.records)
	if normalized.ID == "" {
		if len(next) >= 64 {
			return update, errors.New("最多可保存 64 个直接模型配置")
		}
		normalized.ID = strings.ToLower(rand.Text())
		next = append(next, profileRecord{profile: normalized})
	} else {
		index := profileIndex(next, normalized.ID)
		if index < 0 {
			return update, errProviderProfileMissing
		}
		if old := next[index].profile; old.BaseURL != normalized.BaseURL {
			if err := s.requireEmptyKey(old); err != nil {
				return update, err
			}
		}
		next[index].profile = normalized
	}
	return normalized, s.write(next)
}

func (s *providerProfileStore) requireEmptyKey(p gateway.CompatibleProfile) error {
	configured, err := s.configured(p)
	if err != nil {
		return err
	}
	if configured {
		return errors.New("请先清除此配置的 API Key，再更改服务地址或移除配置")
	}
	return nil
}

func (s *providerProfileStore) remove(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	index := profileIndex(s.records, id)
	if index < 0 {
		return errProviderProfileMissing
	}
	if err := s.requireEmptyKey(s.records[index].profile); err != nil {
		return err
	}
	return s.write(slices.Delete(slices.Clone(s.records), index, index+1))
}

func (s *providerProfileStore) updateKey(id, key string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	index := profileIndex(s.records, id)
	if index < 0 {
		return errProviderProfileMissing
	}
	p := s.records[index].profile
	store := s.key(p.ID, p.BaseURL)
	var err error
	if key == "" {
		err = store.Delete()
	} else {
		err = store.Save(key)
	}
	if err != nil {
		return errProviderKeychain
	}
	return nil
}

// Update the known fields and keep extensions at both levels of the file.
func mergeProviderFields(original json.RawMessage, known any) (json.RawMessage, error) {
	fields := map[string]json.RawMessage{}
	if len(original) != 0 {
		if err := json.Unmarshal(original, &fields); err != nil {
			return nil, err
		}
	}
	encoded, err := json.Marshal(known)
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(encoded, &fields); err != nil {
		return nil, err
	}
	return json.Marshal(fields)
}

func (s *providerProfileStore) write(records []profileRecord) error {
	profiles := make([]json.RawMessage, 0, len(records))
	for i := range records {
		updated, err := mergeProviderFields(records[i].fields, records[i].profile)
		if err != nil {
			return errProviderWrite
		}
		records[i].fields = updated
		profiles = append(profiles, updated)
	}
	updated, err := mergeProviderFields(s.extras, map[string]any{"version": providerProfileVersion, "profiles": profiles})
	if err != nil || atomicFile(s.file, updated) != nil {
		return errProviderWrite
	}
	s.records, s.extras = records, updated
	return nil
}
