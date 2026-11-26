package research

import (
	"errors"
	"path/filepath"
	"slices"

	"scistation.local/desktop/internal/workspace"
)

type CreationTemplate struct {
	ID           string             `json:"id"`
	Title        string             `json:"title"`
	ChineseTitle string             `json:"chineseTitle"`
	Available    bool               `json:"available"`
	Modules      []moduleDefinition `json:"modules"`
}

func CreationTemplates() []CreationTemplate {
	basic := CreationTemplate{ID: "minimal-workspace", Title: "Minimal Workspace", ChineseTitle: "精简工作区", Available: true}
	review := CreationTemplate{ID: "literature-review", Title: "Literature Review", ChineseTitle: "文献综述", Available: true}
	for _, module := range workspaceModules {
		if !module.Placeholder {
			review.Modules = append(review.Modules, module)
		}
		if slices.Contains([]string{"projects", "wiki", "tasks", "calendar", "ai-lab"}, module.ID) {
			basic.Modules = append(basic.Modules, module)
		}
	}
	return []CreationTemplate{
		basic, review,
		{ID: "code-research", Title: "Code Research", ChineseTitle: "代码研究"},
		{ID: "theory-notes", Title: "Theory Notes", ChineseTitle: "理论笔记"},
		{ID: "writing-desk", Title: "Writing Desk", ChineseTitle: "论文写作"},
	}
}

// Configure only a private, freshly staged repository. An ordinary root starts
// with a default project. Sample notes are specifically requested data.
func (s *Service) ConfigureNewWorkspace(id, name string, sample bool, finalResearchDir string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.projects) != 0 {
		return errors.New("a workspace template requires an empty repository")
	}
	for _, template := range CreationTemplates() {
		if template.ID != id || !template.Available {
			continue
		}
		config, err := s.readModuleConfig("")
		if err != nil {
			return err
		}
		for _, m := range workspaceModules {
			config.enabled[m.ID] = false
		}
		for _, m := range template.Modules {
			config.enabled[m.ID] = true
		}
		if err = s.saveModuleConfig(config); err != nil {
			return err
		}
		p := newProject()
		p.Name = name
		p.Description = "Default project for this research root."
		p.ManagedDirectory = true
		if sample {
			p.Name = "Sample · " + name
			p.Description = "Example workspace. These practice notes have no paper or evidence references."
			p.IconName, p.ColorHex = "books.vertical", "#B8E0D2"
		}
		p.Path = filepath.Join(finalResearchDir, "workspaces", p.ID)
		if err := workspace.ManagedMkdir(s.managedDirectory(p.ID, false), 0700); err != nil {
			return err
		}
		d := newProjectData(p)
		if !sample {
			return s.commit(d)
		}
		for _, example := range []struct{ title, namespace, body string }{
			{"Sample · Research context", "", "# Research context (sample)\n\nUse this practice notebook to outline a question and link your own reading notes."},
			{"Sample · Attention mechanism", "concepts", "A concept note can collect definitions and questions. Link related notes by title."},
			{"Sample · Paper note", "papers", "## Citation\n\nAdd a real paper from your library.\n\n## Method\n\nDescribe the method in your own words.\n\n## Open questions\n\nRecord what you still want to verify."},
		} {
			n := Note{Entity: fresh(), ProjectID: p.ID, Title: example.title, Namespace: example.namespace, Body: example.body, Tags: []string{"sample"}, Evidence: []Evidence{}}
			d.Notes[n.ID] = n
		}
		return s.commit(d)
	}
	return errors.New("unknown workspace template")
}
