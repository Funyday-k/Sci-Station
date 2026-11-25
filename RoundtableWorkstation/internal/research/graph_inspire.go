package research

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const inspireLiteratureAPI = "https://inspirehep.net/api/literature"
const inspireSummaryFields = "control_number,titles,dois,arxiv_eprints,citation_count,publication_info,earliest_date"

type inspireGraphPaper struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Arxiv     string `json:"arxiv,omitempty"`
	DOI       string `json:"doi,omitempty"`
	Year      int    `json:"year,omitempty"`
	Citations int    `json:"citations,omitempty"`
}

type inspireGraphReference struct {
	Paper   inspireGraphPaper `json:"paper"`
	Ordinal int               `json:"ordinal,omitempty"`
}

type inspireNeighbors struct {
	Paper      inspireGraphPaper       `json:"paper"`
	References []inspireGraphReference `json:"references"`
	CitedBy    []inspireGraphReference `json:"citedBy"`
}

type inspireSeedResult struct {
	Seed       string            `json:"seed"`
	Source     string            `json:"source"`
	FetchedAt  time.Time         `json:"fetchedAt,omitzero"`
	Warning    string            `json:"warning,omitempty"`
	Inspire    *inspireNeighbors `json:"inspire,omitempty"`
	Local      graphResult       `json:"local"`
	LocalLabel string            `json:"localLabel,omitempty"`
}

type inspireCacheRecord struct {
	Version   int              `json:"version"`
	Key       string           `json:"key"`
	FetchedAt time.Time        `json:"fetchedAt"`
	Data      inspireNeighbors `json:"data"`
}

func inspireGraphIdentity(p Paper) (key, path string) {
	switch {
	case inspirePattern.MatchString(p.InspireID):
		return "inspire:" + p.InspireID, "/literature/" + p.InspireID
	case arxivPattern.MatchString(p.Arxiv):
		id := ArxivWorkID(p.Arxiv)
		return "arxiv:" + id, "/arxiv/" + strings.ReplaceAll(url.PathEscape(id), "%2F", "/")
	case doiPattern.MatchString(p.DOI):
		id := strings.ToLower(p.DOI)
		return "doi:" + id, "/doi/" + url.PathEscape(id)
	default:
		return "", ""
	}
}

func inspireGraphSummary(record inspireRecord) inspireGraphPaper {
	m := record.Metadata
	id := ""
	if m.ID > 0 {
		id = strconv.Itoa(m.ID)
	}
	p := inspireGraphPaper{ID: id, Title: "INSPIRE " + id, Citations: max(m.CitationCount, 0)}
	if len(m.Titles) != 0 && strings.TrimSpace(m.Titles[0].Title) != "" {
		p.Title = cleanProviderAbstract(m.Titles[0].Title)
	}
	for _, value := range m.DOIs {
		if doi := normalizeDOI(value.Value); doiPattern.MatchString(doi) {
			p.DOI = doi
			break
		}
	}
	for _, value := range m.ArxivIDs {
		if arxiv := normalizeArxiv(value.Value); arxivPattern.MatchString(arxiv) {
			p.Arxiv = arxiv
			break
		}
	}
	for _, item := range m.Publication {
		if item.Year > 0 {
			p.Year = item.Year
			break
		}
	}
	if p.Year == 0 && len(m.EarliestDate) >= 4 {
		p.Year, _ = strconv.Atoi(m.EarliestDate[:4])
	}
	return p
}

type inspireGraphFetch func(context.Context, string, any) error

func pacedInspireGraphFetch() inspireGraphFetch {
	var next time.Time
	return func(ctx context.Context, address string, target any) error {
		if wait := time.Until(next); wait > 0 {
			timer := time.NewTimer(wait)
			defer timer.Stop()
			select {
			case <-timer.C:
			case <-ctx.Done():
				return ctx.Err()
			}
		}
		// INSPIRE currently allows 15 requests per 5 seconds. Pace a
		// multi-seed batch to leave room for all six selected records.
		next = time.Now().Add(350 * time.Millisecond)
		return decodeProviderRecord(ctx, address, target)
	}
}

func verifiedInspireCenter(identity string, record inspireRecord) (inspireGraphPaper, bool) {
	paper := inspireGraphSummary(record)
	if !inspirePattern.MatchString(paper.ID) {
		return inspireGraphPaper{}, false
	}
	kind, expected, _ := strings.Cut(identity, ":")
	switch kind {
	case "inspire":
		return paper, paper.ID == expected
	case "arxiv":
		for _, candidate := range record.Metadata.ArxivIDs {
			if id := normalizeArxiv(candidate.Value); ArxivWorkID(id) == expected {
				paper.Arxiv = id
				return paper, true
			}
		}
	case "doi":
		for _, candidate := range record.Metadata.DOIs {
			if id := normalizeDOI(candidate.Value); strings.EqualFold(id, expected) {
				paper.DOI = id
				return paper, true
			}
		}
	}
	return inspireGraphPaper{}, false
}

// Searches are assembled only from checked record identifiers. API request
// construction uses the same bounded HTTP client as paper metadata imports.
func inspireSearch(ctx context.Context, fetch inspireGraphFetch, query string, limit int) ([]inspireRecord, error) {
	values := url.Values{"q": {query}, "size": {strconv.Itoa(limit)}, "sort": {"mostrecent"},
		"fields": {inspireSummaryFields}}
	var out struct {
		Hits *struct {
			Hits []inspireRecord `json:"hits"`
		} `json:"hits"`
	}
	if err := fetch(ctx, inspireLiteratureAPI+"?"+values.Encode(), &out); err != nil {
		return nil, err
	}
	if out.Hits == nil || out.Hits.Hits == nil || len(out.Hits.Hits) > limit {
		return nil, errors.New("invalid INSPIRE search response")
	}
	return out.Hits.Hits, nil
}

func fetchInspireNeighbors(ctx context.Context, fetch inspireGraphFetch, identity, path string) (inspireNeighbors, error) {
	var center inspireRecord
	values := url.Values{"fields": {inspireSummaryFields + ",references"}}
	if err := fetch(ctx, "https://inspirehep.net/api"+path+"?"+values.Encode(), &center); err != nil {
		return inspireNeighbors{}, err
	}
	paper, valid := verifiedInspireCenter(identity, center)
	if !valid {
		return inspireNeighbors{}, errors.New("INSPIRE response did not identify the requested paper")
	}
	// Fetch one bounded batch of labels for the linked references. The order
	// and original ordinal always come from the center record.
	const limit = 25
	result := inspireNeighbors{Paper: paper, References: []inspireGraphReference{}, CitedBy: []inspireGraphReference{}}
	lookups := map[string]bool{}
	for i, item := range center.Metadata.References {
		link, err := url.Parse(item.Record.Ref)
		if err != nil || link.Hostname() != "inspirehep.net" || !strings.HasPrefix(link.Path, "/api/literature/") {
			continue
		}
		id := strings.TrimPrefix(link.Path, "/api/literature/")
		if !inspirePattern.MatchString(id) || id == paper.ID {
			continue
		}
		lookups[id] = true
		ref := inspireGraphPaper{ID: id, Title: "INSPIRE " + id}
		result.References = append(result.References, inspireGraphReference{Paper: ref, Ordinal: i + 1})
		if len(result.References) >= limit {
			break
		}
	}
	if len(lookups) != 0 {
		clauses := make([]string, 0, len(lookups))
		for id := range lookups {
			clauses = append(clauses, "recid:"+id)
		}
		sort.Strings(clauses)
		rows, err := inspireSearch(ctx, fetch, strings.Join(clauses, " OR "), len(clauses))
		if err != nil {
			return inspireNeighbors{}, err
		}
		for _, row := range rows {
			label := inspireGraphSummary(row)
			if !lookups[label.ID] {
				continue
			}
			for i := range result.References {
				if result.References[i].Paper.ID == label.ID {
					result.References[i].Paper = label
				}
			}
		}
	}
	rows, err := inspireSearch(ctx, fetch, "refersto:recid:"+paper.ID, limit)
	if err != nil {
		return inspireNeighbors{}, err
	}
	for _, row := range rows {
		item := inspireGraphSummary(row)
		if item.ID != "" && item.ID != paper.ID {
			result.CitedBy = append(result.CitedBy, inspireGraphReference{Paper: item})
		}
	}
	return result, nil
}

func inspireCacheName(key string) string {
	return fmt.Sprintf("inspire-graph-%x.json", sha256.Sum256([]byte(key)))
}

func (s *Service) readInspireGraph(key string) (inspireCacheRecord, bool) {
	root, err := os.OpenRoot(s.dir)
	if err != nil {
		return inspireCacheRecord{}, false
	}
	defer root.Close()
	file, err := root.OpenFile(inspireCacheName(key), os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return inspireCacheRecord{}, false
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > providerResponseLimit {
		return inspireCacheRecord{}, false
	}
	var record inspireCacheRecord
	dec := json.NewDecoder(io.LimitReader(file, providerResponseLimit))
	if dec.Decode(&record) != nil || dec.Decode(new(any)) != io.EOF || record.Version != 1 ||
		record.Key != key || record.FetchedAt.IsZero() || !inspirePattern.MatchString(record.Data.Paper.ID) ||
		len(record.Data.References) > 25 || len(record.Data.CitedBy) > 25 {
		return inspireCacheRecord{}, false
	}
	if strings.HasPrefix(key, "inspire:") && key != "inspire:"+record.Data.Paper.ID ||
		strings.HasPrefix(key, "arxiv:") && key != "arxiv:"+ArxivWorkID(record.Data.Paper.Arxiv) ||
		strings.HasPrefix(key, "doi:") && key != "doi:"+strings.ToLower(record.Data.Paper.DOI) {
		return inspireCacheRecord{}, false
	}
	for _, group := range [][]inspireGraphReference{record.Data.References, record.Data.CitedBy} {
		for _, entry := range group {
			if !inspirePattern.MatchString(entry.Paper.ID) || entry.Paper.Title == "" {
				return inspireCacheRecord{}, false
			}
		}
	}
	return record, true
}

func (s *Service) loadInspireGraph(ctx context.Context, fetch inspireGraphFetch, key, path string, online bool, seed *inspireSeedResult) {
	if key == "" {
		seed.Warning = "缺少可在 INSPIRE 查询的公开标识符。"
		return
	}
	if online {
		// A provider timeout must still leave other local seeds usable.
		request, cancel := context.WithTimeout(ctx, 8*time.Second)
		result, err := fetchInspireNeighbors(request, fetch, key, path)
		cancel()
		if err == nil {
			record := inspireCacheRecord{Version: 1, Key: key, FetchedAt: time.Now().UTC(), Data: result}
			if blob, err := json.Marshal(record); err != nil || len(blob) > providerResponseLimit ||
				atomicWrite(filepath.Join(s.dir, inspireCacheName(key)), blob) != nil {
				seed.Warning = "已取得 INSPIRE 数据，无法保存本地缓存。"
			}
			seed.Inspire, seed.FetchedAt, seed.Source = &result, record.FetchedAt, "inspire"
			return
		}
		seed.Warning = "INSPIRE 查询失败。"
	}
	if cached, ok := s.readInspireGraph(key); ok {
		seed.Inspire, seed.FetchedAt, seed.Source = &cached.Data, cached.FetchedAt, "cache"
	} else if seed.Warning == "" {
		seed.Warning = "暂无可用的 INSPIRE 缓存。"
	}
}

func (s *Service) graphCitations(w http.ResponseWriter, r *http.Request) {
	values := r.URL.Query()
	seeds := values["seed"]
	if len(seeds) == 0 || len(seeds) > 6 || values.Get("online") != "" && values.Get("online") != "1" {
		jsonFail(w, http.StatusBadRequest, "请选择 1–6 个图谱种子")
		return
	}
	s.mu.RLock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	s.mu.RUnlock()
	if !ok {
		return
	}
	// Only records associated with this project may be used as local seeds.
	papers := filterPapers(s.papers.all(), d.Project.ID, "", "")
	local := make(map[string]Paper, len(papers))
	for _, paper := range papers {
		local[paper.ID] = paper
	}
	normalized := make([]string, 0, len(seeds))
	seen := map[string]bool{}
	for _, seed := range seeds {
		if _, ok := local[seed]; !ok {
			id, external := strings.CutPrefix(seed, "inspire:")
			if !external || !inspirePattern.MatchString(id) {
				jsonFail(w, http.StatusNotFound, "项目中不存在该论文")
				return
			}
			seed = "inspire:" + strings.TrimLeft(id, "0")
			if seed == "inspire:" {
				jsonFail(w, http.StatusBadRequest, "无效的 INSPIRE 记录编号")
				return
			}
		}
		if !seen[seed] {
			normalized = append(normalized, seed)
			seen[seed] = true
		}
	}
	projection := buildPaperGraph(r.Context(), papers)
	nodes := make(map[string]graphNode, len(projection.Nodes))
	for _, n := range projection.Nodes {
		nodes[n.ID] = graphNode{n.ID, n.Title, n.Kind}
	}
	result := make([]inspireSeedResult, 0, len(normalized))
	fetch := pacedInspireGraphFetch()
	for _, seed := range normalized {
		if r.Context().Err() != nil {
			return
		}
		row := inspireSeedResult{Seed: seed, Source: "local", Local: graphResult{Nodes: []graphNode{}, Edges: []graphEdge{}}}
		paper, ok := local[seed]
		if ok {
			query := graphQuery{focus: seed, depth: 1, edgeKinds: []string{"cites"}}
			row.Local, _ = query.run(r.Context(), nodes, projection.Edges)
			row.LocalLabel = paper.Title
		} else {
			paper.InspireID = strings.TrimPrefix(seed, "inspire:")
		}
		key, path := inspireGraphIdentity(paper)
		s.loadInspireGraph(r.Context(), fetch, key, path, values.Get("online") == "1", &row)
		result = append(result, row)
	}
	if r.Context().Err() == nil {
		jsonReply(w, http.StatusOK, result)
	}
}
