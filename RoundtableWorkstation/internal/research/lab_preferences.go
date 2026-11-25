package research

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"regexp"
	"slices"
	"strings"
	"unicode/utf8"

	"go.yaml.in/yaml/v3"

	"scistation.local/desktop/internal/credentials"
)

type LabSettings struct {
	Revision   int        `json:"revision"`
	Endpoint   string     `json:"endpoint,omitempty"`
	MCPEnabled bool       `json:"mcpEnabled"`
	Skills     []LabSkill `json:"skills"`
}

type LabSkill struct {
	ID          string `json:"id"`
	Digest      string `json:"digest"`
	TrustedHash string `json:"trustedHash,omitempty"`
	Enabled     bool   `json:"enabled"`
	Markdown    string `json:"markdown"`
}

type LabSkillText struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Description  string   `json:"description"`
	Author       string   `json:"author"`
	Version      string   `json:"version"`
	Risk         string   `json:"risk"`
	Capabilities []string `json:"capabilities"`
	AllowedTools []string `json:"allowedTools"`
	Digest       string   `json:"digest"`
	Body         string   `json:"body,omitempty"`
}

var (
	ErrLabSettingsConflict = errors.New("项目实验室设置已改变，请重新加载")
	ErrLabSkillUntrusted   = errors.New("技能已停用、内容已改变或尚未明确受信任")
	labSkillID             = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,95}$`)
)

func ParseLabSkill(markdown string) (LabSkillText, error) {
	if len(markdown) > 64<<10 || !utf8.ValidString(markdown) || strings.ContainsRune(markdown, 0) {
		return LabSkillText{}, errors.New("技能文件必须为不超过 64 KiB 的 UTF-8 Markdown")
	}
	if credentials.ContainsSecret(markdown) {
		return LabSkillText{}, errors.New("技能内容疑似包含凭据或私钥，无法导入")
	}
	text := strings.ReplaceAll(strings.TrimPrefix(markdown, "\uFEFF"), "\r\n", "\n")
	headerAndBody, ok := strings.CutPrefix(text, "---\n")
	if !ok {
		return LabSkillText{}, errors.New("技能 Markdown 缺少 YAML 元数据")
	}
	header, body, ok := strings.Cut(headerAndBody, "\n---\n")
	if !ok || len(header) > 12<<10 || strings.TrimSpace(body) == "" {
		return LabSkillText{}, errors.New("技能需要完整的 YAML 元数据及 Markdown 正文")
	}
	var meta struct {
		Name         string
		Description  string
		Author       string
		Version      string
		Risk         string
		Capabilities []string
		AllowedTools []string `yaml:"allowed_tools"`
	}
	if err := yaml.Unmarshal([]byte(header), &meta); err != nil {
		return LabSkillText{}, errors.New("技能 YAML 元数据无法解析")
	}
	meta.Name = strings.TrimSpace(meta.Name)
	meta.Description = strings.TrimSpace(meta.Description)
	if !labSkillID.MatchString(meta.Name) || meta.Description == "" || utf8.RuneCountInString(meta.Description) > 1500 {
		return LabSkillText{}, errors.New("技能需要有效名称和不超过 1,500 字的简介")
	}
	if meta.Risk != "" && meta.Risk != "readOnly" && meta.Risk != "read_only" {
		return LabSkillText{}, errors.New("仅支持用于科研指引的只读 Markdown 技能")
	}
	toolIDs := meta.AllowedTools
	for _, tool := range toolIDs {
		if strings.TrimSpace(tool) == "" || len(tool) > 120 {
			return LabSkillText{}, errors.New("技能工具声明无效")
		}
	}
	body = strings.TrimSpace(body)
	digest := sha256.Sum256([]byte(markdown))
	return LabSkillText{
		ID: strings.ToLower(meta.Name), Name: meta.Name, Description: meta.Description,
		Author: meta.Author, Version: meta.Version, Risk: "readOnly",
		Capabilities: meta.Capabilities, AllowedTools: toolIDs, Digest: hex.EncodeToString(digest[:]), Body: body,
	}, nil
}

func (stored LabSkill) Parse() (LabSkillText, error) {
	skill, err := ParseLabSkill(stored.Markdown)
	if err != nil || skill.ID != stored.ID || skill.Digest != stored.Digest {
		return LabSkillText{}, ErrLabSkillUntrusted
	}
	return skill, nil
}

func (stored LabSkill) Resolve(digest string) (LabSkillText, error) {
	if !stored.Enabled || digest == "" || digest != stored.Digest || digest != stored.TrustedHash {
		return LabSkillText{}, ErrLabSkillUntrusted
	}
	return stored.Parse()
}

func labSettingsSnapshot(d projectData) LabSettings {
	if d.Lab == nil {
		return LabSettings{Revision: 1, Skills: []LabSkill{}}
	}
	config := *d.Lab
	config.Skills = slices.Clone(config.Skills)
	return config
}

func (s *Service) LabSettings(project string) (LabSettings, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, found := s.projects[project]
	if !found || d.Archived || d.Trashed {
		return LabSettings{}, os.ErrNotExist
	}
	return labSettingsSnapshot(d), nil
}

func (s *Service) EditLabSettings(project string, revision int, edit func(*LabSettings) error) (LabSettings, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, found := s.projects[project]
	if !found || d.Archived || d.Trashed {
		return LabSettings{}, os.ErrNotExist
	}
	config := labSettingsSnapshot(d)
	if revision != config.Revision {
		return LabSettings{}, ErrLabSettingsConflict
	}
	if err := edit(&config); err != nil {
		return LabSettings{}, err
	}
	config.Revision++
	d.Lab = &config
	if err := s.commit(d); err != nil {
		if errors.Is(err, errProjectRecordChanged) {
			return LabSettings{}, ErrLabSettingsConflict
		}
		return LabSettings{}, err
	}
	return labSettingsSnapshot(d), nil
}
