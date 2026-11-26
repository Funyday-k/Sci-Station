package plugins

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"syscall"
	"time"

	"scistation.local/desktop/internal/workspace"
)

const (
	builtinID        = "builtin"
	maxRegistryBytes = 32 << 20
)

type Source struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	URL           string `json:"url"`
	Builtin       bool   `json:"builtin"`
	LastRefreshed string `json:"last_refreshed,omitempty"`
}

type AvailablePlugin struct {
	SourceID string `json:"source_id"`
	CatalogEntry
}

type InstalledPlugin struct {
	SourceID     string   `json:"source_id"`
	SourceName   string   `json:"source_name"`
	ID           string   `json:"id"`
	Version      string   `json:"version"`
	Name         string   `json:"name"`
	Author       string   `json:"author"`
	Description  string   `json:"description"`
	SHA256       string   `json:"sha256"`
	Capabilities []string `json:"capabilities"`
	Actions      []Action `json:"actions"`
	Enabled      bool     `json:"enabled"`
}

type View struct {
	Sources   []Source          `json:"sources"`
	Available []AvailablePlugin `json:"available"`
	Installed []InstalledPlugin `json:"installed"`
}

type cachedSource struct {
	Source
	Revision uint64         `json:"revision"`
	Entries  []CatalogEntry `json:"entries"`
}

type installedRecord struct {
	InstalledPlugin
	RoundGuidance  string `json:"round_guidance,omitempty"`
	ReportGuidance string `json:"report_guidance,omitempty"`
}

type registryState struct {
	SchemaVersion int                        `json:"schema_version"`
	Revision      uint64                     `json:"revision"`
	Sources       map[string]cachedSource    `json:"sources"`
	Installed     map[string]installedRecord `json:"installed"`
}

type Store struct {
	dir     string
	builtin cachedSource
	files   fs.FS
}

func NewStore(dir string) (*Store, error) {
	if strings.TrimSpace(dir) == "" {
		return nil, errors.New("缺少插件存储目录")
	}
	files := builtinFiles()
	data, err := fs.ReadFile(files, "catalog.json")
	if err != nil {
		return nil, err
	}
	catalog, err := ParseCatalog(data, "")
	if err != nil {
		return nil, fmt.Errorf("内置目录无效: %w", err)
	}
	if err := workspace.ManagedMkdirAll(filepath.Join(dir, "packages"), 0700); err != nil {
		return nil, err
	}
	s := &Store{dir: dir, files: files, builtin: cachedSource{Source: Source{ID: builtinID, Name: catalog.Name, Builtin: true}, Entries: catalog.Plugins}}
	if err := s.access(false, func(*registryState) error { return nil }); err != nil {
		return nil, err
	}
	return s, nil
}

func readFileLimited(path string, limit int64) ([]byte, error) {
	f, err := workspace.ManagedOpenFile(path, os.O_RDONLY, 0)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return readLimited(f, limit)
}

func (s *Store) load() (*registryState, error) {
	st := &registryState{}
	data, err := readFileLimited(filepath.Join(s.dir, "registry.json"), maxRegistryBytes)
	if errors.Is(err, os.ErrNotExist) {
		return &registryState{SchemaVersion: 1, Sources: map[string]cachedSource{}, Installed: map[string]installedRecord{}}, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(data, st); err != nil {
		return nil, fmt.Errorf("插件注册表无法读取: %w", err)
	}
	if st.SchemaVersion != 1 || st.Sources == nil || st.Installed == nil {
		return nil, errors.New("插件注册表格式无效")
	}
	for id, source := range st.Sources {
		if _, err := checkedURL(source.URL); err != nil || id != source.ID || id != "src-"+checksum([]byte(source.URL)) ||
			source.Builtin || !validText(source.Name, 128, false) || source.Entries == nil {
			return nil, errors.New("订阅来源记录无效")
		}
	}
	for id, item := range st.Installed {
		fromSubscription := strings.HasPrefix(item.SourceID, "src-") && validChecksum(strings.TrimPrefix(item.SourceID, "src-"))
		if ValidateMetadata(id, item.Version, item.Name, item.Author, item.Description) != nil || id != item.ID ||
			(item.SourceID != builtinID && !fromSubscription) || !validChecksum(item.SHA256) || item.Capabilities == nil || item.Actions == nil {
			return nil, errors.New("已安装插件记录无效")
		}
	}
	return st, nil
}

// The permanent lock file has a different inode from registry.json, which is
// atomically replaced. No network operation runs while any registry lock is held.
func (s *Store) access(write bool, fn func(*registryState) error) error {
	lock, err := workspace.ManagedOpenFile(filepath.Join(s.dir, "registry.lock"), os.O_RDWR|os.O_CREATE, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	mode := syscall.LOCK_SH
	if write {
		mode = syscall.LOCK_EX
	}
	for {
		err = syscall.Flock(int(lock.Fd()), mode)
		if err != syscall.EINTR {
			break
		}
	}
	if err != nil {
		return err
	}
	st, err := s.load()
	if err != nil {
		return err
	}
	if err = fn(st); err != nil || !write {
		return err
	}
	data, err := json.Marshal(st)
	if err != nil {
		return err
	}
	if len(data) > maxRegistryBytes {
		return errors.New("订阅目录总量超过本地容量限制")
	}
	if err := writeAtomic(filepath.Join(s.dir, "registry.json"), data); err != nil {
		return err
	}
	s.prunePackages(st)
	return nil
}

func writeAtomic(path string, data []byte) error { return workspace.ManagedAtomicWrite(path, data) }

// After publication no reader holds an obsolete reference. Clean up any old
// package, including one staged before a previous process was interrupted.
func (s *Store) prunePackages(st *registryState) {
	keep := make(map[string]bool, len(st.Installed))
	for _, p := range st.Installed {
		keep[p.SHA256] = true
	}
	dir := filepath.Join(s.dir, "packages")
	entries, err := workspace.ManagedReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		name := entry.Name()
		if !entry.IsDir() && ((validChecksum(name) && !keep[name]) || strings.HasPrefix(name, ".pending-")) {
			_ = workspace.ManagedRemove(filepath.Join(dir, name))
		}
	}
}

func (s *Store) source(st *registryState, id string) (cachedSource, error) {
	if id == builtinID {
		return s.builtin, nil
	}
	source, ok := st.Sources[id]
	if !ok {
		return cachedSource{}, errors.New("未订阅此插件来源")
	}
	return source, nil
}

func (s *Store) View() (View, error) {
	v := View{Sources: []Source{}, Available: []AvailablePlugin{}, Installed: []InstalledPlugin{}}
	err := s.access(false, func(st *registryState) error {
		userSources := make([]cachedSource, 0, len(st.Sources))
		for _, source := range st.Sources {
			userSources = append(userSources, source)
		}
		sort.Slice(userSources, func(i, j int) bool { return userSources[i].ID < userSources[j].ID })
		sources := append([]cachedSource{s.builtin}, userSources...)
		for _, source := range sources {
			v.Sources = append(v.Sources, source.Source)
			entries := slices.Clone(source.Entries)
			sort.Slice(entries, func(i, j int) bool { return entries[i].ID < entries[j].ID })
			for _, p := range entries {
				p.Capabilities = slices.Clone(p.Capabilities)
				v.Available = append(v.Available, AvailablePlugin{SourceID: source.ID, CatalogEntry: p})
			}
		}
		for _, p := range st.Installed {
			v.Installed = append(v.Installed, p.InstalledPlugin)
		}
		sort.Slice(v.Installed, func(i, j int) bool { return v.Installed[i].ID < v.Installed[j].ID })
		return nil
	})
	return v, err
}

func canonicalCatalogURL(u *url.URL) string {
	host := strings.ToLower(u.Hostname())
	port := u.Port()
	if port == "" || (u.Scheme == "https" && port == "443") || (u.Scheme == "http" && port == "80") {
		if strings.Contains(host, ":") {
			host = "[" + host + "]"
		}
	} else {
		host = net.JoinHostPort(host, port)
	}
	u.Host = host
	if u.Path == "" {
		u.Path = "/"
	}
	return u.String()
}

func downloadCatalog(ctx context.Context, raw string) (Catalog, error) {
	data, finalURL, err := fetch(ctx, raw, MaxCatalogBytes)
	if err != nil {
		return Catalog{}, err
	}
	return ParseCatalog(data, finalURL)
}

func (s *Store) AddSource(ctx context.Context, raw string) error {
	u, err := checkedURL(strings.TrimSpace(raw))
	if err != nil {
		return err
	}
	raw = canonicalCatalogURL(u)
	id := "src-" + checksum([]byte(raw))
	check := func(st *registryState) error {
		if _, ok := st.Sources[id]; ok {
			return errors.New("已订阅此目录")
		}
		return nil
	}
	if err = s.access(false, check); err != nil {
		return err
	}
	catalog, err := downloadCatalog(ctx, raw)
	if err != nil {
		return err
	}
	return s.access(true, func(st *registryState) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := check(st); err != nil {
			return err
		}
		st.Revision++
		st.Sources[id] = cachedSource{Source: Source{ID: id, Name: catalog.Name, URL: raw, LastRefreshed: time.Now().UTC().Format(time.RFC3339)}, Entries: catalog.Plugins, Revision: st.Revision}
		return nil
	})
}

func (s *Store) Refresh(ctx context.Context, id string) error {
	if id == builtinID {
		return nil
	}
	var previous cachedSource
	if err := s.access(false, func(st *registryState) error {
		var err error
		previous, err = s.source(st, id)
		return err
	}); err != nil {
		return err
	}
	catalog, err := downloadCatalog(ctx, previous.URL)
	if err != nil {
		return err
	}
	return s.access(true, func(st *registryState) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		current, err := s.source(st, id)
		if err != nil {
			return err
		}
		if current.Revision != previous.Revision {
			return errors.New("订阅目录已变更，请重新刷新")
		}
		st.Revision++
		current.Revision = st.Revision
		current.Name = catalog.Name
		current.Entries = catalog.Plugins
		current.LastRefreshed = time.Now().UTC().Format(time.RFC3339)
		st.Sources[id] = current
		return nil
	})
}

func (s *Store) RemoveSource(id string) error {
	if id == builtinID {
		return errors.New("内置来源无法移除")
	}
	return s.access(true, func(st *registryState) error {
		if _, err := s.source(st, id); err != nil {
			return err
		}
		delete(st.Sources, id)
		return nil
	})
}

func exactGrants(caps, grants []string) bool {
	if grants == nil || len(caps) != len(grants) {
		return false
	}
	sorted := slices.Clone(grants)
	slices.Sort(sorted)
	return slices.Equal(caps, sorted)
}

func installEntry(source cachedSource, id, expectedSHA string, grants []string, old installedRecord, installed bool) (CatalogEntry, error) {
	for _, p := range source.Entries {
		if p.ID != id {
			continue
		}
		if !validChecksum(expectedSHA) || !strings.EqualFold(p.SHA256, expectedSHA) {
			return CatalogEntry{}, errors.New("插件摘要已变更或缺失，请重新查看并确认")
		}
		if !exactGrants(p.Capabilities, grants) {
			return CatalogEntry{}, errors.New("请确认此版本的完整权限列表")
		}
		if installed {
			if old.SourceID != source.ID {
				return CatalogEntry{}, errors.New("此插件 ID 已从其他来源安装")
			}
			v := CompareVersions(p.Version, old.Version)
			if v < 0 || (v == 0 && old.SHA256 != p.SHA256) {
				return CatalogEntry{}, errors.New("不能降级或替换同一版本的插件内容")
			}
		}
		return p, nil
	}
	return CatalogEntry{}, errors.New("来源中没有此插件")
}

func verifyPackage(entry CatalogEntry, data []byte) (Manifest, error) {
	if checksum(data) != entry.SHA256 {
		return Manifest{}, errors.New("插件包 SHA-256 与确认信息不符")
	}
	m, err := ParsePackage(data)
	if err != nil {
		return Manifest{}, err
	}
	if err := matchManifest(entry, m); err != nil {
		return Manifest{}, err
	}
	return m, nil
}

func matchManifest(entry CatalogEntry, m Manifest) error {
	caps := m.Capabilities()
	if m.ID != entry.ID || m.Version != entry.Version || m.Name != entry.Name || m.Author != entry.Author || m.Description != entry.Description || !slices.Equal(entry.Capabilities, caps) {
		return errors.New("插件包的身份、版本、元数据或权限与目录不符")
	}
	return nil
}

func (s *Store) Install(ctx context.Context, sourceID, id, expectedSHA string, grants []string, expectedVersion ...string) error {
	var source cachedSource
	var entry CatalogEntry
	var old installedRecord
	var installed bool
	err := s.access(false, func(st *registryState) error {
		var err error
		source, err = s.source(st, sourceID)
		if err != nil {
			return err
		}
		old, installed = st.Installed[id]
		entry, err = installEntry(source, id, expectedSHA, grants, old, installed)
		if err == nil && (len(expectedVersion) > 1 || (len(expectedVersion) == 1 && expectedVersion[0] != "" && expectedVersion[0] != entry.Version)) {
			return errors.New("目录中的版本与确认信息不符，请重新查看")
		}
		return err
	})
	if err != nil {
		return err
	}
	var data []byte
	if source.Builtin {
		f, err := s.files.Open(entry.URL)
		if err != nil {
			return err
		}
		defer f.Close()
		data, err = readLimited(f, MaxPackageBytes)
		if err != nil {
			return err
		}
	} else {
		base, err := checkedURL(source.URL)
		if err != nil {
			return err
		}
		pkgURL, err := packageURL(base, entry.URL)
		if err != nil {
			return err
		}
		data, _, err = fetch(ctx, pkgURL, MaxPackageBytes)
		if err != nil {
			return err
		}
	}
	m, err := verifyPackage(entry, data)
	if err != nil {
		return err
	}
	return s.access(true, func(st *registryState) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		current, err := s.source(st, sourceID)
		if err != nil {
			return err
		}
		if source.Revision != current.Revision {
			return errors.New("安装期间目录已刷新，请重新确认")
		}
		now, exists := st.Installed[id]
		if exists != installed || (exists && (now.SHA256 != old.SHA256 || now.SourceID != old.SourceID)) {
			return errors.New("安装记录已变更，请重新确认")
		}
		enabled := !exists || now.Enabled
		actions := append([]Action{}, m.Contributions.Actions...)
		info := InstalledPlugin{SourceID: sourceID, SourceName: source.Name, ID: m.ID, Version: m.Version, Name: m.Name, Author: m.Author, Description: m.Description,
			SHA256: entry.SHA256, Capabilities: entry.Capabilities, Actions: actions, Enabled: enabled}
		st.Installed[id] = installedRecord{InstalledPlugin: info, RoundGuidance: m.Contributions.RoundGuidance, ReportGuidance: m.Contributions.ReportGuidance}
		if enabled {
			if err := checkGuidanceBudget(st.Installed); err != nil {
				return err
			}
		}
		return writeAtomic(filepath.Join(s.dir, "packages", entry.SHA256), data)
	})
}

// A reserved byte per item covers list separators in the meeting host.
func checkGuidanceBudget(installed map[string]installedRecord) error {
	round, report := 2, 2
	for _, p := range installed {
		if !p.Enabled {
			continue
		}
		for _, item := range []struct {
			key, text string
			used      *int
		}{{"round_guidance", p.RoundGuidance, &round}, {"report_guidance", p.ReportGuidance, &report}} {
			if item.text == "" {
				continue
			}
			*item.used += guidanceSize(p.ID, p.Version, p.Name, item.key, item.text)
			if *item.used > maxGuidanceBytes {
				return errors.New("启用的插件指引总量超过 8 KiB，请先停用其他指引插件")
			}
		}
	}
	return nil
}

func currentInstallation(st *registryState, id, sourceID, version, sha string) (installedRecord, error) {
	p, ok := st.Installed[id]
	if !ok {
		return installedRecord{}, errors.New("此插件已卸载，请刷新市场")
	}
	if p.SourceID != sourceID || p.Version != version || p.SHA256 != sha {
		return installedRecord{}, errors.New("安装来源或版本已变更，请刷新并重新选择")
	}
	return p, nil
}

func (s *Store) SetEnabled(id, sourceID, version, sha string, enabled bool) error {
	return s.access(true, func(st *registryState) error {
		p, err := currentInstallation(st, id, sourceID, version, sha)
		if err != nil {
			return err
		}
		p.Enabled = enabled
		st.Installed[id] = p
		if enabled {
			return checkGuidanceBudget(st.Installed)
		}
		return nil
	})
}

func (s *Store) Uninstall(id, sourceID, version, sha string) error {
	return s.access(true, func(st *registryState) error {
		if _, err := currentInstallation(st, id, sourceID, version, sha); err != nil {
			return err
		}
		delete(st.Installed, id)
		return nil
	})
}

func (s *Store) localPackage(p installedRecord) (Manifest, error) {
	data, err := readFileLimited(filepath.Join(s.dir, "packages", p.SHA256), MaxPackageBytes)
	if err != nil {
		return Manifest{}, err
	}
	if checksum(data) != p.SHA256 {
		return Manifest{}, errors.New("本地插件包与安装时的摘要不符")
	}
	// These exact bytes already passed ParsePackage before publication. Run
	// validates the module when executing it, outside the storage transaction.
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return Manifest{}, err
	}
	entry := CatalogEntry{ID: p.ID, Version: p.Version, Name: p.Name, Author: p.Author, Description: p.Description, Capabilities: p.Capabilities}
	if err := matchManifest(entry, m); err != nil {
		return Manifest{}, err
	}
	return m, nil
}

// EnabledGuidance reads the text snapshots approved at install time. Starting a
// meeting never opens an action module or needs a WebAssembly execution slot.
func (s *Store) EnabledGuidance() ([]Manifest, error) {
	enabled := []Manifest{}
	err := s.access(false, func(st *registryState) error {
		for _, p := range st.Installed {
			if p.Enabled && (p.RoundGuidance != "" || p.ReportGuidance != "") {
				enabled = append(enabled, Manifest{
					SchemaVersion: 1, ID: p.ID, Name: p.Name, Version: p.Version, Author: p.Author, Description: p.Description,
					Contributions: Contributions{RoundGuidance: p.RoundGuidance, ReportGuidance: p.ReportGuidance},
				})
			}
		}
		sort.Slice(enabled, func(i, j int) bool { return enabled[i].ID < enabled[j].ID })
		return nil
	})
	return enabled, err
}

func (s *Store) Enabled() ([]Manifest, error) {
	enabled := []Manifest{}
	err := s.access(false, func(st *registryState) error {
		for _, p := range st.Installed {
			if !p.Enabled {
				continue
			}
			m, err := s.localPackage(p)
			if err != nil {
				return fmt.Errorf("加载已启用插件 %s: %w", p.ID, err)
			}
			enabled = append(enabled, m)
		}
		sort.Slice(enabled, func(i, j int) bool { return enabled[i].ID < enabled[j].ID })
		return nil
	})
	if err != nil {
		return nil, err
	}
	return enabled, nil
}

// ActionPlugin binds a user click to the exact installation shown at review.
func (s *Store) ActionPlugin(id, sourceID, version, sha256 string) (Manifest, error) {
	var m Manifest
	err := s.access(false, func(st *registryState) error {
		p, err := currentInstallation(st, id, sourceID, version, sha256)
		if err != nil {
			return err
		}
		if !p.Enabled || len(p.Actions) == 0 {
			return errors.New("工具已停用、卸载或版本有变，请重新选择")
		}
		m, err = s.localPackage(p)
		return err
	})
	return m, err
}
