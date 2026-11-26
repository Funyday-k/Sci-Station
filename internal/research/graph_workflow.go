package research

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type graphWorkflowLink struct {
	Label  string `json:"label"`
	NodeID string `json:"nodeId,omitempty"`
	URL    string `json:"url,omitempty"`
}

type graphWorkflowFinding struct {
	Title    string              `json:"title,omitempty"`
	Text     string              `json:"text"`
	Severity string              `json:"severity,omitempty"`
	Line     int                 `json:"line,omitempty"`
	Links    []graphWorkflowLink `json:"links,omitempty"`
	locators []string
	digest   [32]byte
}

type graphWorkflowResult struct {
	Title     string                 `json:"title"`
	Findings  []graphWorkflowFinding `json:"findings"`
	Notice    string                 `json:"notice,omitempty"`
	Total     int                    `json:"total"`
	Truncated bool                   `json:"truncated"`
}

type graphWorkflowPreview struct {
	graphWorkflowResult
	Kind      string `json:"kind"`
	ProjectID string `json:"projectId"`
	Server    string `json:"server"`
	URI       string `json:"uri"`
	SHA256    string `json:"sha256"`
	Excerpt   string `json:"excerpt"`
}

type graphWorkflowQuery struct {
	graphQuery
	operation, severity            string
	limit, threshold, minCitations int
}

func workflowQuery(values url.Values) (graphWorkflowQuery, error) {
	q := graphWorkflowQuery{operation: values.Get("operation")}
	params := url.Values{"focus": {values.Get("focus")}, "depth": {values.Get("depth")}, "direction": {values.Get("direction")}}
	var limit, depth int
	switch q.operation {
	case "reading":
		limit, depth = 12, 3
		params.Del("direction")
		params["kind"] = []string{"cites", "extends", "uses", "related"}
		params["nodeKind"] = []string{"paper", "method"}
	case "bridge":
		limit, depth = 10, 4
		if values.Get("target") == "" {
			return q, errors.New("请选择路径终点")
		}
		params.Set("target", values.Get("target"))
	case "lineage":
		// Keep the original general extension preview for previously saved locators.
		limit, depth = 100, 4
		params["kind"] = []string{"extends"}
	case "method-lineage":
		limit, depth = 100, 4
		params["kind"] = []string{"extends", "uses"}
		params["nodeKind"] = []string{"method"}
	case "missing-core", "stale-citations", "unsupported-claims", "stale-artifacts":
		limit = 100
		if q.operation == "missing-core" {
			limit = 10
		}
		params = url.Values{}
	default:
		return q, errors.New("无效的图谱工作流查询")
	}
	if depth > 0 {
		if params.Get("focus") == "" {
			return q, errors.New("请选择项目图谱起点")
		}
		if params.Get("depth") == "" {
			params.Set("depth", strconv.Itoa(depth))
		}
	}
	var err error
	q.graphQuery, err = parseGraphQuery(params)
	if err != nil {
		return q, err
	}
	q.limit, err = workflowNumber(values, "limit", limit, 1, 100)
	if err != nil {
		return q, err
	}
	if q.operation == "missing-core" {
		q.minCitations, err = workflowNumber(values, "minCitations", 1, 1, 100)
	}
	if q.operation == "stale-citations" {
		q.threshold, err = workflowNumber(values, "thresholdDays", 3650, 365, 36500)
	}
	if q.operation == "stale-artifacts" {
		q.threshold, err = workflowNumber(values, "thresholdDays", 90, 1, 36500)
	}
	if q.operation == "unsupported-claims" {
		q.severity = values.Get("severity")
		if q.severity != "" && q.severity != "error" && q.severity != "warning" {
			return q, errors.New("无效的证据问题级别")
		}
	}
	return q, err
}

func workflowNumber(values url.Values, name string, fallback, minimum, maximum int) (int, error) {
	raw := values.Get(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < minimum || value > maximum {
		return 0, errors.New("无效的图谱查询数值范围")
	}
	return value, nil
}

func (s *Service) graphWorkflow(w http.ResponseWriter, r *http.Request) {
	q, err := workflowQuery(r.URL.Query())
	if err != nil {
		jsonFail(w, http.StatusBadRequest, err.Error())
		return
	}
	project, tasks, ok := s.projectGraphData(w, r)
	if !ok {
		return
	}
	ctx := r.Context()
	var result graphWorkflowResult
	switch q.operation {
	case "unsupported-claims", "stale-artifacts":
		if _, err = s.directory(project); err != nil {
			jsonFail(w, http.StatusForbidden, "项目目录授权不可用")
			return
		}
		result = s.graphArtifactFindings(ctx, project, tasks, q, time.Now())
	default:
		papers := s.papers.all()
		if q.operation == "missing-core" {
			result = missingCoreFindings(ctx, project.Project.ID, papers, q.minCitations)
			break
		}
		nodes, edges := s.projectGraphWithPapers(ctx, project, tasks, papers)
		if node, exists := nodes[q.focus]; exists {
			if q.operation == "reading" && node.Kind != "paper" {
				jsonFail(w, http.StatusBadRequest, "阅读顺序需要以库内论文为起点")
				return
			}
			if q.operation == "method-lineage" && node.Kind != "method" {
				jsonFail(w, http.StatusBadRequest, "方法沿革需要以 Wiki 方法页面为起点")
				return
			}
		}
		orderedEdges := sortedGraphEdges(edges)
		switch q.operation {
		case "reading":
			result, err = graphReadingFindings(ctx, q.graphQuery, project.Project.ID, nodes, orderedEdges, papers, time.Now().Year())
		case "stale-citations":
			result = staleCitationFindings(ctx, project.Project.ID, nodes, orderedEdges, papers, time.Now().Year(), q.threshold)
		default:
			var graph graphResult
			graph, err = q.graphQuery.run(ctx, nodes, orderedEdges)
			if err == nil {
				result = graphTraversalFindings(q, graph)
			}
		}
	}
	if ctx.Err() != nil {
		return
	}
	if err != nil {
		jsonFail(w, http.StatusNotFound, err.Error())
		return
	}
	result.Total = len(result.Findings)
	result.Truncated = result.Total > q.limit
	result.Findings = result.Findings[:min(q.limit, result.Total)]
	if result.Findings == nil {
		result.Findings = []graphWorkflowFinding{}
	}
	text := graphWorkflowText(result)
	digest := sha256.Sum256([]byte(text))
	w.Header().Set("Cache-Control", "no-store")
	jsonReply(w, http.StatusOK, graphWorkflowPreview{
		graphWorkflowResult: result,
		Kind:                "project-graph", ProjectID: project.Project.ID, Server: "本地项目图谱",
		URI: r.URL.RequestURI(), Excerpt: text, SHA256: hex.EncodeToString(digest[:]),
	})
}

func graphExcerptLabel(text string) string {
	runes := []rune(strings.Join(strings.Fields(text), " "))
	if len(runes) > 150 {
		return string(runes[:150]) + "…"
	}
	return string(runes)
}

func graphFindingNode(node graphNode) graphWorkflowLink {
	return graphWorkflowLink{Label: node.Label, NodeID: node.ID}
}

func graphTraversalFindings(q graphWorkflowQuery, graph graphResult) graphWorkflowResult {
	nodes := map[string]graphNode{}
	for _, n := range graph.Nodes {
		nodes[n.ID] = n
	}
	depth := "（深度 " + strconv.Itoa(q.depth) + "）"
	result := graphWorkflowResult{}
	if q.operation == "bridge" {
		result.Title = "项目图谱 · 最短关系路径" + depth
		if graph.Path == nil || !graph.Path.Found {
			result.Notice = "当前范围内未找到路径。"
			return result
		}
		for i, id := range graph.Path.Nodes {
			row := graphWorkflowFinding{
				Title: graphExcerptLabel(nodes[id].Label), Links: []graphWorkflowLink{graphFindingNode(nodes[id])}, locators: []string{id},
			}
			if i < len(graph.Edges) {
				edge := graph.Edges[i]
				row.Text = edge.Kind + " " + graphExcerptLabel(nodes[edge.Source].Label) + " → " + graphExcerptLabel(nodes[edge.Target].Label)
			}
			result.Findings = append(result.Findings, row)
		}
		return result
	}

	result.Title = "项目图谱 · 扩展关系" + depth
	if q.operation == "method-lineage" {
		result.Title = "项目图谱 · 方法沿革" + depth
	}
	result.Notice = "起点 " + graphExcerptLabel(nodes[q.focus].Label)
	if len(graph.Edges) == 0 {
		result.Notice += "。当前范围内没有已记录的对应关系。"
		return result
	}
	for _, edge := range graph.Edges {
		from, to := nodes[edge.Source], nodes[edge.Target]
		kind := "扩展"
		if edge.Kind == "uses" {
			kind = "使用"
		}
		row := graphWorkflowFinding{
			Text:     graphExcerptLabel(from.Label) + " → " + kind + " → " + graphExcerptLabel(to.Label),
			Links:    []graphWorkflowLink{graphFindingNode(from), graphFindingNode(to)},
			locators: []string{from.ID, to.ID},
		}
		if edge.Label != "" {
			row.Text += " · " + graphExcerptLabel(edge.Label)
		}
		result.Findings = append(result.Findings, row)
	}
	return result
}

func graphWorkflowText(result graphWorkflowResult) string {
	rows := []string{result.Title}
	if result.Notice != "" {
		rows = append(rows, result.Notice)
	}
	for i, finding := range result.Findings {
		row := finding.Text
		if finding.Title != "" {
			row = finding.Title
			if finding.Text != "" {
				row += " · " + finding.Text
			}
		}
		if len(finding.locators) > 0 {
			row += " [" + strings.Join(finding.locators, ", ") + "]"
		}
		rows = append(rows, strconv.Itoa(i+1)+". "+row)
	}
	if result.Truncated {
		rows = append(rows, "另有 "+strconv.Itoa(result.Total-len(result.Findings))+" 条结果。")
	}

	const limit = 1960
	var excerpt strings.Builder
	runes := 0
	for _, row := range rows {
		width := len([]rune(row)) + 1
		if runes+width > limit-25 {
			excerpt.WriteString("其余条目可在项目图谱中核对。\n")
			break
		}
		excerpt.WriteString(row + "\n")
		runes += width
	}
	return strings.TrimSpace(excerpt.String())
}
