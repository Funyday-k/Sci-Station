package desktop

import (
	"encoding/hex"
	"net/http"
	"sort"
	"strconv"
	"strings"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/meeting"
)

type labRunConfiguration struct {
	Model        string              `json:"model,omitempty"`
	ModelSource  string              `json:"model_source,omitempty"`
	Effort       string              `json:"effort,omitempty"`
	Preset       string              `json:"preset,omitempty"`
	Phase        string              `json:"phase,omitempty"`
	Transport    string              `json:"transport,omitempty"`
	Timeout      int                 `json:"timeout,omitempty"`
	MaxSteps     int                 `json:"max_steps,omitempty"`
	MaxChildren  int                 `json:"max_children"`
	MayEditFiles bool                `json:"may_edit_files"`
	Budget       *meeting.ToolBudget `json:"budget,omitempty"`
	Prompt       *labRunPrompt       `json:"prompt,omitempty"`
}

type labRunPrompt struct {
	ID      string                `json:"id"`
	Version int                   `json:"version"`
	Surface meeting.PromptSurface `json:"surface"`
	Digest  string                `json:"digest"`
}

type labRunVersion struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

type labRunSource struct {
	labEvidenceReference
	ReadStatus string `json:"read_status,omitempty"`
}

type labRunEvent struct {
	Kind        string `json:"kind"`
	At          string `json:"at"`
	Detail      string `json:"detail,omitempty"`
	FileVersion string `json:"file_version,omitempty"`
}

type labRunInspection struct {
	Number        int                           `json:"number"`
	Record        *meeting.LabRunRecord         `json:"record,omitempty"`
	Status        string                        `json:"status"`
	Scope         string                        `json:"scope"`
	StartedAt     string                        `json:"started_at,omitempty"`
	Topic         string                        `json:"topic"`
	Note          string                        `json:"note,omitempty"`
	Configuration labRunConfiguration           `json:"configuration"`
	Rules         *[]meeting.ProjectRuleVersion `json:"rules,omitempty"`
	Plugins       []labRunVersion               `json:"plugins"`
	Files         []labRunVersion               `json:"files"`
	Sources       []labRunSource                `json:"sources"`
	Timeline      []labRunEvent                 `json:"timeline"`
}

func labRunScope(r *http.Request) meeting.LabScope {
	query := r.URL.Query()
	switch query.Get("scope") {
	case "global":
		if query.Get("project") == "" {
			return meeting.LabScope{Global: true}
		}
	case "":
		return meeting.LabScope{ProjectID: query.Get("project")}
	}
	return meeting.LabScope{}
}

func labAuditText(s string) string {
	if credentials.ContainsSecret(s) {
		return "[已隐藏疑似凭证]"
	}
	return s
}

func inspectLabRun(room *meeting.Session, round meeting.Round) labRunInspection {
	result := labRunInspection{Number: round.Number, Status: "unknown", Scope: "project", StartedAt: round.CreatedAt,
		Topic: labAuditText(room.Topic), Note: labAuditText(round.Note), Rules: round.ProjectRules, Plugins: []labRunVersion{}, Files: []labRunVersion{},
		Sources: []labRunSource{}, Timeline: []labRunEvent{}}
	if room.ProjectID == "" {
		result.Scope = "global"
	}
	if round.LabRun != nil && round.LabRun.Version == 1 {
		result.Record = round.LabRun
	}
	settings := round.Settings
	result.Configuration = labRunConfiguration{Preset: round.Preset, Phase: round.Phase, Timeout: settings.Timeout,
		MaxSteps: settings.MaxSteps, MaxChildren: settings.MaxChildren, Transport: settings.CodexTransport,
		MayEditFiles: settings.AllowEdits, Budget: settings.ToolBudget}
	if prompt := round.PromptOverride; prompt != nil {
		result.Configuration.Prompt = &labRunPrompt{ID: prompt.ID, Version: prompt.Version, Surface: prompt.Surface, Digest: prompt.Digest}
	}
	if len(round.Turns) == 1 {
		turn := round.Turns[0]
		result.Status = turn.Status
		result.Configuration.Model = round.RecordedTurnModel(turn)
		result.Configuration.ModelSource = turn.ModelSource
		result.Configuration.Effort = turn.Effort
		if result.Configuration.Effort == "" {
			result.Configuration.Effort = settings.Efforts[turn.Seat]
		}
		for path, f := range turn.Reads {
			result.Files = append(result.Files, labRunVersion{Name: labAuditText(path), Version: f.Version})
		}
		sort.Slice(result.Files, func(i, j int) bool { return result.Files[i].Name < result.Files[j].Name })
	}
	for _, plugin := range round.PluginGuidance {
		result.Plugins = append(result.Plugins, labRunVersion{Name: plugin.Name, Version: plugin.Version})
	}
	for _, event := range room.Events {
		if event.Round != round.Number {
			continue
		}
		kind := labEventKind(event.Type)
		if kind != "other" && kind != "board" && kind != "agenda" {
			result.Timeline = append(result.Timeline, labRunEvent{Kind: kind, At: event.At, Detail: labAuditText(event.Detail), FileVersion: event.FileVersion})
		}
		switch kind {
		case "cancel_requested":
			if result.Status == "error" {
				result.Status = "cancelled"
			}
		case "recovered", "shutdown_requested":
			if result.Status == "error" {
				result.Status = "interrupted"
			}
		}
	}
	refs := labReferenceIndex(labRecordedReferences(room, round.Number, ""))
	for _, source := range room.CitationMaterials(round.Number) {
		ref := refs[source.CitationID]
		if ref.ID == "" {
			ref = labEvidenceReference{ID: source.CitationID, Title: source.Name, Status: "unavailable"}
		}
		result.Sources = append(result.Sources, labRunSource{labEvidenceReference: ref, ReadStatus: source.ReadStatus})
	}
	return result
}

func (a *apiServer) serveLabRun(w http.ResponseWriter, r *http.Request, id string) {
	decoded, err := hex.DecodeString(id)
	if err != nil || len(decoded) != 16 || id != strings.ToLower(id) {
		http.NotFound(w, r)
		return
	}
	if a.meetings == nil {
		reject(w, 503, "未打开会话存档")
		return
	}
	scope := labRunScope(r)
	w.Header().Set("Cache-Control", "no-store")
	switch r.Method {
	case http.MethodGet:
		number, err := strconv.Atoi(r.URL.Query().Get("round"))
		if err != nil || number < 1 {
			reject(w, 400, "请选择要查看的轮次")
			return
		}
		room, err := a.meetings.LabRunSession(scope, id)
		if err != nil {
			fail(w, err)
			return
		}
		for _, round := range room.Rounds {
			if round.Number == number {
				reply(w, 200, inspectLabRun(room, round))
				return
			}
		}
		reject(w, 404, "未找到此运行")
	case http.MethodPost:
		if !scope.Global && scope.ProjectID == "" {
			reject(w, 404, "未找到所选范围内的单席会话")
			return
		}
		var input struct {
			Expected *int `json:"expected_round"`
		}
		if !jsonBody(w, r, &input) {
			return
		}
		if input.Expected == nil || *input.Expected < 0 {
			reject(w, 400, "需要当前轮号")
			return
		}
		lab := a.research
		if lab == nil {
			reject(w, 503, "未打开科研工作区")
			return
		}
		if scope.Global && !checkLabModule(w, lab, "") || !scope.Global && !checkLabProject(w, lab, scope.ProjectID) {
			return
		}
		next, err := a.meetings.RetryLabRun(scope, id, *input.Expected)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, 202, next)
	default:
		w.Header().Set("Allow", "GET, POST")
		reject(w, 405, "请查看或重试运行")
	}
}
