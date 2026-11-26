package research

import (
	"encoding/json"
	"errors"
	"net/http"
	"path/filepath"
	"regexp"
	"slices"
)

type shellLayout struct {
	Mode              string   `json:"mode"`
	PanelPinned       bool     `json:"panelPinned"`
	Width             int      `json:"width"`
	TreeExpanded      bool     `json:"treeExpanded"`
	TopOrder          []string `json:"topOrder"`
	TabOrder          []string `json:"tabOrder"`
	PinnedProjects    []string `json:"pinnedProjects"`
	CollapsedProjects []string `json:"collapsedProjects"`
}

func readShellLayout(fields map[string]json.RawMessage) (shellLayout, error) {
	state := shellLayout{Mode: "hidden", Width: 360, TreeExpanded: true, TopOrder: []string{}, TabOrder: []string{}, PinnedProjects: []string{}, CollapsedProjects: []string{}}
	if raw, ok := fields["shellLayout"]; ok {
		// Previous releases opened the inspector by default. Only a saved AI
		// mode is unambiguously a deliberate choice in those layouts.
		stored := struct {
			*shellLayout
			PinPreference *bool `json:"panelPinned"`
		}{shellLayout: &state}
		if json.Unmarshal(raw, &stored) != nil || !slices.Contains([]string{"inspector", "ai", "hidden"}, state.Mode) || state.Width < 200 || state.Width > 640 {
			return state, errors.New("invalid shell layout")
		}
		state.PanelPinned = state.Mode == "ai"
		if stored.PinPreference != nil {
			state.PanelPinned = *stored.PinPreference
		}
	}
	return state, nil
}

type shellLayoutChange struct {
	Mode         *string   `json:"mode"`
	PanelPinned  *bool     `json:"panelPinned"`
	Width        *int      `json:"width"`
	TreeExpanded *bool     `json:"treeExpanded"`
	TopOrder     *[]string `json:"topOrder"`
	TabOrder     *[]string `json:"tabOrder"`
	ProjectID    string    `json:"projectId"`
	Pinned       *bool     `json:"pinned"`
	Collapsed    *bool     `json:"collapsed"`
}

var shellSectionID = regexp.MustCompile(`^[a-z][a-z0-9-]{0,63}$`)

func uniqueShellIDs(ids []string) bool {
	if len(ids) > 128 {
		return false
	}
	seen := map[string]bool{}
	for _, id := range ids {
		if !shellSectionID.MatchString(id) || seen[id] {
			return false
		}
		seen[id] = true
	}
	return true
}

func setShellID(ids []string, id string, present bool) []string {
	if !present {
		return slices.DeleteFunc(ids, func(s string) bool { return s == id })
	}
	if slices.Contains(ids, id) {
		return ids
	}
	return append(ids, id)
}

func (s *Service) shellLayout(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	language, fields, err := s.readInterface()
	if err != nil {
		jsonFail(w, 500, "无法读取界面偏好")
		return
	}
	state, err := readShellLayout(fields)
	if err != nil {
		jsonFail(w, 500, "无法读取工作区布局")
		return
	}
	if r.Method == http.MethodGet {
		jsonReply(w, 200, state)
		return
	}
	var in shellLayoutChange
	if !payload(w, r, &in) {
		return
	}
	if (in.Mode != nil && !slices.Contains([]string{"inspector", "ai", "hidden"}, *in.Mode)) ||
		(in.Width != nil && (*in.Width < 200 || *in.Width > 640)) ||
		(in.TopOrder != nil && !uniqueShellIDs(*in.TopOrder)) || (in.TabOrder != nil && !uniqueShellIDs(*in.TabOrder)) {
		jsonFail(w, 400, "无效的工作区布局")
		return
	}
	if in.Pinned != nil || in.Collapsed != nil {
		if !s.activeModuleProject(in.ProjectID) {
			jsonFail(w, 404, "科研项目不存在")
			return
		}
	}
	if in.Mode != nil {
		state.Mode = *in.Mode
	}
	if in.PanelPinned != nil {
		state.PanelPinned = *in.PanelPinned
	}
	if state.Mode == "hidden" {
		state.PanelPinned = false
	}
	if in.Width != nil {
		state.Width = *in.Width
	}
	if in.TreeExpanded != nil {
		state.TreeExpanded = *in.TreeExpanded
	}
	if in.TopOrder != nil {
		state.TopOrder = *in.TopOrder
	}
	if in.TabOrder != nil {
		state.TabOrder = *in.TabOrder
	}
	if in.Pinned != nil {
		state.PinnedProjects = setShellID(state.PinnedProjects, in.ProjectID, *in.Pinned)
	}
	if in.Collapsed != nil {
		state.CollapsedProjects = setShellID(state.CollapsedProjects, in.ProjectID, *in.Collapsed)
	}
	// Preserve unknown settings on this root, including future layout fields.
	stored := map[string]json.RawMessage{}
	if raw, ok := fields["shellLayout"]; ok {
		if json.Unmarshal(raw, &stored) != nil || stored == nil {
			jsonFail(w, 500, "无法更新工作区布局")
			return
		}
	}
	known, _ := json.Marshal(state)
	if err = json.Unmarshal(known, &stored); err != nil {
		jsonFail(w, 500, "无法更新工作区布局")
		return
	}
	fields["language"], _ = json.Marshal(language)
	fields["shellLayout"], _ = json.Marshal(stored)
	out, err := json.MarshalIndent(fields, "", "  ")
	if err != nil || atomicWrite(filepath.Join(s.dir, interfaceSettingsFile), append(out, '\n')) != nil {
		jsonFail(w, 500, "无法保存工作区布局")
		return
	}
	jsonReply(w, 200, state)
}
