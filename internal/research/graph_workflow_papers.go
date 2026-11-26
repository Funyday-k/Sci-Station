package research

import (
	"context"
	"net/url"
	"slices"
	"strconv"
	"strings"
)

func graphPaperReaderLink(paper Paper, project string) graphWorkflowLink {
	q := url.Values{"paper": {paper.ID}}
	if slices.Contains(paper.ProjectIDs, project) {
		q.Set("project", project)
	}
	return graphWorkflowLink{Label: paper.Title, URL: "/reader?" + q.Encode()}
}

func graphPaperIndex(papers []Paper) map[string]Paper {
	index := make(map[string]Paper, len(papers))
	for _, paper := range papers {
		index[paper.ID] = paper
	}
	return index
}

func graphPaperYears(year int) string {
	if year <= 0 {
		return ""
	}
	return "（" + strconv.Itoa(year) + "）"
}

type coreCitationCandidate struct {
	node   graphNode
	citing []graphEdge
}

func missingCoreFindings(ctx context.Context, project string, papers []Paper, minimum int) graphWorkflowResult {
	var core []Paper
	index := graphPaperIndex(papers)
	for _, paper := range papers {
		if slices.Contains(paper.CoreProjectIDs, project) {
			core = append(core, paper)
		}
	}
	result := graphWorkflowResult{Title: "项目图谱 · 尚未关联项目的核心参考文献",
		Notice: "已检查 " + strconv.Itoa(len(core)) + " 篇核心论文。只计入有明确记录的引文。"}
	if len(core) == 0 {
		return result
	}

	graph := buildPaperGraphForSources(ctx, core, papers)
	candidates := map[string]coreCitationCandidate{}
	for _, node := range graph.Nodes {
		if node.Kind == "reference" {
			candidates[node.ID] = coreCitationCandidate{node: graphNode{node.ID, node.Title, node.Kind}}
		}
	}
	for _, edge := range graph.Edges {
		if edge.Kind != "cites" {
			continue
		}
		candidate := candidates[edge.Target]
		if target, known := index[edge.Target]; known {
			if slices.Contains(target.ProjectIDs, project) {
				continue
			}
			candidate.node = graphNode{target.ID, target.Title, "paper"}
		} else if candidate.node.ID == "" {
			continue
		}
		var confirmed []graphOccurrence
		for _, occurrence := range edge.Occurrences {
			if occurrence.Resolution != "ambiguous-title" {
				confirmed = append(confirmed, occurrence)
			}
		}
		if len(confirmed) == 0 {
			continue
		}
		edge.Occurrences = confirmed
		candidate.citing = append(candidate.citing, edge)
		candidates[edge.Target] = candidate
	}
	ranked := valuesBy(candidates, func(a, b coreCitationCandidate) bool {
		if len(a.citing) != len(b.citing) {
			return len(a.citing) > len(b.citing)
		}
		if a.node.Label != b.node.Label {
			return a.node.Label < b.node.Label
		}
		return a.node.ID < b.node.ID
	})
	for _, candidate := range ranked {
		if len(candidate.citing) < minimum {
			break
		}
		var target string
		row := graphWorkflowFinding{}
		if paper, ok := index[candidate.node.ID]; ok {
			target = graphNodeLocator(candidate.node) + graphPaperYears(paper.Year)
			row.Links = append(row.Links, graphPaperReaderLink(paper, project))
		} else {
			target = graphExcerptLabel(candidate.citing[0].Occurrences[0].Quote) + "（库内未确认）"
		}
		row.Text = target + " · " + strconv.Itoa(len(candidate.citing)) + " 篇核心论文引用"
		for _, edge := range candidate.citing[:min(5, len(candidate.citing))] {
			paper := index[edge.Source]
			row.Text += " · " + graphNodeLocator(graphNode{paper.ID, paper.Title, "paper"})
			row.Links = append(row.Links, graphCitationSourceLink(paper, project, edge.Occurrences[0]))
		}
		result.Findings = append(result.Findings, row)
	}
	if len(result.Findings) == 0 {
		result.Notice += " 当前未发现满足条件的引文。"
	}
	return result
}

func graphCitationSourceLink(paper Paper, project string, occurrence graphOccurrence) graphWorkflowLink {
	if occurrence.Source != "metadata" && occurrence.Source != "paper-note" {
		return graphPaperReaderLink(paper, project)
	}
	q := url.Values{"project": {project}, "paper": {paper.ID}, "citation": {occurrence.Source},
		"ordinal": {strconv.Itoa(occurrence.Ordinal)}, "revision": {strconv.Itoa(occurrence.SourceRevision)}}
	if occurrence.Line > 0 {
		q.Set("line", strconv.Itoa(occurrence.Line))
		q.Set("endLine", strconv.Itoa(occurrence.EndLine))
	}
	return graphWorkflowLink{Label: "查看 " + paper.Title + " 中的引文", URL: "/reader?" + q.Encode()}
}

func staleCitationFindings(ctx context.Context, project string, nodes map[string]graphNode, edges []graphEdge, papers []Paper, year, thresholdDays int) graphWorkflowResult {
	index := graphPaperIndex(papers)
	threshold := (thresholdDays + 364) / 365
	result := graphWorkflowResult{Title: "项目图谱 · 待核对的陈旧引文", Notice: "引文须达到 " + strconv.Itoa(threshold) + " 年，并有明确记录的较新扩展。"}
	extensions := map[string][]Paper{}
	for _, edge := range edges {
		if edge.Kind != "extends" {
			continue
		}
		newer, older := index[edge.Source], index[edge.Target]
		if older.Year > 0 && newer.Year > older.Year {
			extensions[older.ID] = append(extensions[older.ID], newer)
		}
	}
	for _, edge := range edges {
		if ctx.Err() != nil {
			return result
		}
		if edge.Kind != "cites" || len(extensions[edge.Target]) == 0 {
			continue
		}
		citing, cited := index[edge.Source], index[edge.Target]
		if !slices.Contains(citing.ProjectIDs, project) || year-cited.Year < threshold {
			continue
		}
		newer := extensions[cited.ID]
		slices.SortFunc(newer, func(a, b Paper) int {
			if a.Year != b.Year {
				return b.Year - a.Year
			}
			return strings.Compare(a.ID, b.ID)
		})
		row := graphWorkflowFinding{
			Text:     graphNodeLocator(nodes[citing.ID]) + " 引用 " + graphNodeLocator(nodes[cited.ID]) + graphPaperYears(cited.Year),
			Severity: "warning",
			Links:    []graphWorkflowLink{graphPaperReaderLink(citing, project), graphPaperReaderLink(cited, project)},
		}
		if len(edge.Occurrences) > 0 {
			row.Links[0] = graphCitationSourceLink(citing, project, edge.Occurrences[0])
		}
		for _, paper := range newer[:min(5, len(newer))] {
			row.Text += " · 较新扩展 " + graphNodeLocator(nodes[paper.ID]) + graphPaperYears(paper.Year)
			row.Links = append(row.Links, graphPaperReaderLink(paper, project))
		}
		result.Findings = append(result.Findings, row)
	}
	if len(result.Findings) == 0 {
		result.Notice += " 当前未发现满足条件的引文。"
	}
	return result
}

func graphReadingFindings(ctx context.Context, q graphQuery, project string, nodes map[string]graphNode, edges []graphEdge, papers []Paper, year int) (graphWorkflowResult, error) {
	index := graphPaperIndex(papers)
	core := map[string]bool{}
	for _, paper := range papers {
		if slices.Contains(paper.CoreProjectIDs, project) {
			core[paper.ID] = true
		}
	}
	traversalNodes := nodes
	traversalEdges := edges
	if len(core) > 0 && slices.Contains(index[q.focus].ProjectIDs, project) && q.depth >= 2 {
		// An explicit core designation is a separate reason to read a project
		// paper. The internal hop lets it coexist with recorded references and
		// methods without projecting an apparent paper-to-paper citation.
		traversalNodes = make(map[string]graphNode, len(nodes)+1)
		for id, node := range nodes {
			traversalNodes[id] = node
		}
		projectNode := "project:" + project
		traversalNodes[projectNode] = graphNode{projectNode, "", "project"}
		q.nodeKinds = append(q.nodeKinds, "project")
		q.edgeKinds = append(q.edgeKinds, "belongs-to")
		traversalEdges = append(slices.Clone(edges), graphEdge{Source: q.focus, Target: projectNode, Kind: "belongs-to"})
		for _, node := range graphNodesByID(nodes) {
			if core[node.ID] && node.ID != q.focus {
				traversalEdges = append(traversalEdges, graphEdge{Source: node.ID, Target: projectNode, Kind: "belongs-to"})
			}
		}
	}
	graph, err := q.run(ctx, traversalNodes, traversalEdges)
	if err != nil {
		return graphWorkflowResult{}, err
	}
	candidates := map[string]int{}
	for _, node := range graph.Nodes {
		if node.Kind == "paper" {
			candidates[node.ID] = 0
		}
	}
	dependents := map[string][]string{}
	dependencies := map[[2]string]bool{}
	scores := map[string]float64{}
	reasons := map[string]string{}
	for _, edge := range edges {
		_, to := candidates[edge.Target]
		_, from := candidates[edge.Source]
		if edge.Kind == "cites" {
			if from {
				scores[edge.Source]++
			}
			if to {
				scores[edge.Target]++
			}
			if edge.Source == q.focus {
				reasons[edge.Target] = "起点论文引用的前置文献"
			}
			if edge.Target == q.focus && reasons[edge.Source] == "" {
				reasons[edge.Source] = "引用起点论文的后续文献"
			}
		}
		pair := [2]string{edge.Source, edge.Target}
		if from && to && (edge.Kind == "cites" || edge.Kind == "extends") && !dependencies[pair] {
			dependencies[pair] = true
			candidates[edge.Source]++
			dependents[edge.Target] = append(dependents[edge.Target], edge.Source)
		}
	}
	ids := make([]string, 0, len(candidates))
	for id := range candidates {
		ids = append(ids, id)
		paper := index[id]
		if paper.Year > 0 {
			scores[id] += 1.0 / float64(max(year-paper.Year+1, 1))
		}
		if slices.Contains(paper.ProjectIDs, project) {
			scores[id] += 1.5
		}
	}
	scores[q.focus] += 2
	rank := func(a, b string) int {
		if scores[a] > scores[b] {
			return -1
		}
		if scores[a] < scores[b] {
			return 1
		}
		return strings.Compare(a, b)
	}
	slices.SortFunc(ids, rank)
	ready := make([]string, 0, len(ids))
	for _, id := range ids {
		if candidates[id] == 0 {
			ready = append(ready, id)
		}
	}
	for i := 0; i < len(ready); i++ {
		group := dependents[ready[i]]
		slices.SortFunc(group, rank)
		for _, id := range group {
			candidates[id]--
			if candidates[id] == 0 {
				ready = append(ready, id)
			}
		}
	}
	result := graphWorkflowResult{Title: "项目图谱 · 阅读顺序（前置论文优先）"}
	if len(ready) < len(ids) {
		result.Notice = "部分引用或扩展关系构成环，请核对这些条目的顺序。"
		for _, id := range ids {
			if candidates[id] > 0 {
				ready = append(ready, id)
			}
		}
	}
	for _, id := range ready {
		reason := reasons[id]
		switch {
		case id == q.focus:
			reason = "所选起点论文"
		case reason != "":
		case core[id]:
			reason = "项目核心论文"
		default:
			reason = "由已记录的引用、扩展或方法关系找到"
		}
		result.Findings = append(result.Findings, graphWorkflowFinding{
			Text:  graphNodeLocator(nodes[id]) + graphPaperYears(index[id].Year) + " · " + reason,
			Links: []graphWorkflowLink{graphFindingNode(nodes[id])},
		})
	}
	return result, nil
}
