package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"scistation.local/desktop/internal/research"
)

const discoverySchema = 1

type discoveryOptions struct {
	Query      string   `json:"query"`
	Source     string   `json:"source"`
	Categories []string `json:"categories"`
	CrossList  bool     `json:"cross_list"`
	TopK       int      `json:"top_k"`
	References []string `json:"reference_ids"`
	AIModel    string   `json:"ai_model,omitempty"`
}

type discoverySummary struct {
	ID       string `json:"id"`
	Query    string `json:"query"`
	Source   string `json:"source"`
	Updated  string `json:"updated"`
	Count    int    `json:"count"`
	Archived bool   `json:"archived,omitempty"`
}

type discoveryRun struct {
	discoveryOptions
	ID          string                        `json:"id"`
	Updated     string                        `json:"updated"`
	Archived    bool                          `json:"archived,omitempty"`
	Items       []research.DiscoveryCandidate `json:"items"`
	AtomQueries []string                      `json:"atom_queries,omitempty"`
	AIReview    map[string]string             `json:"ai_review,omitempty"`
	Notice      string                        `json:"notice,omitempty"`
}

type discoveryFeedback struct {
	research.DiscoveryCandidate
	Run     string `json:"run"`
	Updated string `json:"updated"`
}

type discoveryState struct {
	Schema         int                          `json:"schema_version"`
	Runs           []discoveryRun               `json:"runs"`
	Feedback       map[string]string            `json:"feedback"`
	FeedbackPapers map[string]discoveryFeedback `json:"feedback_papers,omitempty"`
	unknown        map[string]json.RawMessage
}

type discoveryView struct {
	discoveryRun
	Feedback map[string]string  `json:"feedback"`
	History  []discoverySummary `json:"history"`
}

type discoveryEdit struct {
	Run      string `json:"run"`
	Key      string `json:"key"`
	Arxiv    string `json:"arxiv"`
	State    string `json:"state"`
	FetchPDF bool   `json:"fetch_pdf"`
}

var discoveryMu sync.Mutex
var paperArxivID = regexp.MustCompile(`(?i)^(?:[a-z][a-z0-9.-]*/[0-9]{7}|[0-9]{4}\.[0-9]{4,5})(?:v[0-9]+)?$`)
var discoveryCategory = regexp.MustCompile(`^[a-z][a-z0-9]*(?:[-.][a-z0-9]+)*$`)

func loadDiscovery(path string) (discoveryState, error) {
	s := discoveryState{Schema: discoverySchema, Runs: []discoveryRun{}, Feedback: map[string]string{}, FeedbackPapers: map[string]discoveryFeedback{}}
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return s, err
	}
	if err = json.Unmarshal(b, &s.unknown); err != nil || s.unknown == nil {
		return s, errors.New("发现记录需要 JSON 对象")
	}
	s.Schema = 0
	if err = json.Unmarshal(b, &s); err != nil {
		return s, err
	}
	switch {
	case s.unknown["schema_version"] == nil:
		s.Schema = discoverySchema
		var old discoveryRun
		if err = json.Unmarshal(b, &old); err != nil {
			return s, err
		}
		if old.Query != "" || old.Updated != "" || len(old.Items) > 0 {
			old.ID, old.Source, old.CrossList, old.TopK = "legacy", "arxiv", true, len(old.Items)
			s.Runs = []discoveryRun{old}
		}
	case s.Schema != discoverySchema:
		return s, errors.New("发现记录版本不受支持")
	case s.unknown["runs"] == nil || s.Runs == nil:
		return s, errors.New("发现记录缺少检索历史")
	}
	if s.Feedback == nil {
		s.Feedback = map[string]string{}
	}
	if s.FeedbackPapers == nil {
		s.FeedbackPapers = map[string]discoveryFeedback{}
	}
	for _, key := range []string{"schema_version", "runs", "feedback", "feedback_papers", "query", "items", "updated"} {
		delete(s.unknown, key)
	}
	return s, nil
}

func (s discoveryState) save(file string) error {
	b, err := json.Marshal(s)
	if err != nil {
		return err
	}
	if len(s.unknown) != 0 {
		merged := s.unknown
		if err = json.Unmarshal(b, &merged); err != nil {
			return err
		}
		b, err = json.Marshal(merged)
		if err != nil {
			return err
		}
	}
	return atomicFile(file, b)
}

// A saved run remains accessible offline without recomputing its rankings.
func (s discoveryState) view(runID string) (discoveryView, bool) {
	result := discoveryView{
		discoveryRun: discoveryRun{discoveryOptions: discoveryOptions{Source: "arxiv", CrossList: true, TopK: 24}, Items: []research.DiscoveryCandidate{}},
		Feedback:     s.Feedback, History: []discoverySummary{},
	}
	found := runID == ""
	for _, run := range s.Runs {
		if !run.Archived {
			result.History = append(result.History, discoverySummary{ID: run.ID, Query: run.Query, Source: run.Source, Updated: run.Updated, Count: len(run.Items)})
			if result.ID == "" && (runID == "" || run.ID == runID) {
				result.discoveryRun = run
				found = true
			}
		}
	}
	return result, found
}

func (s *discoveryState) add(run discoveryRun) {
	if latest, _ := s.view(""); latest.ID != "" {
		prior := latest.discoveryRun
		prior.ID, prior.Updated = run.ID, run.Updated
		if reflect.DeepEqual(prior, run) {
			return
		}
	}
	var id [16]byte
	rand.Read(id[:])
	run.ID = hex.EncodeToString(id[:])
	s.Runs = append([]discoveryRun{run}, s.Runs...)
}

func normalizeDiscoveryOptions(options *discoveryOptions) error {
	options.Query = strings.TrimSpace(options.Query)
	if options.Source == "" {
		options.Source = "arxiv"
	}
	if options.TopK == 0 {
		options.TopK = 24
	}
	if utf8.RuneCountInString(options.Query) > 350 || options.TopK < 1 || options.TopK > 100 || len(options.Categories) > 24 || len(options.References) > 20 {
		return errors.New("检索式、分类、参考论文或候选数超出范围")
	}
	if options.Source != "arxiv" && options.Source != "graph" {
		return errors.New("文献来源无效")
	}
	if options.Source == "graph" && options.AIModel != "" {
		return errors.New("项目图谱发现为本地检索")
	}
	var categories []string
	for _, category := range options.Categories {
		category = strings.ToLower(strings.TrimSpace(category))
		if len(category) > 32 || !discoveryCategory.MatchString(category) {
			return errors.New("arXiv 分类代码无效")
		}
		if !slices.Contains(categories, category) {
			categories = append(categories, category)
		}
	}
	options.Categories = categories
	if options.Source == "arxiv" && options.Query == "" && len(categories) == 0 {
		return errors.New("请输入检索式或至少一个 arXiv 分类")
	}
	return nil
}

func arxivDiscoveryQuery(raw string, categories []string) string {
	if raw != "" && !strings.Contains(raw, ":") {
		raw = "all:\"" + strings.ReplaceAll(raw, "\"", " ") + "\""
	}
	if len(categories) == 0 {
		return raw
	}
	cat := make([]string, 0, len(categories))
	for _, c := range categories {
		// arXiv uses uppercase suffixes for subdivisions such as astro-ph.HE.
		before, after, dotted := strings.Cut(c, ".")
		if dotted {
			c = before + "." + strings.ToUpper(after)
		}
		cat = append(cat, "cat:"+c)
	}
	joined := strings.Join(cat, " OR ")
	if raw == "" {
		return joined
	}
	return "(" + raw + ") AND (" + joined + ")"
}

type discoveryDependencies struct {
	search func(context.Context, string, int) ([]research.DiscoveryCandidate, error)
	ai     discoveryAI
}

func (a *apiServer) serveDiscovery(lab *research.Service, w http.ResponseWriter, r *http.Request, route string) {
	if a.prefs == nil {
		reject(w, 503, "未打开工作区")
		return
	}
	serveDiscovery(lab, filepath.Dir(a.prefs.file), w, r, route, discoveryDependencies{
		search: research.SearchArxivCandidates,
		ai:     studioGateway(a.prefs),
	})
}

func serveDiscovery(lab *research.Service, dir string, w http.ResponseWriter, r *http.Request, route string, deps discoveryDependencies) {
	project := r.URL.Query().Get("project")
	name := "discovery.json"
	if project != "" {
		if !lab.HasActiveProject(project) {
			reject(w, 404, "科研项目不存在或已归档")
			return
		}
		name = "discovery." + project + ".json"
	}
	file := filepath.Join(dir, name)

	if route == "discover" && r.Method == http.MethodPost {
		options := discoveryOptions{CrossList: true}
		if !jsonBody(w, r, &options) {
			return
		}
		if err := normalizeDiscoveryOptions(&options); err != nil {
			reject(w, 400, err.Error())
			return
		}
		if options.Source == "graph" && project == "" {
			reject(w, 400, "请先选择项目以查看核心论文的图谱关系")
			return
		}
		sources, err := lab.DiscoveryContext(project, options.References)
		if err != nil {
			reject(w, 400, err.Error())
			return
		}
		discoveryMu.Lock()
		state, err := loadDiscovery(file)
		discoveryMu.Unlock()
		if err != nil {
			reject(w, 500, "发现记录无法读取")
			return
		}
		run, err := buildDiscoveryRun(r.Context(), options, sources, state, deps)
		if err != nil {
			reject(w, 502, err.Error())
			return
		}
		if r.Context().Err() != nil || (project != "" && !lab.HasActiveProject(project)) {
			reject(w, 409, "发现范围已关闭，请重新检索")
			return
		}
		discoveryMu.Lock()
		defer discoveryMu.Unlock()
		// Feedback may have changed while the external providers were working.
		// Reload before committing the new run so neither mutation can erase the other.
		state, err = loadDiscovery(file)
		if err != nil {
			reject(w, 500, "发现记录无法读取")
			return
		}
		state.add(run)
		saveDiscovery(w, file, state, "")
		return
	}

	if !(route == "discover" && r.Method == http.MethodGet) && !(route != "discover" && r.Method == http.MethodPost) {
		reject(w, 405, "不支持此请求")
		return
	}
	var edit discoveryEdit
	if r.Method == http.MethodPost && !jsonBody(w, r, &edit) {
		return
	}
	if route == "select-discovery" {
		discoveryMu.Lock()
		state, err := loadDiscovery(file)
		discoveryMu.Unlock()
		if err != nil {
			reject(w, 500, "发现记录无法读取")
			return
		}
		candidate, ok := discoverySelected(state, edit)
		if !ok {
			reject(w, 404, "推荐论文不在该检索记录中")
			return
		}
		paper, err := lab.ImportDiscoveryCandidate(r.Context(), project, candidate, edit.FetchPDF)
		if err != nil {
			reject(w, 409, err.Error())
			return
		}
		reply(w, 200, paper)
		return
	}
	discoveryMu.Lock()
	defer discoveryMu.Unlock()
	state, err := loadDiscovery(file)
	if err != nil {
		reject(w, 500, "发现记录无法读取")
		return
	}
	switch route {
	case "discover":
		view, ok := state.view(r.URL.Query().Get("run"))
		if !ok {
			reject(w, 404, "检索记录不存在或已归档")
			return
		}
		reply(w, 200, view)
	case "feedback":
		if !slices.Contains([]string{"", "saved", "hidden", "liked", "disliked", "opened"}, edit.State) {
			reject(w, 400, "无效的推荐反馈")
			return
		}
		if edit.Run == "" && paperArxivID.MatchString(edit.Arxiv) && edit.Key == "" {
			// Backward-compatible writes from the prototype.
			discoverySetFeedback(&state, research.ArxivWorkID(edit.Arxiv), edit.State, discoveryFeedback{})
			saveDiscovery(w, file, state, "")
			return
		}
		candidate, ok := discoverySelected(state, edit)
		if !ok {
			reject(w, 404, "推荐论文不在该检索记录中")
			return
		}
		discoverySetFeedback(&state, candidate.Key(), edit.State, discoveryFeedback{
			DiscoveryCandidate: candidate, Run: edit.Run, Updated: time.Now().UTC().Format(time.RFC3339Nano),
		})
		saveDiscovery(w, file, state, edit.Run)
	case "archive-discovery":
		runIndex := slices.IndexFunc(state.Runs, func(run discoveryRun) bool { return run.ID == edit.Run })
		if runIndex < 0 {
			reject(w, 404, "检索记录不存在")
			return
		}
		state.Runs[runIndex].Archived = true
		saveDiscovery(w, file, state, "")

	}
}

func discoverySelected(state discoveryState, edit discoveryEdit) (research.DiscoveryCandidate, bool) {
	if edit.Key == "" || edit.Run == "" {
		return research.DiscoveryCandidate{}, false
	}
	view, ok := state.view(edit.Run)
	if ok {
		for _, candidate := range view.Items {
			if candidate.Key() == edit.Key {
				return candidate, true
			}
		}
	}
	return research.DiscoveryCandidate{}, false
}

func discoverySetFeedback(state *discoveryState, key, feedback string, detail discoveryFeedback) {
	for id := range state.Feedback {
		if id == key || research.ArxivWorkID(id) == key {
			delete(state.Feedback, id)
			delete(state.FeedbackPapers, id)
		}
	}
	if feedback != "" {
		state.Feedback[key] = feedback
		if detail.Run != "" {
			state.FeedbackPapers[key] = detail
		}
	}
}

func saveDiscovery(w http.ResponseWriter, file string, state discoveryState, run string) {
	if err := state.save(file); err != nil {
		reject(w, 500, "保存发现记录失败")
		return
	}
	view, _ := state.view(run)
	reply(w, 200, view)
}
