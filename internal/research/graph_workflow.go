package research

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

type graphWorkflowPreview struct {
	Kind      string `json:"kind"`
	ProjectID string `json:"projectId"`
	Server    string `json:"server"`
	URI       string `json:"uri"`
	SHA256    string `json:"sha256"`
	Excerpt   string `json:"excerpt"`
}

func workflowQuery(values url.Values) (graphQuery, string, error) {
	operation := values.Get("operation")
	if values.Get("focus") == "" {
		return graphQuery{}, operation, errors.New("请选择项目图谱起点")
	}
	params := url.Values{"focus": {values.Get("focus")}, "depth": {values.Get("depth")}}
	switch operation {
	case "reading":
		params.Set("direction", "outgoing")
		params["kind"] = []string{"cites", "extends"}
		params["nodeKind"] = []string{"paper"}
	case "bridge":
		if values.Get("target") == "" {
			return graphQuery{}, operation, errors.New("请选择路径终点")
		}
		params.Set("target", values.Get("target"))
		params.Set("direction", values.Get("direction"))
	case "lineage":
		params.Set("direction", values.Get("direction"))
		params["kind"] = []string{"extends"}
	default:
		return graphQuery{}, operation, errors.New("无效的图谱工作流查询")
	}
	query, err := parseGraphQuery(params)
	return query, operation, err
}

func (s *Service) graphWorkflow(w http.ResponseWriter, r *http.Request) {
	query, operation, err := workflowQuery(r.URL.Query())
	if err != nil {
		jsonFail(w, http.StatusBadRequest, err.Error())
		return
	}
	project, tasks, ok := s.projectGraphData(w, r)
	if !ok {
		return
	}
	nodes, edges := s.projectGraph(r.Context(), project, tasks)
	if r.Context().Err() != nil {
		return
	}
	if node, exists := nodes[query.focus]; exists && operation == "reading" && node.Kind != "paper" {
		jsonFail(w, http.StatusBadRequest, "阅读顺序需要以已入库论文为起点")
		return
	}
	graph, err := query.run(r.Context(), nodes, sortedGraphEdges(edges))
	if r.Context().Err() != nil {
		return
	}
	if err != nil {
		jsonFail(w, http.StatusNotFound, err.Error())
		return
	}
	text := graphWorkflowText(operation, query.focus, query.depth, graph)
	digest := sha256.Sum256([]byte(text))
	jsonReply(w, http.StatusOK, graphWorkflowPreview{
		Kind: "project-graph", ProjectID: project.Project.ID, Server: "本地项目图谱",
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

func graphWorkflowText(operation, focus string, depth int, graph graphResult) string {
	nodes := map[string]graphNode{}
	for _, n := range graph.Nodes {
		nodes[n.ID] = n
	}
	label := func(id string) string { return graphExcerptLabel(nodes[id].Label) }
	rows := []string{}
	switch operation {
	case "bridge":
		rows = append(rows, "项目图谱 · 最短关系路径（深度 "+strconv.Itoa(depth)+"）")
		if graph.Path != nil && graph.Path.Found {
			for i, id := range graph.Path.Nodes {
				rows = append(rows, strconv.Itoa(i+1)+". "+label(id)+" ["+id+"]")
				if i < len(graph.Edges) {
					edge := graph.Edges[i]
					rows = append(rows, "   "+edge.Kind+": "+label(edge.Source)+" → "+label(edge.Target))
				}
			}
		} else {
			rows = append(rows, "当前范围内未找到路径。")
		}
	case "reading":
		rows = append(rows, "项目图谱 · 阅读顺序（引用和扩展所指向的前置论文优先）")
		ids, cycle := graphReadingOrder(focus, graph)
		if cycle {
			rows = append(rows, "部分记录构成环，请核对其中的顺序。")
		}
		for i, id := range ids {
			rows = append(rows, strconv.Itoa(i+1)+". "+label(id)+" ["+id+"]")
		}
	case "lineage":
		rows = append(rows, "项目图谱 · 扩展关系（深度 "+strconv.Itoa(depth)+"）", "起点 "+label(focus)+" ["+focus+"]")
		for _, edge := range graph.Edges {
			rows = append(rows, label(edge.Source)+" ["+edge.Source+"] → "+label(edge.Target)+" ["+edge.Target+"]")
		}
		if len(graph.Edges) == 0 {
			rows = append(rows, "当前范围内没有已记录的扩展关系。")
		}
	}
	// Keep each locator intact when the existing Lab handoff requires truncation.
	var excerpt strings.Builder
	for _, row := range rows {
		if len([]rune(excerpt.String()))+len([]rune(row))+1 > 1960 {
			excerpt.WriteString("其余条目可在项目图谱中核对。\n")
			break
		}
		excerpt.WriteString(row + "\n")
	}
	return strings.TrimSpace(excerpt.String())
}

func graphReadingOrder(focus string, graph graphResult) ([]string, bool) {
	dependencies := map[string][]string{}
	for _, edge := range graph.Edges {
		dependencies[edge.Source] = append(dependencies[edge.Source], edge.Target)
	}
	state := map[string]int{}
	result := []string{}
	cycle := false
	var visit func(string)
	visit = func(node string) {
		switch state[node] {
		case 1:
			cycle = true
			return
		case 2:
			return
		}
		state[node] = 1
		for _, dependency := range dependencies[node] {
			visit(dependency)
		}
		state[node] = 2
		result = append(result, node)
	}
	visit(focus)
	return result, cycle
}
