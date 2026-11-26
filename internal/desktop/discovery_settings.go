package desktop

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"path/filepath"
	"unicode/utf8"

	"scistation.local/desktop/internal/research"
	"slices"
	"strings"
)

type discoveryDefaults struct {
	Source        string   `json:"source"`
	Categories    []string `json:"categories"`
	CrossList     bool     `json:"cross_list"`
	TopK          int      `json:"top_k"`
	MaxCandidates int      `json:"max_daily_candidates"`
	LibraryDays   int      `json:"library_recent_days"`
}

func defaultDiscoverySettings() discoveryDefaults {
	return discoveryDefaults{Source: "arxiv", CrossList: true, TopK: 24, MaxCandidates: 100, LibraryDays: 60}
}

func normalizeDiscoveryCategories(raw []string) ([]string, error) {
	if len(raw) > 24 {
		return nil, errors.New("至多选择 24 个 arXiv 分类")
	}
	var categories []string
	for _, category := range raw {
		category = strings.ToLower(strings.TrimSpace(category))
		if len(category) > 32 || !discoveryCategory.MatchString(category) {
			return nil, errors.New("arXiv 分类代码无效")
		}
		if !slices.Contains(categories, category) {
			categories = append(categories, category)
		}
	}
	return categories, nil
}

func validDiscoverySource(source string) bool {
	return slices.Contains([]string{"arxiv", "graph", "library", "daily"}, source)
}

func (d *discoveryDefaults) normalize(project string) error {
	if !validDiscoverySource(d.Source) || (d.Source == "graph" && project == "") {
		return errors.New("请选择当前范围可用的来源")
	}
	if d.TopK < 1 || d.TopK > 100 || d.MaxCandidates < d.TopK || d.MaxCandidates > 500 || d.LibraryDays < 1 || d.LibraryDays > 3650 {
		return errors.New("推荐篇数、候选上限或馆藏回溯天数无效")
	}
	var err error
	d.Categories, err = normalizeDiscoveryCategories(d.Categories)
	return err
}

type discoveryFeedInput struct {
	Name string `json:"name"`
	Text string `json:"text"`
}

type discoveryRequest struct {
	discoveryOptions
	Feed *discoveryFeedInput `json:"daily_feed,omitempty"`
}

type discoveryFeedProvenance struct {
	Name   string `json:"name"`
	SHA256 string `json:"sha256"`
}

type discoveryFeedbackEvent struct {
	Key     string `json:"key"`
	State   string `json:"state"`
	Run     string `json:"run,omitempty"`
	Updated string `json:"updated"`
}

func saveDiscoveryDefaults(w http.ResponseWriter, r *http.Request, file, project string) {
	if r.Method != http.MethodPost {
		reject(w, 405, "不支持此请求")
		return
	}
	var defaults discoveryDefaults
	if !jsonBody(w, r, &defaults) {
		return
	}
	if err := defaults.normalize(project); err != nil {
		reject(w, 400, err.Error())
		return
	}
	discoveryMu.Lock()
	defer discoveryMu.Unlock()
	state, err := loadDiscovery(file)
	if err != nil {
		reject(w, 500, "发现记录无法读取")
		return
	}
	state.Defaults = &defaults
	saveDiscovery(w, file, state, "")
}

func readDiscoveryFeed(input *discoveryFeedInput, limit int) ([]research.DiscoveryCandidate, *discoveryFeedProvenance, error) {
	if input == nil || len(input.Text) == 0 || len(input.Text) > 2<<20 {
		return nil, nil, errors.New("请选择至多 2 MiB 的 JSON 或 JSONL 文献文件")
	}
	name := filepath.Base(strings.ReplaceAll(strings.TrimSpace(input.Name), "\\", "/"))
	if name == "" || name == "." || name == "/" || utf8.RuneCountInString(name) > 255 || strings.ContainsAny(name, "\r\n\x00") {
		return nil, nil, errors.New("文献文件名无效")
	}
	candidates, err := research.ParseDiscoveryFeed(input.Text, limit)
	if err != nil {
		return nil, nil, err
	}
	hash := sha256.Sum256([]byte(input.Text))
	return candidates, &discoveryFeedProvenance{Name: name, SHA256: hex.EncodeToString(hash[:])}, nil
}
