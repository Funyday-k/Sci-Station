package research

import (
	"maps"
	"net/http"
	"strings"
)

type GraphRelation struct {
	Entity
	Source string `json:"source"`
	Target string `json:"target"`
	Kind   string `json:"kind"`
	Label  string `json:"label,omitempty"`
}

func (s *Service) relations(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Source string `json:"source"`
		Target string `json:"target"`
		Kind   string `json:"kind"`
		Label  string `json:"label"`
	}
	if r.Method == "POST" && !payload(w, r, &in) {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	if !ok {
		return
	}
	d.Relations = maps.Clone(d.Relations)
	if r.Method == "DELETE" {
		id := r.PathValue("relation")
		rel, ok := d.Relations[id]
		if !found(w, ok) || !revisionOK(w, rel.Revision, queryRevision(r.URL.Query())) {
			return
		}
		delete(d.Relations, id)
		if s.save(w, d) {
			w.WriteHeader(204)
		}
		return
	}
	in.Label = strings.TrimSpace(in.Label)
	if (in.Kind != "related" && in.Kind != "supports" && in.Kind != "contradicts" && in.Kind != "extends") || in.Source == in.Target || (in.Label != "" && !label(in.Label, 240)) {
		jsonFail(w, 400, "关系类型、目标或说明无效")
		return
	}
	nodes, _ := s.derivedGraph(r.Context(), d, s.visibleTasksLocked(d.Project.ID))
	if r.Context().Err() != nil {
		return
	}
	if _, ok := nodes[in.Source]; !ok {
		jsonFail(w, 400, "起点没有出现在项目图谱中")
		return
	}
	if _, ok := nodes[in.Target]; !ok {
		jsonFail(w, 400, "终点没有出现在项目图谱中")
		return
	}
	for _, rel := range d.Relations {
		if rel.Source == in.Source && rel.Target == in.Target && rel.Kind == in.Kind {
			jsonReply(w, 200, rel)
			return
		}
	}
	if d.Relations == nil {
		d.Relations = map[string]GraphRelation{}
	}
	rel := GraphRelation{Entity: fresh(), Source: in.Source, Target: in.Target, Kind: in.Kind, Label: in.Label}
	d.Relations[rel.ID] = rel
	if s.save(w, d) {
		jsonReply(w, 201, rel)
	}
}
