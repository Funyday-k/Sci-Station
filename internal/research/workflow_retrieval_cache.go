package research

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"syscall"

	"scistation.local/desktop/internal/workspace"
)

const (
	retrievalCacheVersion = 1
	retrievalModel        = "scistation-deterministic-32-v1"
	retrievalCacheBytes   = 8 << 20
)

type retrievalCacheRow struct {
	Hash    string            `json:"hash"`
	Vectors []retrievalVector `json:"vectors"`
}

type retrievalCache struct {
	Version int                          `json:"version"`
	Model   string                       `json:"model"`
	Project string                       `json:"project"`
	Sources map[string]retrievalCacheRow `json:"sources"`
}

func newRetrievalCache(project string) retrievalCache {
	return retrievalCache{
		Version: retrievalCacheVersion, Model: retrievalModel, Project: project,
		Sources: map[string]retrievalCacheRow{},
	}
}

func readRetrievalCache(path, project string) (retrievalCache, string) {
	blank := newRetrievalCache(project)
	f, err := workspace.ManagedOpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if errors.Is(err, os.ErrNotExist) {
		return blank, "new"
	}
	if err != nil {
		return blank, "unavailable"
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return blank, "unavailable"
	}
	if info.Size() > retrievalCacheBytes {
		return blank, "invalid"
	}
	var cache retrievalCache
	data, err := io.ReadAll(io.LimitReader(f, retrievalCacheBytes+1))
	if err != nil {
		return blank, "unavailable"
	}
	if len(data) > retrievalCacheBytes || json.Unmarshal(data, &cache) != nil || cache.Project != project || cache.Sources == nil {
		return blank, "invalid"
	}
	if cache.Version != retrievalCacheVersion || cache.Model != retrievalModel {
		return blank, "version_changed"
	}
	return cache, "current"
}

func (s *Service) retrievalCachePath(project string) string {
	return filepath.Join(s.dir, "lab-retrieval", project+".json")
}

func writeRetrievalCache(path string, cache retrievalCache) error {
	data, err := json.Marshal(cache)
	if err != nil {
		return err
	}
	if len(data) > retrievalCacheBytes {
		return errors.New("local retrieval cache exceeds its size limit")
	}
	if err = workspace.ManagedMkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	return workspace.ManagedAtomicWrite(path, data)
}
