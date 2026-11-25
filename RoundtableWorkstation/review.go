package main

import (
	"crypto/sha256"
	"errors"
	"net/http"
	"net/url"
	"os"
	"sync"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/workspace"
)

type reviewResult struct {
	Path    string `json:"path"`
	Diff    string `json:"diff"`
	Added   int    `json:"added"`
	Removed int    `json:"removed"`
}

type reviewKey struct {
	Session, Path, Before, After string
	Patch                        [sha256.Size]byte
}

// Normalize only a requested, already matched revision. The bounded FIFO avoids
// repeating that work when the selected review is reopened; session polling
// never needs to normalize all historical revisions.
type reviewMemo struct {
	mu      sync.Mutex
	entries map[reviewKey]reviewResult
	order   []reviewKey
	bytes   int
}

const reviewCacheBytes = 8 << 20
const reviewCacheEntries = 64

var normalizedReviews reviewMemo

func reviewSize(key reviewKey, result reviewResult) int {
	return len(key.Session) + len(key.Path) + len(key.Before) + len(key.After) + len(result.Path) + len(result.Diff) + 128
}

func (cache *reviewMemo) get(key reviewKey) (reviewResult, bool) {
	cache.mu.Lock()
	defer cache.mu.Unlock()
	result, ok := cache.entries[key]
	return result, ok
}

func (cache *reviewMemo) put(key reviewKey, result reviewResult) {
	size := reviewSize(key, result)
	if size > reviewCacheBytes {
		return
	}
	cache.mu.Lock()
	defer cache.mu.Unlock()
	if _, ok := cache.entries[key]; ok {
		return
	}
	if cache.entries == nil {
		cache.entries = make(map[reviewKey]reviewResult)
	}
	for len(cache.order) >= reviewCacheEntries || cache.bytes+size > reviewCacheBytes {
		old := cache.order[0]
		cache.order[0] = reviewKey{}
		cache.order = cache.order[1:]
		cache.bytes -= reviewSize(old, cache.entries[old])
		delete(cache.entries, old)
	}
	cache.entries[key] = result
	cache.order = append(cache.order, key)
	cache.bytes += size
}

func savedChange(session *meeting.Session, path, before, after string) (workspace.Change, bool) {
	matches := func(change workspace.Change) bool {
		return change.Path == path && change.Before == before && change.After == after
	}
	for i := len(session.UserChanges) - 1; i >= 0; i-- {
		if change := session.UserChanges[i].Change; matches(change) {
			return change, true
		}
	}
	for ri := len(session.Rounds) - 1; ri >= 0; ri-- {
		for ti := len(session.Rounds[ri].Turns) - 1; ti >= 0; ti-- {
			changes := session.Rounds[ri].Turns[ti].Changes
			for ci := len(changes) - 1; ci >= 0; ci-- {
				if matches(changes[ci]) {
					return changes[ci], true
				}
			}
		}
	}
	return workspace.Change{}, false
}

func (a *apiServer) review(w http.ResponseWriter, r *http.Request, id string) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		reject(w, http.StatusMethodNotAllowed, "修订审阅只支持读取")
		return
	}
	query, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil {
		reject(w, http.StatusBadRequest, "修订参数格式有误")
		return
	}
	for _, name := range []string{"path", "before", "after"} {
		if len(query[name]) != 1 || query[name][0] == "" {
			reject(w, http.StatusBadRequest, "须提供且只提供一次 path、before 和 after")
			return
		}
	}
	session, err := a.meetings.Get(id)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			reject(w, http.StatusNotFound, "未找到该圆桌")
		} else {
			reject(w, http.StatusInternalServerError, "无法读取已保存的圆桌记录")
		}
		return
	}
	change, ok := savedChange(session, query.Get("path"), query.Get("before"), query.Get("after"))
	if !ok {
		reject(w, http.StatusNotFound, "本场圆桌没有完全匹配的实际修订记录")
		return
	}
	key := reviewKey{Session: id, Path: change.Path, Before: change.Before, After: change.After, Patch: sha256.Sum256([]byte(change.Diff))}
	if result, ok := normalizedReviews.get(key); ok {
		reply(w, http.StatusOK, result)
		return
	}
	patch, err := workspace.NormalizePatch(change.Diff)
	if err != nil {
		reject(w, http.StatusUnprocessableEntity, "此历史修订的差异无法还原；不会用当前文件替代")
		return
	}
	added, removed := workspace.ParseLineTotals(patch)
	result := reviewResult{Path: change.Path, Diff: patch, Added: added, Removed: removed}
	normalizedReviews.put(key, result)
	reply(w, http.StatusOK, result)
}
