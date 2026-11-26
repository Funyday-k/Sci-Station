package research

import (
	"context"
	"errors"
	"net/url"
	"slices"
	"strconv"
)

type graphQuery struct {
	focus, target string
	depth         int
	direction     string
	edgeKinds     []string
	nodeKinds     []string
}

type graphPath struct {
	Found bool     `json:"found"`
	Nodes []string `json:"nodes,omitempty"`
}

func parseGraphQuery(values url.Values) (graphQuery, error) {
	q := graphQuery{focus: values.Get("focus"), target: values.Get("target"),
		depth: 2, direction: values.Get("direction"), edgeKinds: values["kind"], nodeKinds: values["nodeKind"]}
	if q.target != "" && q.focus == "" {
		return q, errors.New("请先选择路径起点")
	}
	if q.target != "" {
		q.depth = 6
	}
	if raw := values.Get("depth"); raw != "" {
		depth, err := strconv.Atoi(raw)
		if err != nil || depth < 0 || depth > 10 {
			return q, errors.New("图谱深度须为 0 到 10")
		}
		q.depth = depth
	}
	switch q.direction {
	case "", "both", "outgoing", "incoming":
	default:
		return q, errors.New("无效的关系方向")
	}
	for _, kind := range q.edgeKinds {
		switch kind {
		case "cites", "possible-cites", "evidence", "wikilink", "paper", "reading", "related", "supports", "contradicts", "extends", "uses":
		default:
			return q, errors.New("无效的关系类型")
		}
	}
	for _, kind := range q.nodeKinds {
		switch kind {
		case "note", "method", "paper", "reference", "task", "meeting", "missing":
		default:
			return q, errors.New("无效的条目类型")
		}
	}
	return q, nil
}

func (q graphQuery) run(ctx context.Context, nodes map[string]graphNode, edges []graphEdge) (graphResult, error) {
	result := graphResult{Nodes: []graphNode{}, Edges: []graphEdge{}}
	selected := map[string]graphNode{}
	for id, n := range nodes {
		if id == q.focus || id == q.target || len(q.nodeKinds) == 0 || slices.Contains(q.nodeKinds, n.Kind) {
			selected[id] = n
		}
	}
	filtered := make([]graphEdge, 0, len(edges))
	for _, edge := range edges {
		_, from := selected[edge.Source]
		_, to := selected[edge.Target]
		unfiltered := len(q.edgeKinds) == 0 && (q.focus == "" || edge.Kind != "possible-cites")
		if from && to && (unfiltered || slices.Contains(q.edgeKinds, edge.Kind)) {
			filtered = append(filtered, edge)
		}
	}
	if q.focus == "" {
		result.Nodes = graphNodesByID(selected)
		result.Edges = filtered
		return result, nil
	}
	if _, ok := selected[q.focus]; !ok {
		return result, errors.New("起点没有出现在项目图谱中")
	}
	if _, ok := selected[q.target]; q.target != "" && !ok {
		return result, errors.New("终点没有出现在项目图谱中")
	}
	result.Hops = map[string]int{q.focus: 0}
	if q.target == q.focus {
		result.Path = &graphPath{Found: true, Nodes: []string{q.focus}}
		result.Nodes = append(result.Nodes, selected[q.focus])
		return result, nil
	}
	adjacent := map[string][]int{}
	for i, edge := range filtered {
		if q.direction != "incoming" {
			adjacent[edge.Source] = append(adjacent[edge.Source], i)
		}
		if q.direction != "outgoing" && (q.direction == "incoming" || edge.Target != edge.Source) {
			adjacent[edge.Target] = append(adjacent[edge.Target], i)
		}
	}
	queue := []string{q.focus}
	used := map[int]bool{}
	parent := map[string]graphStep{}
	for i := 0; i < len(queue); i++ {
		if err := ctx.Err(); err != nil {
			return graphResult{}, err
		}
		source := queue[i]
		depth := result.Hops[source]
		if depth >= q.depth {
			continue
		}
		for _, index := range adjacent[source] {
			used[index] = true
			edge := filtered[index]
			target := edge.Target
			if target == source {
				target = edge.Source
			}
			if _, seen := result.Hops[target]; seen {
				continue
			}
			result.Hops[target] = depth + 1
			parent[target] = graphStep{source, index}
			if target == q.target {
				return makeGraphPath(q.focus, target, selected, filtered, parent), nil
			}
			queue = append(queue, target)
		}
	}
	for _, id := range queue {
		result.Nodes = append(result.Nodes, selected[id])
	}
	for i, edge := range filtered {
		if used[i] {
			result.Edges = append(result.Edges, edge)
		}
	}
	if q.target != "" {
		result.Path = &graphPath{}
		// The endpoints stay visible when the current filters disconnect them.
		result.Nodes = []graphNode{selected[q.focus], selected[q.target]}
		result.Edges = []graphEdge{}
		result.Hops = nil
	}
	return result, nil
}

func graphNodesByID(nodes map[string]graphNode) []graphNode {
	return valuesBy(nodes, func(a, b graphNode) bool { return a.ID < b.ID })
}

type graphStep struct {
	prev string
	edge int
}

func makeGraphPath(start, end string, nodes map[string]graphNode, edges []graphEdge, parents map[string]graphStep) graphResult {
	result := graphResult{Hops: map[string]int{}, Path: &graphPath{Found: true}}
	for id := end; id != start; {
		step := parents[id]
		result.Path.Nodes = append(result.Path.Nodes, id)
		result.Edges = append(result.Edges, edges[step.edge])
		id = step.prev
	}
	result.Path.Nodes = append(result.Path.Nodes, start)
	slices.Reverse(result.Path.Nodes)
	slices.Reverse(result.Edges)
	for i, id := range result.Path.Nodes {
		result.Hops[id] = i
		result.Nodes = append(result.Nodes, nodes[id])
	}
	return result
}
