package desktop

import (
	"errors"
	"net/http"
	"os"
	"slices"
	"strings"

	"scistation.local/desktop/internal/research"
)

type labSkillStatus struct {
	research.LabSkillText
	Trusted bool `json:"trusted"`
	Enabled bool `json:"enabled"`
	Invalid bool `json:"invalid,omitempty"`
}

type labContextResponse struct {
	Connections []research.LabConnector `json:"connections,omitempty"`
	Revision    int                     `json:"revision"`
	Endpoint    string                  `json:"endpoint"`
	MCPEnabled  bool                    `json:"mcpEnabled"`
	Skills      []labSkillStatus        `json:"skills"`
}

type labContextEdit struct {
	ProjectID string `json:"projectId"`
	Revision  int    `json:"revision"`
	Operation string `json:"operation"`
	Confirmed bool   `json:"confirmed"`
	Endpoint  string `json:"endpoint"`
	ID        string `json:"id"`
	Digest    string `json:"digest"`
	Value     bool   `json:"value"`
	Markdown  string `json:"markdown"`
}

func labContextSummary(config research.LabSettings) labContextResponse {
	out := labContextResponse{Revision: config.Revision, Endpoint: config.Endpoint, MCPEnabled: config.MCPEnabled, Skills: []labSkillStatus{}}
	for _, row := range config.Skills {
		skill, err := row.Parse()
		if err != nil {
			skill = research.LabSkillText{ID: row.ID, Name: row.ID, Digest: row.Digest}
		}
		skill.Body = ""
		out.Skills = append(out.Skills, labSkillStatus{
			LabSkillText: skill, Enabled: row.Enabled, Invalid: err != nil, Trusted: err == nil && row.Digest == row.TrustedHash,
		})
	}
	return out
}

func checkLabProject(w http.ResponseWriter, lab *research.Service, project string) bool {
	if project == "" || !lab.HasActiveProject(project) {
		reject(w, 404, "科研项目不存在或已归档")
		return false
	}
	return checkLabModule(w, lab, project)
}

func checkLabModule(w http.ResponseWriter, lab *research.Service, project string) bool {
	enabled, err := lab.ModuleEnabled(project, "ai-lab")
	if err != nil {
		reject(w, 503, "无法读取 AI 实验室模块设置")
		return false
	}
	if !enabled {
		reject(w, 409, "当前范围的 AI 实验室模块已停用")
		return false
	}
	return true
}

func labContextError(w http.ResponseWriter, err error) {
	var pathError *os.PathError
	switch {
	case errors.Is(err, os.ErrNotExist):
		reject(w, 404, "科研项目不存在或已归档")
	case errors.Is(err, research.ErrLabSettingsConflict), errors.Is(err, research.ErrLabSkillUntrusted):
		reject(w, 409, err.Error())
	case errors.As(err, &pathError):
		reject(w, 500, "无法保存项目实验室设置")
	default:
		reject(w, 422, err.Error())
	}
}

func editLabContext(config *research.LabSettings, input labContextEdit) error {
	if input.Operation == "mcp" {
		endpoint := strings.TrimSpace(input.Endpoint)
		if (endpoint != "" || input.Value) && !labEndpoint(endpoint) {
			return errors.New("仅可配置公开 HTTPS MCP 地址，地址不可包含查询参数或凭据")
		}
		config.Endpoint = endpoint
		config.MCPEnabled = input.Value
		return nil
	}
	index := slices.IndexFunc(config.Skills, func(skill research.LabSkill) bool { return skill.ID == input.ID })
	if input.Operation == "install" {
		skill, err := research.ParseLabSkill(input.Markdown)
		if err != nil {
			return err
		}
		if skill.ID != input.ID || skill.Digest != input.Digest {
			return research.ErrLabSettingsConflict
		}
		if index >= 0 || len(config.Skills) >= 32 {
			return errors.New("已导入同名技能或项目技能目录已满")
		}
		config.Skills = append(config.Skills, research.LabSkill{ID: skill.ID, Digest: skill.Digest, Markdown: input.Markdown})
		return nil
	}
	if index < 0 || input.Digest == "" || config.Skills[index].Digest != input.Digest {
		return research.ErrLabSettingsConflict
	}
	skill := &config.Skills[index]
	switch input.Operation {
	case "trust":
		if input.Value {
			if _, err := skill.Parse(); err != nil {
				return err
			}
			skill.TrustedHash = input.Digest
		} else {
			skill.TrustedHash = ""
		}
	case "enable":
		if input.Value {
			if _, err := skill.Parse(); err != nil {
				return err
			}
		}
		skill.Enabled = input.Value
	case "remove":
		config.Skills = slices.Delete(config.Skills, index, index+1)
	default:
		return errors.New("未知的项目实验室设置操作")
	}
	return nil
}

func (a *apiServer) serveLabContext(w http.ResponseWriter, r *http.Request, path string) {
	lab := a.research
	if lab == nil {
		reject(w, 503, "未打开科研工作区")
		return
	}
	if path == "context" && r.Method == http.MethodGet {
		project := r.URL.Query().Get("project")
		if !checkLabProject(w, lab, project) {
			return
		}
		config, err := lab.LabSettings(project)
		if err != nil {
			labContextError(w, err)
			return
		}
		reply(w, 200, labContextSummary(config))
		return
	}
	if !(path == "context" && r.Method == http.MethodPatch ||
		(path == "context/preview" || path == "context/skill" || path == "context/resolve") && r.Method == http.MethodPost) {
		reject(w, 405, "不支持此设置操作")
		return
	}
	var in labContextEdit
	if !jsonBody(w, r, &in) || !checkLabProject(w, lab, in.ProjectID) {
		return
	}
	switch path {
	case "context":
		if !in.Confirmed {
			reject(w, 403, "更改前请确认当前项目和操作")
			return
		}
		config, err := lab.EditLabSettings(in.ProjectID, in.Revision, func(config *research.LabSettings) error {
			return editLabContext(config, in)
		})
		if err != nil {
			labContextError(w, err)
			return
		}
		reply(w, 200, labContextSummary(config))
	case "context/preview":
		skill, err := research.ParseLabSkill(in.Markdown)
		if err != nil {
			labContextError(w, err)
			return
		}
		reply(w, 200, skill)
	case "context/skill", "context/resolve":
		config, err := lab.LabSettings(in.ProjectID)
		if err != nil {
			labContextError(w, err)
			return
		}
		index := slices.IndexFunc(config.Skills, func(skill research.LabSkill) bool { return skill.ID == in.ID && skill.Digest == in.Digest })
		if index < 0 {
			labContextError(w, research.ErrLabSettingsConflict)
			return
		}
		stored := config.Skills[index]
		skill, err := stored.Parse()
		if path == "context/resolve" {
			skill, err = stored.Resolve(in.Digest)
			body := []rune(skill.Body)
			if len(body) > 8000 {
				skill.Body = string(body[:8000]) + "\n[后续正文省略]"
			}
		}
		if err != nil {
			labContextError(w, err)
			return
		}
		reply(w, 200, skill)
	}
}
