// Package meeting coordinates persistent roundtables. The workspace is the sole editing channel.
package meeting

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/sessionstore"
	"scistation.local/desktop/internal/workspace"
)

var ErrConflict = errors.New("session conflict")

const maxInputCharacters = 12000

func ValidateTopic(topic string) error {
	if strings.TrimSpace(topic) == "" {
		return errors.New("请输入会议议题")
	}
	if utf8.RuneCountInString(topic) > maxInputCharacters {
		return fmt.Errorf("会议议题最多 %d 个字符", maxInputCharacters)
	}
	return nil
}

type Member struct {
	Version            int    `json:"version,omitempty"`
	ModelEpoch         int    `json:"model_epoch,omitempty"`
	PreviousModel      string `json:"previous_model,omitempty"`
	SwitchedAfterRound int    `json:"switched_after_round,omitempty"`
	ID                 string `json:"id"`
	Model              string `json:"model"`
	Label              string `json:"label"`
	Source             string `json:"source"`
	Effort             string `json:"effort"`
}

type Settings struct {
	ModelEpochs     map[string]int    `json:"model_epochs,omitempty"`
	CatalogModelIDs map[string]bool   `json:"catalog_model_ids,omitempty"`
	Efforts         map[string]string `json:"efforts,omitempty"`
	Models          map[string]string `json:"models"`
	ChildModels     map[string]string `json:"child_models"`
	CLIPaths        map[string]string `json:"cli_paths"`
	Timeout         int               `json:"timeout"`
	MaxChildren     int               `json:"max_children"`
	MaxSteps        int               `json:"max_steps"`
	AllowEdits      bool              `json:"allow_edits"`
	CodexTransport  string            `json:"codex_transport,omitempty"`
	MagpiePort      int               `json:"magpie_port,omitempty"`
}

type exactCatalogKey struct{}

// CatalogModelID resolves the exact model requested by this seat. Only older
// CLI configurations use a provider-prefixed shorthand.
func CatalogModelID(ctx context.Context, seat, model string) string {
	if exact, _ := ctx.Value(exactCatalogKey{}).(bool); exact {
		return model
	}
	return legacyCatalogID(seat, model)
}

type effortKey struct{}
type sessionKey struct{}

func ModelRequest(ctx context.Context) (effort, session string) {
	effort, _ = ctx.Value(effortKey{}).(string)
	session, _ = ctx.Value(sessionKey{}).(string)
	return
}

type codexRouteKey struct{}
type codexRoute struct {
	mode string
	port int
}

// CodexRoute returns the immutable transport selection captured for the current
// round. An empty mode and zero port preserve the native CLI default.
func CodexRoute(ctx context.Context) (mode string, port int) {
	if route, ok := ctx.Value(codexRouteKey{}).(codexRoute); ok {
		return route.mode, route.port
	}
	return "", 0
}

type Child struct {
	Effort      string `json:"effort,omitempty"`
	ID          string `json:"id"`
	Name        string `json:"name,omitempty"`
	Nickname    string `json:"nickname,omitempty"`
	DisplayName string `json:"display_name,omitempty"`
	Task        string `json:"task"`
	Model       string `json:"model"`
	Status      string `json:"status"`
	Text        string `json:"text"`
	Error       string `json:"error"`
	StartedAt   string `json:"started_at,omitempty"`
	FinishedAt  string `json:"finished_at,omitempty"`
}

type Turn struct {
	ModelLabel            string                    `json:"model_label,omitempty"`
	ModelSource           string                    `json:"model_source,omitempty"`
	ProposedBoardUpdates  []boardUpdate             `json:"proposed_board_updates,omitempty"`
	Points                []DiscussionPoint         `json:"points,omitempty"`
	Positions             []Position                `json:"positions,omitempty"`
	ProposedAgendaUpdates []agendaProposal          `json:"proposed_agenda_updates,omitempty"`
	Effort                string                    `json:"effort,omitempty"`
	Seat                  string                    `json:"seat"`
	Model                 string                    `json:"model"`
	Status                string                    `json:"status"`
	Text                  string                    `json:"text"`
	Error                 string                    `json:"error"`
	Children              []Child                   `json:"children"`
	Changes               []workspace.Change        `json:"changes"`
	Reads                 map[string]workspace.File `json:"reads"`
	StartedAt             string                    `json:"started_at,omitempty"`
	FinishedAt            string                    `json:"finished_at,omitempty"`
}

type ProjectRuleVersion struct {
	Path   string `json:"path"`
	Digest string `json:"digest"`
}

// ProjectRuleSnapshot describes the imported guidance fixed at round start.
// Only the version metadata is persisted. The guidance is held by the runner.
type ProjectRuleSnapshot struct {
	Versions []ProjectRuleVersion
	Guidance string
}

type Round struct {
	MaterialIDs       []string              `json:"material_ids,omitempty"`
	Checkpoint        *ContinuousCheckpoint `json:"checkpoint,omitempty"`
	Auto              bool                  `json:"auto,omitempty"`
	ProjectRules      *[]ProjectRuleVersion `json:"project_rules,omitempty"`
	PluginGuidance    []PluginGuidance      `json:"plugin_guidance,omitempty"`
	AgendaItemID      string                `json:"agenda_item_id,omitempty"`
	ProposedFollowups []AgendaInput         `json:"proposed_followups,omitempty"`
	Number            int                   `json:"number"`
	Preset            string                `json:"preset"`
	Phase             string                `json:"phase"`
	Note              string                `json:"note"`
	Target            string                `json:"target"`
	CreatedAt         string                `json:"created_at"`
	Turns             []Turn                `json:"turns"`
	Settings          Settings              `json:"settings"`
}

type Event struct {
	ID          int    `json:"id"`
	Type        string `json:"type"`
	Seat        string `json:"seat"`
	Detail      string `json:"detail"`
	At          string `json:"at"`
	Round       int    `json:"round,omitempty"`
	ChildID     string `json:"child_id,omitempty"`
	OperationID string `json:"operation_id,omitempty"`
	RawExcerpt  string `json:"raw_excerpt,omitempty"`
	Step        int    `json:"step,omitempty"`
}

// Operation is a write-ahead record. Unknown outcomes are inspected, never replayed.
type Operation struct {
	ID              string            `json:"id"`
	Seat            string            `json:"seat"`
	Round           int               `json:"round"`
	Path            string            `json:"path"`
	ExpectedVersion string            `json:"expected_version"`
	Text            string            `json:"text"`
	Status          string            `json:"status"`
	Error           string            `json:"error,omitempty"`
	Change          *workspace.Change `json:"change,omitempty"`
}

type UserChange struct {
	At     string           `json:"at"`
	Change workspace.Change `json:"change"`
}

type Session struct {
	SeatOverrides     map[string]Member `json:"seat_overrides,omitempty"`
	Board             MeetingBoard      `json:"board"`
	Materials         []Material        `json:"materials"`
	Continuous        *ContinuousState  `json:"continuous,omitempty"`
	Report            *MeetingReport    `json:"report,omitempty"`
	AgendaDraftStatus string            `json:"agenda_draft_status,omitempty"`
	AgendaDraftError  string            `json:"agenda_draft_error,omitempty"`
	Agenda            []AgendaItem      `json:"agenda,omitempty"`
	ActiveAgendaID    string            `json:"active_agenda_id,omitempty"`
	AgendaVersion     int               `json:"agenda_version"`
	Members           []Member          `json:"members,omitempty"`
	Preset            string            `json:"preset"`
	ID                string            `json:"id"`
	Topic             string            `json:"topic"`
	Title             string            `json:"title,omitempty"`
	ProjectID         string            `json:"project_id,omitempty"`
	Project           string            `json:"project"`
	Seats             []string          `json:"seats"`
	Status            string            `json:"status"`
	CreatedAt         string            `json:"created_at"`
	UpdatedAt         string            `json:"updated_at"`
	Rounds            []Round           `json:"rounds"`
	Events            []Event           `json:"events"`
	CancelRequested   bool              `json:"cancel_requested"`
	UserChanges       []UserChange      `json:"user_changes"`
	Operations        []Operation       `json:"operations"`
}

type Summary struct {
	SeatOverrides map[string]Member `json:"seat_overrides,omitempty"`
	Members       []Member          `json:"members,omitempty"`
	Preset        string            `json:"preset"`
	ID            string            `json:"id"`
	Topic         string            `json:"topic"`
	Title         string            `json:"title,omitempty"`
	ProjectID     string            `json:"project_id,omitempty"`
	Project       string            `json:"project"`
	Seats         []string          `json:"seats"`
	Status        string            `json:"status"`
	CreatedAt     string            `json:"created_at"`
	UpdatedAt     string            `json:"updated_at"`
	RoundCount    int               `json:"round_count"`
}

type Engine struct {
	presence            boardPresenceHub
	projectRuleSnapshot func(string) (ProjectRuleSnapshot, error)
	projectAccess       func(string, func(string) error) error
	pluginGuidance      func() ([]PluginGuidance, error)
	dir                 string
	call                func(context.Context, string, string, string, string) (string, error)
	settings            func() Settings
	mu                  sync.Mutex
	cancelMu            sync.Mutex
	cancels             map[string]context.CancelFunc
	activeRounds        map[string]int
	workers             sync.WaitGroup
	shuttingDown        bool
	backgroundErr       error
	agendaDraftCancels  map[string]context.CancelFunc
	reportCancels       map[string]context.CancelFunc
	titleFlights        map[string]*titleFlight // guarded by cancelMu, shared with Shutdown registration
}

func now() string { return time.Now().UTC().Format(time.RFC3339Nano) }
func newID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

func New(dir string, call func(context.Context, string, string, string, string) (string, error), settings func() Settings) (*Engine, error) {
	if call == nil || settings == nil {
		return nil, errors.New("model call and settings getter are required")
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	if err = workspace.ManagedMkdirAll(abs, 0700); err != nil {
		return nil, err
	}
	e := &Engine{dir: abs, call: call, settings: settings, cancels: make(map[string]context.CancelFunc), activeRounds: make(map[string]int)}
	if err := e.visitSessions(nil); err != nil {
		return nil, err
	}
	return e, nil
}

func (e *Engine) locked(fn func() error) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	f, err := workspace.ManagedOpenFile(filepath.Join(e.dir, ".meeting.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	return fn()
}

func (e *Engine) lease(id string) (*os.File, error) {
	f, err := workspace.ManagedOpenFile(filepath.Join(e.dir, id+".run.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) || errors.Is(err, syscall.EAGAIN) {
			return nil, nil
		}
		return nil, err
	}
	return f, nil
}
func release(f *os.File) {
	if f != nil {
		syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}
}
func (e *Engine) load(id string) (*Session, error) {
	var s Session
	if err := sessionstore.Read(e.dir, id, &s); err != nil {
		return nil, err
	}
	if s.ID != id {
		return nil, sessionstore.UnreadableFile(e.dir, id, "存档会话 ID 与文件名不符。")
	}
	if s.Preset == "" {
		s.Preset = "work"
	}
	if s.Materials == nil {
		s.Materials = []Material{}
	}
	for i := range s.Rounds {
		if s.Rounds[i].Preset == "" && s.Rounds[i].Phase == "" {
			s.Rounds[i].Preset, s.Rounds[i].Phase = "work", "work"
		}
	}
	ensureBoard(&s)
	return &s, nil
}
func (e *Engine) save(s *Session) error {
	ensureBoard(s)
	s.UpdatedAt = now()
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	if err := workspace.ManagedAtomicWrite(filepath.Join(e.dir, s.ID+".json"), append(data, '\n')); err != nil {
		return err
	}
	e.presence.sync(s)
	return nil
}
func addEvent(s *Session, kind, seat, detail string) *Event {
	if len(detail) > 600 {
		detail = string([]rune(detail)[:min(150, len([]rune(detail)))])
	}
	s.Events = append(s.Events, Event{ID: len(s.Events) + 1, Type: kind, Seat: seat, Detail: detail, At: now(), Round: len(s.Rounds)})
	return &s.Events[len(s.Events)-1]
}
func clone(s *Session) *Session {
	data, _ := json.Marshal(s)
	var result Session
	json.Unmarshal(data, &result)
	return &result
}

func (e *Engine) recover(s *Session) error {
	if s.Report.active() {
		return e.recoverReport(s)
	}
	if s.AgendaDraftStatus == "drafting" {
		lease, err := e.lease(s.ID)
		if err != nil {
			return err
		}
		if lease != nil {
			defer release(lease)
			failAgendaDraft(s, "上次起草已中断，可重新请首席生成。")
			return e.save(s)
		}
	}
	pending := false
	for _, op := range s.Operations {
		if op.Status == "pending" {
			pending = true
		}
	}
	if s.Status != "running" && !pending {
		return nil
	}
	lease, err := e.lease(s.ID)
	if err != nil {
		return err
	}
	if lease == nil {
		return nil
	}
	defer release(lease)
	if s.Status == "running" && len(s.Rounds) > 0 {
		if s.Continuous.active() && s.Continuous.SettledRound == len(s.Rounds) {
			s.Status = terminal(&s.Rounds[len(s.Rounds)-1])
		} else {
			recordRoundEnd(s, s.CancelRequested, "Process exited; work was not replayed. Start a new round explicitly.")
		}
	} else if s.Status == "running" {
		s.Status = "ready"
	}
	if s.Continuous.active() {
		pauseContinuous(s, "应用退出，持续推进已暂停。已保存的工作不会重放。")
	}

	for i := range s.Operations {
		if s.Operations[i].Status == "pending" {
			s.Operations[i].Status = "unknown"
			addEvent(s, "write_outcome_unknown", s.Operations[i].Seat, "Inspect the current file before deciding whether to retry: "+s.Operations[i].Path).OperationID = s.Operations[i].ID
		}
	}
	addEvent(s, "recovered", "", "Interrupted work was not replayed.")
	return e.save(s)
}
func terminal(r *Round) string {
	for _, t := range r.Turns {
		if t.Status != "done" {
			return "partial"
		}
	}
	return "ready"
}

func (e *Engine) Create(topic, project string, seats []string) (*Session, error) {
	return e.CreateWithMaterials(topic, project, seats, nil)
}

func (e *Engine) CreateWithMaterials(topic, project string, seats []string, materialIDs []string) (*Session, error) {
	return e.CreateScopedWithMaterials(topic, ProjectScope{Directory: project}, seats, materialIDs)
}

func (e *Engine) CreateScopedWithMaterials(topic string, scope ProjectScope, seats []string, materialIDs []string) (*Session, error) {
	if len(seats) == 0 {
		seats = []string{"codex", "cursor"}
	}
	seen := map[string]bool{}
	for _, seat := range seats {
		if (seat != "codex" && seat != "cursor") || seen[seat] {
			return nil, errors.New("seats must be distinct codex/cursor entries")
		}
		seen[seat] = true
	}
	return e.create(topic, scope, seats, nil, "work", nil, nil, materialIDs)
}

// CreateConfigured gives every chair a stable identity, independently of its
// provider or model. Private helpers inherit their parent's selected model.
func (e *Engine) CreateConfigured(topic, project string, members []Member, preset string, agenda ...AgendaInput) (*Session, error) {
	return e.CreateWithContinuous(topic, project, members, preset, nil, agenda...)
}

func (e *Engine) CreateWithContinuous(topic, project string, members []Member, preset string, continuous *ContinuousConfig, agenda ...AgendaInput) (*Session, error) {
	return e.CreateConfiguredWithMaterials(topic, project, members, preset, continuous, nil, agenda...)
}

func (e *Engine) CreateConfiguredWithMaterials(topic, project string, members []Member, preset string, continuous *ContinuousConfig, materialIDs []string, agenda ...AgendaInput) (*Session, error) {
	return e.CreateScopedConfiguredWithMaterials(topic, ProjectScope{Directory: project}, members, preset, continuous, materialIDs, agenda...)
}

func (e *Engine) CreateScopedConfiguredWithMaterials(topic string, scope ProjectScope, members []Member, preset string, continuous *ContinuousConfig, materialIDs []string, agenda ...AgendaInput) (*Session, error) {
	if len(members) == 0 {
		return nil, errors.New("请选择至少一位参会成员")
	}
	configured := append([]Member(nil), members...)
	seats := make([]string, len(configured))
	for i := range configured {
		m := &configured[i]
		if strings.TrimSpace(m.Model) == "" {
			return nil, errors.New("请选择有效的 Magpie 模型")
		}
		m.ID = fmt.Sprintf("member-%d", i+1)
		m.Version, m.ModelEpoch, m.PreviousModel, m.SwitchedAfterRound = 0, 0, "", 0
		if m.Effort == "" {
			m.Effort = "auto"
		}
		seats[i] = m.ID
	}
	return e.create(topic, scope, seats, configured, preset, agenda, continuous, materialIDs)
}
func (e *Engine) create(topic string, scope ProjectScope, seats []string, members []Member, preset string, agenda []AgendaInput, continuous *ContinuousConfig, materialIDs []string) (*Session, error) {
	if err := ValidateTopic(topic); err != nil {
		return nil, err
	}
	if scope.Global && (scope.ID != "" || scope.Directory != "") {
		return nil, errors.New("全局圆桌不能关联项目目录")
	}
	s := &Session{Board: MeetingBoard{State: boardEmpty}, ID: newID(), Topic: topic, ProjectID: scope.ID, Members: members, Seats: append([]string{}, seats...), Status: "ready", CreatedAt: now(), Rounds: []Round{}, Events: []Event{}, UserChanges: []UserChange{}, Operations: []Operation{}, Materials: []Material{}}
	if !scope.Global {
		validated, err := workspace.Validate(scope.Directory)
		if err != nil {
			return nil, err
		}
		s.Project = validated
	}
	if continuous != nil {
		cfg, err := continuousConfig(*continuous, topic)
		if err != nil {
			return nil, err
		}
		s.Continuous = &ContinuousState{Config: cfg, Status: "configured"}
	}
	if err := InitAgenda(s, preset, agenda); err != nil {
		return nil, err
	}
	addEvent(s, "created", "", "Created without sending a model request.")
	err := e.locked(func() error {
		if _, err := e.bindMaterials(s, materialIDs); err != nil {
			return err
		}
		if !scope.Global {
			return e.WithProjectDirectory(s, func(string) error { return e.save(s) })
		}
		return e.save(s)
	})
	return clone(s), err
}
func (e *Engine) Get(id string) (*Session, error) {
	var result *Session
	err := e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(s); err != nil {
			return err
		}
		// load decoded a fresh session for this reader.
		result = s
		return nil
	})
	return result, err
}
func (e *Engine) List() ([]Summary, error) {
	result, _, err := e.ListWithRecovery()
	return result, err
}

// ListWithRecovery returns healthy summaries and the locations of unusable files.
func (e *Engine) ListWithRecovery() ([]Summary, []sessionstore.Unreadable, error) {
	result := []Summary{}
	unreadable := []sessionstore.Unreadable{}
	err := e.visitSessions(func(s *Session, issue *sessionstore.Unreadable) {
		if issue != nil {
			unreadable = append(unreadable, *issue)
			return
		}
		result = append(result, Summary{ID: s.ID, Topic: s.Topic, Title: s.Title, ProjectID: s.ProjectID, Project: s.Project, Preset: s.Preset, Members: s.Members, SeatOverrides: s.SeatOverrides, Seats: append([]string{}, s.Seats...), Status: s.Status, CreatedAt: s.CreatedAt, UpdatedAt: s.UpdatedAt, RoundCount: len(s.Rounds)})
	})
	if err != nil {
		return nil, nil, err
	}
	sort.Slice(result, func(i, j int) bool { return result[i].CreatedAt > result[j].CreatedAt })
	return result, unreadable, nil
}

func (e *Engine) visitSessions(visit func(*Session, *sessionstore.Unreadable)) error {
	return e.locked(func() error {
		ids, err := sessionstore.IDs(e.dir)
		if err != nil {
			return err
		}
		for _, id := range ids {
			s, err := e.load(id)
			if err != nil {
				var issue *sessionstore.Unreadable
				if !errors.As(err, &issue) {
					return err
				}
				if visit != nil {
					visit(nil, issue)
				}
				continue
			}
			if err = e.recover(s); err != nil {
				return err
			}
			if visit != nil {
				visit(s, nil)
			}
		}
		return nil
	})
}
func (e *Engine) snapshotSettings(session *Session) (Settings, error) {
	// Copy maps so configuration updates cannot mutate an active round.
	encoded, err := json.Marshal(e.settings())
	if err != nil {
		return Settings{}, err
	}
	var s Settings
	if err = json.Unmarshal(encoded, &s); err != nil {
		return s, err
	}
	if len(session.Members) > 0 {
		s.Models = map[string]string{}
		s.ChildModels = map[string]string{}
		s.Efforts = map[string]string{}
		s.CLIPaths = nil
		s.CodexTransport = "magpie"
	}
	s.ModelEpochs, s.CatalogModelIDs = nil, nil
	for _, seat := range session.Seats {
		m := session.memberForSeat(seat)
		if m == nil {
			continue
		}
		if s.Models == nil {
			s.Models = map[string]string{}
		}
		if s.ChildModels == nil {
			s.ChildModels = map[string]string{}
		}
		if s.Efforts == nil {
			s.Efforts = map[string]string{}
		}
		s.Models[seat], s.ChildModels[seat], s.Efforts[seat] = m.Model, m.Model, m.Effort
		// The gateway only needs the exact-ID marker on legacy seat names.
		if seat == "codex" || seat == "cursor" {
			if s.CatalogModelIDs == nil {
				s.CatalogModelIDs = map[string]bool{}
			}
			s.CatalogModelIDs[seat] = true
		}
		if m.ModelEpoch > 0 {
			if s.ModelEpochs == nil {
				s.ModelEpochs = map[string]int{}
			}
			s.ModelEpochs[seat] = m.ModelEpoch
		}
	}
	return s, nil
}
func (e *Engine) validatedSettings(session *Session, seats []string) (Settings, error) {
	s, err := e.snapshotSettings(session)
	if err != nil {
		return s, err
	}
	if s.Timeout <= 0 || s.MaxSteps <= 0 || s.MaxChildren < 0 {
		return s, errors.New("invalid timeout, step limit or child limit")
	}
	if s.ChildModels == nil {
		s.ChildModels = map[string]string{}
	}
	for _, seat := range seats {
		if strings.TrimSpace(s.Models[seat]) == "" {
			return s, fmt.Errorf("missing model for %s", seat)
		}
		if s.ChildModels[seat] == "" {
			s.ChildModels[seat] = s.Models[seat]
		}
	}
	return s, nil
}

// Seat IDs remain unambiguous even when several seats share a model or label.
func (s *Session) resolveTarget(target string) (string, error) {
	for _, id := range s.Seats {
		if target == id {
			return id, nil
		}
	}
	match := ""
	for _, seat := range s.Seats {
		m := s.memberForSeat(seat)
		if m == nil {
			continue
		}
		if strings.EqualFold(target, m.Label) || target == m.Model {
			if match != "" {
				return "", errors.New("该称呼对应多个席位，请选择具体席位")
			}
			match = m.ID
		}
	}
	if match == "" {
		return "", errors.New("请选择本场会议的成员")
	}
	return match, nil
}

func (e *Engine) Start(id, note, target string, expectedRound int) (*Session, error) {
	return e.StartWithDiscussion(id, note, target, expectedRound, "work", "work")
}

func (e *Engine) StartWithDiscussion(id, note, target string, expectedRound int, preset, phase string, agendaVersion ...*int) (*Session, error) {
	options := RoundOptions{Preset: preset, Phase: phase}
	if len(agendaVersion) > 0 {
		options.AgendaVersion = agendaVersion[0]
	}
	return e.StartRound(id, note, target, expectedRound, options)
}

type RoundOptions struct {
	Continuous    *ContinuousConfig
	Preset, Phase string
	AgendaVersion *int
	MaterialIDs   []string
	// Nil preserves the preset and global editing policy for legacy clients.
	AllowEdits *bool
}

// StartRound snapshots the selected plan and effective permissions.
func (e *Engine) StartRound(id, note, target string, expectedRound int, options RoundOptions) (*Session, error) {
	if utf8.RuneCountInString(note) > maxInputCharacters {
		return nil, fmt.Errorf("本轮消息最多 %d 个字符", maxInputCharacters)
	}
	preset, phase := options.Preset, options.Phase
	namedSeat := target != ""
	var snapshot *Session
	var projectRules ProjectRuleSnapshot
	var lease *os.File
	var ctx context.Context
	var cancel context.CancelFunc
	err := e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(s); err != nil {
			return err
		}
		if err = s.requireOpen(); err != nil {
			return err
		}
		if s.AgendaDraftStatus == "drafting" {
			return fmt.Errorf("%w: 首席正在起草议程", ErrConflict)
		}
		if len(s.Rounds) != expectedRound {
			return fmt.Errorf("%w: session advanced; refresh", ErrConflict)
		}
		if s.Status == "running" {
			return fmt.Errorf("%w: a round is running", ErrConflict)
		}
		if options.AgendaVersion != nil && *options.AgendaVersion != s.AgendaVersion {
			return fmt.Errorf("%w: 议程已变化，请刷新后发起本轮", ErrConflict)
		}
		previousMaterials := len(s.Materials)
		materialIDs, err := e.bindMaterials(s, options.MaterialIDs)
		if err != nil {
			return err
		}
		for i := previousMaterials; i < len(s.Materials); i++ {
			s.Materials[i].AddedRound = expectedRound + 1
		}
		if preset == "" {
			preset = s.Preset
			if item := s.findAgenda(s.ActiveAgendaID); item != nil {
				if item.Kind == "implementation" {
					preset = "work"
				} else if item.Preset != "" {
					preset = item.Preset
				} else if preset == "" || preset == "work" {
					preset = "review"
				}
				if phase == "" && item.Preset == preset {
					phase = item.Phase
				}
			}
		}
		plan, err := deliberation.Resolve(preset, phase)
		if err != nil {
			return err
		}
		selected := append([]string{}, s.Seats...)
		if plan.Synthesis() && target == "" && len(selected) > 0 {
			target = selected[0]
		}
		if target != "" {
			target, err = s.resolveTarget(target)
			if err != nil {
				return err
			}
			selected = []string{target}
		}
		settings, err := e.validatedSettings(s, selected)
		if err != nil {
			return err
		}
		settings.AllowEdits = settings.AllowEdits && !s.isGlobal() && !plan.ReadOnly() && (options.AllowEdits == nil || *options.AllowEdits)
		projectRules, err = e.loadRoundRules(s)
		if err != nil {
			return err
		}
		pluginGuidance, err := e.snapshotPluginGuidance(roundGuidance)
		if err != nil {
			return err
		}
		if err = s.armContinuous(options.Continuous, plan.Preset, note); err != nil {
			return err
		}
		if s.Continuous.active() && namedSeat {
			s.Continuous.Target = target
		}
		lease, err = e.lease(id)
		if err != nil {
			return err
		}
		if lease == nil {
			return fmt.Errorf("%w: scheduler already active", ErrConflict)
		}
		appendRound(s, plan, note, target, selected, settings, projectRules, pluginGuidance, materialIDs, false)
		ctx, cancel = context.WithCancel(context.Background())
		e.cancelMu.Lock()
		defer e.cancelMu.Unlock()
		if e.shuttingDown {
			cancel()
			release(lease)
			lease = nil
			return fmt.Errorf("%w: engine is shutting down", ErrConflict)
		}
		if err = e.save(s); err != nil {
			cancel()
			release(lease)
			lease = nil
			return err
		}
		e.cancels[id] = cancel
		e.activeRounds[id] = len(s.Rounds)
		e.workers.Add(1)
		snapshot = clone(s)
		return nil
	})
	if err != nil {
		return nil, err
	}
	go e.run(ctx, id, lease, cancel, projectRules.Guidance)
	return snapshot, nil
}
func (e *Engine) loadRoundRules(s *Session) (ProjectRuleSnapshot, error) {
	if s.isGlobal() {
		return ProjectRuleSnapshot{}, nil
	}
	if err := e.WithProjectDirectory(s, func(string) error { return nil }); err != nil {
		return ProjectRuleSnapshot{}, err
	}
	if e.projectRuleSnapshot == nil {
		return ProjectRuleSnapshot{}, nil
	}
	rules, err := e.projectRuleSnapshot(s.Project)
	if err != nil {
		return rules, fmt.Errorf("无法读取本轮项目规则：%w", err)
	}
	return rules, nil
}

func appendRound(s *Session, plan deliberation.Plan, note, target string, seats []string, settings Settings, rules ProjectRuleSnapshot, plugins []PluginGuidance, materialIDs []string, automatic bool) {
	turns := make([]Turn, 0, len(seats))
	for _, seat := range seats {
		t := Turn{Seat: seat, Model: settings.Models[seat], Effort: settings.Efforts[seat], Status: "pending", Children: []Child{}, Changes: []workspace.Change{}, Reads: map[string]workspace.File{}}
		if m := s.memberForSeat(seat); m != nil {
			t.ModelLabel, t.ModelSource = m.Label, m.Source
		}
		turns = append(turns, t)
	}
	var versions *[]ProjectRuleVersion
	if rules.Versions != nil {
		refs := append([]ProjectRuleVersion{}, rules.Versions...)
		versions = &refs
	}
	s.Rounds = append(s.Rounds, Round{Number: len(s.Rounds) + 1, Auto: automatic, AgendaItemID: s.ActiveAgendaID, Preset: plan.Preset, Phase: plan.Phase, Note: note, Target: target, CreatedAt: now(), Turns: turns, Settings: settings, ProjectRules: versions, PluginGuidance: plugins, MaterialIDs: materialIDs})
	s.Status, s.CancelRequested = "running", false
	if len(s.Agenda) > 0 {
		s.AgendaVersion++
	}
	addEvent(s, "round_started", "", note)
}

func (e *Engine) Cancel(id string) (*Session, error) {
	var result *Session
	err := e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(s); err != nil {
			return err
		}
		if s.Status == "running" && !s.CancelRequested {
			s.CancelRequested = true
			addEvent(s, "cancel_requested", "", "Stopping the current model request.")
			if err = e.save(s); err != nil {
				return err
			}
			e.cancelMu.Lock()
			cancel := e.cancels[id]
			e.cancelMu.Unlock()
			if cancel != nil {
				cancel()
			}
		}
		result = clone(s)
		return nil
	})
	return result, err
}

// Shutdown rejects new starts, cancels this Engine's active CLI calls, and waits
// for their transports and state writes to finish. The transport must wait for
// its process group to exit before returning from a cancelled call. If ctx
// expires, cancellation remains active and cleanup continues in the background.
func (e *Engine) Shutdown(ctx context.Context) error {
	type activeRun struct {
		id     string
		round  int
		cancel context.CancelFunc
	}
	e.cancelMu.Lock()
	e.shuttingDown = true
	active := make([]activeRun, 0, len(e.cancels))
	for id, cancel := range e.cancels {
		active = append(active, activeRun{id: id, round: e.activeRounds[id], cancel: cancel})
	}
	titleCancels := make([]context.CancelFunc, 0, len(e.titleFlights))
	for _, stop := range e.reportCancels {
		titleCancels = append(titleCancels, stop)
	}
	for _, stop := range e.agendaDraftCancels {
		titleCancels = append(titleCancels, stop)
	}
	for _, flight := range e.titleFlights {
		titleCancels = append(titleCancels, flight.cancel)
	}
	e.cancelMu.Unlock()
	// Signal processes immediately, even if a durable file operation currently
	// holds the storage lock. Registration and WaitGroup.Add share cancelMu, so
	// no worker can be registered after shutdown begins.
	for _, run := range active {
		run.cancel()
	}
	for _, cancel := range titleCancels {
		cancel()
	}
	finished := make(chan error, 1)
	go func() {
		var result error
		for _, run := range active {
			err := e.locked(func() error {
				s, err := e.load(run.id)
				if err != nil {
					return err
				}
				// Another Engine may already have begun a later explicit round.
				if s.Status != "running" || len(s.Rounds) != run.round || s.CancelRequested {
					return nil
				}
				s.CancelRequested = true
				addEvent(s, "shutdown_requested", "", "Application shutdown is stopping active model requests.")
				return e.save(s)
			})
			result = errors.Join(result, err)
		}
		e.workers.Wait()
		e.cancelMu.Lock()
		result = errors.Join(result, e.backgroundErr)
		e.cancelMu.Unlock()
		finished <- result
	}()
	select {
	case err := <-finished:
		return err
	case <-ctx.Done():
		return ctx.Err()
	}
}
func (e *Engine) mutate(id string, index int, fn func(*Session, *Turn) error) error {
	return e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = fn(s, &s.Rounds[len(s.Rounds)-1].Turns[index]); err != nil {
			return err
		}
		return e.save(s)
	})
}
func (e *Engine) check(ctx context.Context, id string) error {
	_, err := e.checkedSnapshot(ctx, id, nil)
	return err
}

func (e *Engine) checkedSnapshot(ctx context.Context, id string, onRead func(*Session)) (*Session, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	var snapshot *Session
	err := e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		e.presence.sync(s)
		if s.CancelRequested {
			return context.Canceled
		}
		if onRead != nil {
			onRead(s)
		}
		snapshot = s
		return nil
	})
	return snapshot, err
}
func (e *Engine) run(ctx context.Context, id string, lease *os.File, cancel context.CancelFunc, importedGuidance string) {
	defer e.workers.Done()
	done := make(chan struct{})
	watcherDone := make(chan struct{})
	go func() {
		defer close(watcherDone)
		ticker := time.NewTicker(100 * time.Millisecond)
		defer ticker.Stop()
		var revision string
		for {
			select {
			case <-done:
				return
			case <-ctx.Done():
				return
			case <-ticker.C:
				if err := e.checkRevision(ctx, id, &revision); err != nil {
					cancel()
					return
				}
			}
		}
	}()
	var stopReason string
	defer func() {
		close(done)
		<-watcherDone
		// Publish terminal status and release the scheduling lease in one lock.
		released := false
		finishErr := e.locked(func() error {
			defer func() {
				e.cancelMu.Lock()
				delete(e.cancels, id)
				delete(e.activeRounds, id)
				e.cancelMu.Unlock()
				release(lease)
				released = true
			}()
			s, err := e.load(id)
			if err != nil {
				return err
			}
			if s.Status != "running" {
				return nil
			}
			c := s.Continuous
			if !c.active() || c.SettledRound != len(s.Rounds) {
				recordRoundEnd(s, s.CancelRequested || ctx.Err() != nil, "")
			} else {
				s.Status = terminal(&s.Rounds[len(s.Rounds)-1])
			}
			if c.active() {
				if s.CancelRequested || ctx.Err() != nil {
					stopReason = "持续推进已暂停。"
				}
				if stopReason == "" {
					stopReason = "本轮未完成，请检查记录。"
				}
				pauseContinuous(s, stopReason)
			}
			return e.save(s)
		})
		if !released {
			release(lease)
			e.cancelMu.Lock()
			delete(e.cancels, id)
			delete(e.activeRounds, id)
			e.cancelMu.Unlock()
		}
		if finishErr != nil {
			e.cancelMu.Lock()
			e.backgroundErr = errors.Join(e.backgroundErr, finishErr)
			e.cancelMu.Unlock()
		}
		cancel()
	}()
	for {
		s, err := e.Get(id)
		if err != nil {
			stopReason = err.Error()
			return
		}
		for i := range s.Rounds[len(s.Rounds)-1].Turns {
			if err = e.check(ctx, id); err != nil {
				return
			}
			if err = e.parent(ctx, id, i, importedGuidance); errors.Is(err, context.Canceled) {
				return
			}
		}
		if !s.Continuous.active() {
			return
		}
		guidance, again, err := e.afterContinuousRound(ctx, id)
		if err != nil {
			stopReason = err.Error()
			return
		}
		if !again {
			return
		}
		importedGuidance = guidance
	}
}

type action struct {
	BoardUpdates  json.RawMessage `json:"board_updates,omitempty"`
	Points        json.RawMessage `json:"points,omitempty"`
	Positions     json.RawMessage `json:"positions,omitempty"`
	AgendaUpdates json.RawMessage `json:"agenda_updates,omitempty"`
	Followups     json.RawMessage `json:"followups,omitempty"`
	Action        string          `json:"action"`
	Round         int             `json:"round,omitempty"`
	Seat          string          `json:"seat,omitempty"`
	Path          string          `json:"path,omitempty"`
	Text          *string         `json:"text,omitempty"`
	Task          string          `json:"task,omitempty"`
	Name          json.RawMessage `json:"name,omitempty"`
	Nickname      json.RawMessage `json:"nickname,omitempty"`
	DisplayName   json.RawMessage `json:"display_name,omitempty"`
}

func (a action) reportedChildName() string {
	for _, value := range []json.RawMessage{a.Name, a.Nickname, a.DisplayName} {
		var name string
		if json.Unmarshal(value, &name) == nil && strings.TrimSpace(name) != "" {
			return name
		}
	}
	return ""
}

func decodeAction(raw string) (action, error) {
	value := strings.TrimSpace(raw)
	if a, found, err := wholeAction(value, 0); found || err != nil {
		return a, err
	}
	// Only outermost JSON blocks are candidates. Never search recursively in
	// an example object, an array, or a quoted prose string for a write action.
	var selected action
	found := false
	for _, block := range outerJSONBlocks(value) {
		a, candidate, err := wholeAction(block, 0)
		if err != nil {
			return action{}, err
		}
		if !candidate {
			continue
		}
		if found && marshal(a) != marshal(selected) {
			return action{}, errors.New("回复包含多个不同动作，存在歧义；未执行任何动作。请只返回一个动作 JSON。")
		}
		selected, found = a, true
	}
	if !found {
		return action{}, errors.New("回复中没有唯一有效的动作 JSON；未执行任何动作。请只返回一个动作对象。")
	}
	return selected, nil
}

// wholeAction accepts a whole action, JSON-string quoting of a whole action,
// and the existing single-key result/output transport envelopes. Arbitrary
// text/content/example fields are deliberately not recursively interpreted.
func wholeAction(value string, depth int) (action, bool, error) {
	if depth >= 5 {
		return action{}, false, errors.New("动作 JSON 包装层数过多；请直接返回一个动作对象。")
	}
	var quoted string
	if json.Unmarshal([]byte(value), &quoted) == nil {
		return wholeAction(strings.TrimSpace(quoted), depth+1)
	}
	var object map[string]json.RawMessage
	if json.Unmarshal([]byte(value), &object) != nil || object == nil {
		return action{}, false, nil
	}
	if duplicateObjectFields(value) {
		return action{}, true, errors.New("动作 JSON 含重复字段，存在歧义；未执行任何动作。")
	}
	if _, hasAction := object["action"]; !hasAction {
		if len(object) == 1 {
			for _, key := range []string{"result", "output"} {
				if encoded, ok := object[key]; ok && json.Unmarshal(encoded, &quoted) == nil {
					return wholeAction(strings.TrimSpace(quoted), depth+1)
				}
			}
		}
		return action{}, false, nil
	}
	var a action
	if json.Unmarshal([]byte(value), &a) != nil {
		return action{}, true, errors.New("动作字段类型无效；action、path、task、text、seat 须为字符串，round 须为整数。")
	}
	switch a.Action {
	case "read":
		if strings.TrimSpace(a.Path) == "" {
			return action{}, true, errors.New("read 动作缺少有效 path。")
		}
	case "read_statement":
		if a.Round < 1 || strings.TrimSpace(a.Seat) == "" {
			return action{}, true, errors.New("read_statement 动作需要正整数 round 和有效 seat。")
		}
	case "write":
		if strings.TrimSpace(a.Path) == "" || a.Text == nil {
			return action{}, true, errors.New("write 动作必须同时提供 path 和完整 text；未执行写入。")
		}
	case "delegate":
		if strings.TrimSpace(a.Task) == "" {
			return action{}, true, errors.New("delegate 动作缺少有效 task。")
		}
	case "say":
		if a.Text == nil || strings.TrimSpace(*a.Text) == "" {
			return action{}, true, errors.New("say 动作缺少非空 text。")
		}
	default:
		return action{}, true, errors.New("不支持的动作：" + a.Action + "；请使用当前席位的动作协议。")
	}
	return a, true, nil
}

func duplicateObjectFields(value string) bool {
	decoder := json.NewDecoder(strings.NewReader(value))
	if _, err := decoder.Token(); err != nil {
		return false
	}
	seen := map[string]bool{}
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return false
		}
		key, ok := token.(string)
		if !ok {
			return false
		}
		if seen[key] {
			return true
		}
		seen[key] = true
		var ignored json.RawMessage
		if decoder.Decode(&ignored) != nil {
			return false
		}
	}
	return false
}

func outerJSONBlocks(value string) []string {
	blocks := []string{}
	stack := []byte{}
	start := -1
	quoted, escaped := false, false
	for index := 0; index < len(value); index++ {
		c := value[index]
		if quoted {
			if escaped {
				escaped = false
				continue
			}
			if c == '\\' {
				escaped = true
			} else if c == '"' {
				quoted = false
			}
			continue
		}
		if c == '"' {
			quoted = true
			continue
		}
		if c == '{' || c == '[' {
			if len(stack) == 0 {
				start = index
			}
			stack = append(stack, c)
			continue
		}
		if (c == '}' || c == ']') && len(stack) > 0 {
			opener := stack[len(stack)-1]
			if (opener == '{' && c != '}') || (opener == '[' && c != ']') {
				stack, start = nil, -1
				continue
			}
			stack = stack[:len(stack)-1]
			if len(stack) == 0 {
				if value[start] == '{' {
					blocks = append(blocks, value[start:index+1])
				}
				start = -1
			}
		}
	}
	return blocks
}

func protocolCorrection(child, allowEdits bool) string {
	allowed := "read、read_statement、delegate 或 say"
	if child {
		allowed = "read、read_statement 或 say"
	} else if allowEdits {
		allowed = "read、read_statement、delegate、write 或 say"
	}
	return "上一回复不符合动作协议，尚未执行其中任何动作。请只返回一个 " + allowed + " JSON 对象，不要添加解释或代码围栏。保留操作历史；已成功的读取、委派和写入不要重复执行。"
}

func (e *Engine) protocolFailure(id string, index, step int, childID, raw string, cause error) error {
	return e.mutate(id, index, func(s *Session, t *Turn) error {
		event := addEvent(s, "protocol_error", t.Seat, cause.Error())
		event.ChildID, event.Step, event.RawExcerpt = childID, step+1, shorten(raw, 400)
		return nil
	})
}

func shorten(text string, limit int) string {
	runes := []rune(text)
	if len(runes) > limit {
		return string(runes[:limit]) + "…"
	}
	return text
}
func relative(path string) (string, error) {
	if path == "" || filepath.IsAbs(path) || strings.Contains(path, "\\") {
		return "", errors.New("path must be a relative project file")
	}
	for _, part := range strings.Split(path, "/") {
		if part == ".." {
			return "", errors.New("path must stay within the project")
		}
	}
	path = filepath.ToSlash(filepath.Clean(path))
	if path == "." {
		return "", errors.New("path must identify a file")
	}
	return path, nil
}
func readFile(project, path string) (workspace.File, error) {
	f, err := workspace.Read(project, path)
	if errors.Is(err, os.ErrNotExist) {
		return workspace.File{Path: path, Text: "", Version: "missing"}, nil
	}
	return f, err
}
func protocol(child, allowEdits bool) string {
	base := `You are a model participating in a shared-project roundtable. Speak only for yourself; never simulate another seat or invent success. Native shell commands, file tools and edits are forbidden. All project operations must use this JSON protocol; the application executes them and verifies versions. Return exactly ONE JSON object, without commentary or Markdown. Actions: {"action":"read","path":"relative/file"}; {"action":"read_statement","round":1,"seat":"codex"}; {"action":"say","text":"your final statement"}. Use the user's language. Cite original public statements as [R1 · seat/model]. When a visible statement has text_omitted, read_statement retrieves its original text if needed to evaluate or quote it. A text_excerpt is only a prefix. For project evidence, read supplies the exact current file when text_omitted or diff_omitted is set. text_elsewhere refers to the same file version included elsewhere in the prompt. already_read feedback refers to content already in the turn's input. `
	base += materialPromptInstructions + "\n" + boardContextInstructions + "\n"
	base += "Use each public statement's recorded model for attribution. A seat is a stable discussion role and different models may have occupied it. A previous model's words and positions belong to that model.\n"
	if child {
		return base + `You are a PRIVATE read-only child. Only read, read_statement and say are allowed. Never write or delegate. Your answer goes only to your own parent, not the public discussion. If your CLI has already provided your own agent name, relay it exactly as an optional "name" field of your action. Omit the field if no name was provided. Never make up a name.`
	}
	base += `You are the current parent/chair for your own seat. You may also use {"action":"delegate","task":"bounded task for your own read-only child"}. Use selected files; do not repeatedly read unchanged content. When enough evidence is available, return say. Only your final say becomes a public statement. Assess private child results yourself. Address the peer's actual latest changes and explain which position you maintain or revise. Respect steps_remaining and max_children. `
	if !allowEdits {
		return base + `Project files are read-only this round. Do not return a write action.`
	}
	return base + `You may use {"action":"write","path":"relative/file","text":"complete new file text"}. Read every path before writing it, including a missing new file. After each write or conflict, explicitly read again before any later write. Only claim edits confirmed by successful feedback.`
}
func marshal(v any) string { b, _ := json.Marshal(v); return string(b) }

// SetProjectContext adapts a legacy reader that does not report rule versions.
func (e *Engine) SetProjectContext(f func(string) string) {
	if f == nil {
		e.SetProjectRuleSnapshot(nil)
		return
	}
	e.SetProjectRuleSnapshot(func(project string) (ProjectRuleSnapshot, error) {
		return ProjectRuleSnapshot{Guidance: f(project)}, nil
	})
}

// SetProjectRuleSnapshot installs the project rule reader during startup.
func (e *Engine) SetProjectRuleSnapshot(f func(string) (ProjectRuleSnapshot, error)) {
	e.projectRuleSnapshot = f
}

func (e *Engine) context(s *Session, index int, importedGuidance string) (map[string]any, error) {
	if s.isGlobal() {
		return e.projectContext(s, index, importedGuidance, "")
	}
	var data map[string]any
	err := e.WithProjectDirectory(s, func(project string) error {
		var err error
		data, err = e.projectContext(s, index, importedGuidance, project)
		return err
	})
	return data, err
}

func (e *Engine) projectContext(s *Session, index int, importedGuidance, project string) (map[string]any, error) {
	r := &s.Rounds[len(s.Rounds)-1]
	t := &r.Turns[index]
	model := r.catalogTurnModel(*t)
	member := s.memberForSeat(t.Seat)
	handoffAfter := 0
	if member != nil {
		handoffAfter = member.SwitchedAfterRound
	}
	plan, err := deliberation.Resolve(r.Preset, r.Phase)
	if err != nil {
		return nil, err
	}
	catalog := []string{}
	if project != "" {
		catalog, err = workspace.Catalog(project)
		if err != nil {
			return nil, err
		}
	}
	covered := 0
	if s.Continuous.active() && s.Continuous.Checkpoint != nil {
		covered = s.Continuous.Checkpoint.ThroughRound
	}
	var hostConstraints []map[string]any
	hostBudget := statementTextBudget / 4
	prior := []publicStatement{}
	priorRounds := []map[string]any{}
	for _, previous := range s.Rounds[:len(s.Rounds)-1] {
		if previous.Number <= covered {
			// Keep the host's own instructions authoritative even after summaries
			// replace older model-generated discussion.
			if !previous.Auto && previous.Note != "" {
				ref := map[string]any{"round": previous.Number, "seat": "host"}
				if fitsPromptText(previous.Note, &hostBudget) {
					ref["note"] = previous.Note
				} else {
					ref["text_omitted"] = true
				}
				hostConstraints = append(hostConstraints, ref)
			}
			continue
		}
		previousPlan, planErr := deliberation.Resolve(previous.Preset, previous.Phase)
		if planErr != nil {
			return nil, planErr
		}
		entry := map[string]any{"round": previous.Number, "preset": previousPlan.Preset, "phase": previousPlan.Phase, "target": previous.Target, "agenda_item_id": previous.AgendaItemID}
		if previous.Auto {
			entry["continuation_note"] = previous.Note
		} else {
			entry["host_note"] = previous.Note
		}
		priorRounds = append(priorRounds, entry)
	}
	participation := []map[string]any{}
	changes := map[string]map[string]any{}
	for ri := range s.Rounds {
		// A discussion stage sees only preceding rounds. In particular, neither
		// successful statements nor partial text/changes from this round leak to
		// a later seat simply because the execution remains sequential.
		if plan.Independent() && ri == len(s.Rounds)-1 {
			continue
		}
		seenSeats := map[string]bool{}
		for ti := range s.Rounds[ri].Turns {
			old := &s.Rounds[ri].Turns[ti]
			seenSeats[old.Seat] = true
			if ri == len(s.Rounds)-1 && ti == index {
				continue
			}
			completed := old.Status == "done" && strings.TrimSpace(old.Text) != ""
			recordedModel := s.Rounds[ri].RecordedTurnModel(*old)
			if s.Rounds[ri].Number > covered {
				participation = append(participation, map[string]any{"round": s.Rounds[ri].Number, "seat": old.Seat, "model": recordedModel, "status": old.Status, "has_completed_statement": completed})
			}
			if completed {
				prior = append(prior, publicStatement{Round: s.Rounds[ri].Number, Seat: old.Seat, Model: recordedModel, Text: old.Text, Points: old.Points, Positions: old.Positions})
			}
			if (old.Seat != t.Seat || s.Rounds[ri].catalogTurnModel(*old) != model || s.Rounds[ri].Number <= handoffAfter) && s.Rounds[ri].Number > covered {
				for _, c := range old.Changes {
					changes[c.Path] = map[string]any{"round": s.Rounds[ri].Number, "seat": old.Seat, "model": recordedModel, "change": c}
				}
			}
		}
		for _, seat := range s.Seats {
			if !seenSeats[seat] && s.Rounds[ri].Number > covered {
				participation = append(participation, map[string]any{"round": s.Rounds[ri].Number, "seat": seat, "model": s.Rounds[ri].Settings.Models[seat], "status": "absent", "has_completed_statement": false})
			}
		}
	}
	paths := []string{}
	for p := range changes {
		paths = append(paths, p)
	}
	sort.Strings(paths)
	evidence := newProjectEvidence()
	userFiles := map[string]promptFile{}
	for i := len(s.UserChanges) - 1; i >= 0; i-- {
		path := s.UserChanges[i].Change.Path
		if _, found := userFiles[path]; !found {
			if f, err := evidence.read(project, path); err == nil {
				userFiles[path] = f
			}
		}
	}
	var userChanges []promptUserChange
	if s.UserChanges != nil {
		userChanges = make([]promptUserChange, len(s.UserChanges))
		for i := len(s.UserChanges) - 1; i >= 0; i-- {
			change := s.UserChanges[i]
			userChanges[i] = promptUserChange{At: change.At, Change: evidence.change(change.Change)}
		}
	}
	peer := []map[string]any{}
	for _, p := range paths {
		entry := changes[p]
		entry["change"] = evidence.change(entry["change"].(workspace.Change))
		f, err := evidence.read(project, p)
		if err != nil {
			entry["current_content_error"] = err.Error()
		} else {
			entry["current_content"] = f
		}
		peer = append(peer, entry)
	}
	uncertain := []map[string]any{}
	for _, op := range s.Operations {
		if plan.Independent() && op.Round >= r.Number && op.Seat != t.Seat && op.Seat != "user" {
			continue
		}
		if op.Status == "unknown" {
			entry := map[string]any{"operation": op}
			f, err := evidence.read(project, op.Path)
			if err != nil {
				entry["read_error"] = err.Error()
			} else {
				entry["actual_content"] = f
			}
			uncertain = append(uncertain, entry)
		}
	}
	privateMemory := []map[string]any{}
private:
	for ri := len(s.Rounds) - 1; ri >= 0 && s.Rounds[ri].Number > handoffAfter && len(privateMemory) < 6; ri-- {
		for ti := len(s.Rounds[ri].Turns) - 1; ti >= 0 && len(privateMemory) < 6; ti-- {
			old := &s.Rounds[ri].Turns[ti]
			if old.Seat != t.Seat {
				continue
			}
			if previous := s.Rounds[ri].catalogTurnModel(*old); previous == "" || previous != model {
				break private
			}
			for ci := len(old.Children) - 1; ci >= 0 && len(privateMemory) < 6; ci-- {
				child := old.Children[ci]
				if child.Status != "done" || child.Text == "" {
					continue
				}
				privateMemory = append(privateMemory, map[string]any{"round": s.Rounds[ri].Number, "task": shorten(child.Task, 120), "model": child.Model, "conclusion": shorten(child.Text, 400)})
			}
		}
	}
	members := make([]Member, 0, len(s.Seats))
	for _, seat := range s.Seats {
		members = append(members, s.effectiveMember(seat, r.Settings))
	}
	data := map[string]any{"active_agenda": s.findAgenda(r.AgendaItemID), "open_agenda": openAgenda(s), "imported_project_reference": importedGuidance, "topic": s.Topic, "project": s.Project, "seat": t.Seat, "model": t.Model, "members": members, "round": r.Number, "preset": plan.Preset, "phase": plan.Phase, "latest_instruction": r.Note, "prior_rounds": priorRounds, "catalog": catalog, "prior_statements": prior, "public_participation": participation, "peer_changes": peer, "user_changes": userChanges, "user_changed_content": userFiles, "uncertain_edits": uncertain, "own_private_child_memory": privateMemory, "allow_edits": r.Settings.AllowEdits && !plan.ReadOnly(), "max_children": r.Settings.MaxChildren}
	if member != nil && member.ModelEpoch > 0 {
		data["model_handoff"] = map[string]any{"after_round": handoffAfter, "previous_model": member.PreviousModel}
	}
	if len(r.PluginGuidance) > 0 {
		data["plugin_guidance"] = r.PluginGuidance
	}
	if len(s.Materials) > 0 {
		data["materials"] = materialPromptContext(s.materialReferences(r.MaterialIDs))
	}
	if s.Continuous.active() {
		data["continuous_goal"] = s.Continuous.Config.Goal
		data["acceptance_criteria"] = s.Continuous.Config.Criteria
		data["continuous_next"] = s.Continuous.Next
		if r.Auto {
			data["instruction_origin"] = "continuation_reviewer"
		}
		if covered > 0 {
			data["rolling_summary"] = recordedCheckpointModels(s.Continuous.Checkpoint, prior)
			if points := continuousPoints(prior, covered); points != nil {
				data["archived_points"] = points
			}
			data["earlier_host_instructions"] = hostConstraints
		}
	}
	return data, nil
}
func (e *Engine) invoke(ctx context.Context, seat, model, prompt string, settings Settings) (string, error) {
	stepCtx, cancel := context.WithTimeout(ctx, time.Duration(settings.Timeout)*time.Second)
	defer cancel()
	stepCtx = context.WithValue(stepCtx, codexRouteKey{}, codexRoute{mode: settings.CodexTransport, port: settings.MagpiePort})
	stepCtx = context.WithValue(stepCtx, effortKey{}, settings.Efforts[seat])
	if settings.CatalogModelIDs[seat] {
		stepCtx = context.WithValue(stepCtx, exactCatalogKey{}, true)
	}
	if epoch := settings.ModelEpochs[seat]; epoch > 0 {
		if key, ok := stepCtx.Value(sessionKey{}).(string); ok && key != "" {
			stepCtx = context.WithValue(stepCtx, sessionKey{}, fmt.Sprintf("%s-model-%d", key, epoch))
		}
	}
	output, err := e.call(stepCtx, seat, model, prompt, settings.CLIPaths[seat])
	if stepCtx.Err() != nil {
		return "", stepCtx.Err()
	}
	return output, err
}

func (e *Engine) parent(ctx context.Context, id string, index int, importedGuidance string) (resultErr error) {
	var snapshot *Session
	err := e.mutate(id, index, func(s *Session, t *Turn) error {
		t.Status, t.StartedAt = "running", now()
		addEvent(s, "seat_started", t.Seat, t.Model)
		snapshot = clone(s)
		return nil
	})
	if err != nil {
		return err
	}
	r := snapshot.Rounds[len(snapshot.Rounds)-1]
	turn := r.Turns[index]
	settings := r.Settings
	defer func() {
		if resultErr != nil {
			e.mutate(id, index, func(s *Session, t *Turn) error {
				t.Status, t.Error, t.FinishedAt = "error", resultErr.Error(), now()
				addEvent(s, "seat_error", t.Seat, resultErr.Error())
				return nil
			})
		}
	}()
	plan, err := deliberation.Resolve(r.Preset, r.Phase)
	if err != nil {
		return err
	}
	if plan.ReadOnly() {
		settings.AllowEdits = false
	}
	contextData, err := e.context(snapshot, index, importedGuidance)
	if err != nil {
		return err
	}
	requestSession := id + "-" + turn.Seat
	if epoch := pluginGuidanceEpoch(snapshot.Rounds); epoch > 0 {
		requestSession += fmt.Sprintf("-guidance-%d", epoch)
	}
	if c := snapshot.Continuous; c.active() {
		// A fresh gateway session at each checkpoint prevents a provider from
		// carrying the discarded conversation back into the model request.
		through := 0
		if c.Checkpoint != nil {
			through = c.Checkpoint.ThroughRound
		}
		requestSession = fmt.Sprintf("%s-continuous-%d-%d", requestSession, c.StartRound, through)
	}
	ctx = context.WithValue(ctx, sessionKey{}, requestSession)
	instructions := protocol(false, settings.AllowEdits) + "\n" + positionInstructions + "\n" + plan.Instructions() + "\n" + agendaInstructions + "\n" + agendaUpdateInstructions + "\n" + boardInstructions + "\n" + publicBoardContextInstructions
	if contextData["model_handoff"] != nil {
		instructions += "\nMODEL_HANDOFF: You are taking over the same seat from a previous model. Continue the topic using the public record and its stable point IDs. Evaluate earlier statements independently, including this seat's prior statements, and identify their actual model when attributing them."
	}
	if plan.Synthesis() {
		instructions += "\n" + synthesisFollowupInstructions
	}
	if len(r.PluginGuidance) > 0 {
		instructions += "\n" + roundPluginRules
	}
	ctx = deliberation.WithInstructions(ctx, instructions)
	visibleStatements := contextData["prior_statements"].([]publicStatement)
	recent := visibleStatements
	if snapshot.Continuous.active() {
		ctx = deliberation.WithInstructions(ctx, instructions+"\nCONTINUOUS_RUN: The host enabled continued rounds toward continuous_goal. Use this preset and current permissions. Make concrete progress toward the acceptance criteria. State what is still missing, what you checked, and what another seat can verify. The reviewer determines whether to advance; decisions needing a human remain open. rolling_summary replaces older public statements; use read_statement with the cited round and seat to consult original evidence and its point IDs. archived_points, when present, lists recent discussion points and the last explicit stance per seat as of the checkpoint. Use their stable IDs for positions, and consult newer statements for changes. Past human instructions listed in earlier_host_instructions with text_omitted can also be retrieved by round and seat host. Read relevant omitted host instructions before taking action.")
		if cp := snapshot.Continuous.Checkpoint; cp != nil {
			i := 0
			for i < len(recent) && recent[i].Round <= cp.ThroughRound {
				i++
			}
			recent = recent[i:]
		}
	}
	inlineStatements := compactStatements(recent)
	contextData["prior_statements"] = inlineStatements
	visiblePoints := priorPointIDs(visibleStatements)
	if snapshot.Continuous.active() && snapshot.Continuous.Checkpoint != nil {
		for _, old := range snapshot.Rounds {
			if old.Number > snapshot.Continuous.Checkpoint.ThroughRound {
				break
			}
			if !old.Auto && old.Note != "" {
				visibleStatements = append(visibleStatements, publicStatement{Round: old.Number, Seat: "host", Text: old.Note})
			}
		}
	}
	statements := newStatementReader(visibleStatements, inlineStatements)
	writeEvidence := newProjectEvidence()
	history := []map[string]any{}
	protocolFailures := 0
	blindRound := 0
	if plan.Independent() {
		blindRound = r.Number
	}
	for step := 0; step < settings.MaxSteps; step++ {
		callCtx := ctx
		if step == 0 && !r.Auto {
			callCtx = e.withVisualMaterials(ctx, snapshot.materialReferences(r.MaterialIDs))
		}
		var finishPreview func()
		requestSnapshot, err := e.checkedSnapshot(ctx, id, func(fresh *Session) {
			callCtx, finishPreview = e.presence.stream(callCtx, fresh, turn.Seat, r.Number)
		})
		if err != nil {
			return err
		}
		// Refresh the editable meeting display for each request while retaining
		// the round's original speaking order, permissions and evidence.
		includeBoardPrompt(contextData, requestSnapshot, blindRound)
		includeLiveAgenda(contextData, requestSnapshot, r.AgendaItemID)
		base := "CONTEXT:\n" + marshal(contextData)
		prompt := base + fmt.Sprintf("\nSTEPS REMAINING: %d\nACTION HISTORY:\n", settings.MaxSteps-step) + marshal(history)
		raw, err := e.invoke(callCtx, turn.Seat, turn.Model, prompt, settings)
		finishPreview()
		if err != nil {
			return err
		}
		if err = e.check(ctx, id); err != nil {
			return err
		}
		a, err := decodeAction(raw)
		var points []DiscussionPoint
		var positions []Position
		if err == nil && a.Action == "say" {
			points, positions, err = parsePositions(a, visiblePoints, r.Number, index)
		}
		if err != nil {
			if saveErr := e.protocolFailure(id, index, step, "", raw, err); saveErr != nil {
				return saveErr
			}
			protocolFailures++
			if protocolFailures > 2 {
				return fmt.Errorf("动作协议累计三次无效，已用完两次纠正机会：%w", err)
			}
			history = append(history, map[string]any{"ok": false, "protocol_error": err.Error(), "correction": protocolCorrection(false, settings.AllowEdits)})
			continue
		}
		if a.Action == "say" {
			if a.Text == nil || strings.TrimSpace(*a.Text) == "" {
				return errors.New("say 动作需要非空 text。")
			}
			return e.mutate(id, index, func(s *Session, t *Turn) error {
				if s.CancelRequested || ctx.Err() != nil {
					return context.Canceled
				}
				t.Status, t.Text, t.FinishedAt = "done", *a.Text, now()
				t.Points, t.Positions = points, positions
				t.ProposedAgendaUpdates = parseAgendaUpdates(requestSnapshot, a.AgendaUpdates)
				t.ProposedBoardUpdates = parseBoardUpdates(requestSnapshot, a.BoardUpdates, *a.Text)
				if plan.Synthesis() {
					s.Rounds[len(s.Rounds)-1].ProposedFollowups = eligibleFollowups(s, a.Followups)
				}
				addEvent(s, "seat_done", t.Seat, "Public statement recorded.")
				return nil
			})
		}
		var result any
		switch a.Action {
		case "read":
			var path string
			path, err = relative(a.Path)
			if err == nil {
				var f workspace.File
				f, err = e.readProjectFile(snapshot, path)
				if err == nil {
					result = f
					err = e.mutate(id, index, func(s *Session, t *Turn) error {
						if previous, found := t.Reads[path]; found && previous.Version == f.Version {
							result = alreadyReadFile(f)
						}
						t.Reads[path] = f
						addEvent(s, "read", t.Seat, path)
						return nil
					})
				}
			}
		case "read_statement":
			result, err = statements.read(a)
		case "write":
			var change *workspace.Change
			change, err = e.agentWrite(ctx, id, index, a)
			if err == nil {
				result = writeEvidence.change(*change)
			}
			a.Text = nil
		case "delegate":
			result, err = e.delegate(ctx, id, index, a.Task, contextData, visibleStatements, settings)
		default:
			err = errors.New("unknown action: " + a.Action)
		}
		if errors.Is(err, context.Canceled) {
			return err
		}
		feedback := map[string]any{"action": a, "ok": err == nil}
		if err != nil {
			feedback["error"] = err.Error()
			if saveErr := e.mutate(id, index, func(s *Session, t *Turn) error { addEvent(s, "action_error", t.Seat, err.Error()); return nil }); saveErr != nil {
				return saveErr
			}
		} else {
			feedback["result"] = result
		}
		history = append(history, feedback)
	}
	return errors.New("已达到步骤上限，尚未获得最终公开发言。")
}

func (e *Engine) agentWrite(ctx context.Context, id string, index int, a action) (*workspace.Change, error) {
	if a.Text == nil {
		return nil, errors.New("write requires complete text")
	}
	path, err := relative(a.Path)
	if err != nil {
		return nil, err
	}
	var change *workspace.Change
	err = e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if s.CancelRequested || ctx.Err() != nil {
			return context.Canceled
		}
		round := &s.Rounds[len(s.Rounds)-1]
		plan, planErr := deliberation.Resolve(round.Preset, round.Phase)
		if planErr != nil {
			return planErr
		}
		if !round.Settings.AllowEdits || plan.ReadOnly() {
			return errors.New("edits are disabled for this round")
		}
		t := &round.Turns[index]
		baseline, ok := t.Reads[path]
		if !ok {
			return errors.New("read this path before writing it")
		}
		op := Operation{ID: newID(), Seat: t.Seat, Round: len(s.Rounds), Path: path, ExpectedVersion: baseline.Version, Text: *a.Text, Status: "pending"}
		s.Operations = append(s.Operations, op)
		oi := len(s.Operations) - 1
		addEvent(s, "write_intent", t.Seat, path).OperationID = op.ID
		if err = e.save(s); err != nil {
			return err
		}
		var actual workspace.Change
		writeErr := e.WithProjectDirectory(s, func(project string) error {
			var err error
			actual, err = workspace.Write(project, path, *a.Text, baseline.Version)
			return err
		})
		delete(t.Reads, path)
		if writeErr != nil {
			s.Operations[oi].Status, s.Operations[oi].Error = "error", writeErr.Error()
			addEvent(s, "write_failed", t.Seat, writeErr.Error()).OperationID = op.ID
		} else {
			s.Operations[oi].Status, s.Operations[oi].Change = "applied", &actual
			t.Changes = append(t.Changes, actual)
			change = &actual
			addEvent(s, "write", t.Seat, path).OperationID = op.ID
		}
		if err = e.save(s); err != nil {
			return err
		}
		return writeErr
	})
	return change, err
}

func (e *Engine) delegate(ctx context.Context, id string, index int, task string, contextData map[string]any, visibleStatements []publicStatement, settings Settings) (map[string]any, error) {
	if strings.TrimSpace(task) == "" {
		return nil, errors.New("delegate requires a task")
	}
	childID := newID()
	var seat string
	var selected map[string]workspace.File
	err := e.mutate(id, index, func(s *Session, t *Turn) error {
		if s.CancelRequested || ctx.Err() != nil {
			return context.Canceled
		}
		if len(t.Children) >= settings.MaxChildren {
			return errors.New("this seat's child limit has been reached")
		}
		seat = t.Seat
		selected = map[string]workspace.File{}
		for p, f := range t.Reads {
			selected[p] = f
		}
		t.Children = append(t.Children, Child{ID: childID, Task: task, Model: settings.ChildModels[seat], Effort: settings.Efforts[seat], Status: "running", StartedAt: now()})
		addEvent(s, "child_started", seat, task).ChildID = childID
		return nil
	})
	if err != nil {
		return nil, err
	}
	text, err := e.child(ctx, id, index, childID, seat, task, contextData, selected, visibleStatements, settings)
	saveErr := e.mutate(id, index, func(s *Session, t *Turn) error {
		for i := range t.Children {
			c := &t.Children[i]
			if c.ID == childID {
				c.FinishedAt = now()
				if err != nil {
					c.Status, c.Error = "error", err.Error()
					addEvent(s, "child_error", seat, err.Error()).ChildID = childID
				} else {
					c.Status, c.Text = "done", text
					addEvent(s, "child_done", seat, "Private result returned to parent.").ChildID = childID
				}
				break
			}
		}
		return nil
	})
	if saveErr != nil {
		return nil, saveErr
	}
	if err != nil {
		return nil, err
	}
	return map[string]any{"child_id": childID, "text": text}, nil
}
func (e *Engine) child(ctx context.Context, id string, index int, childID, seat, task string, contextData map[string]any, selected map[string]workspace.File, visibleStatements []publicStatement, settings Settings) (string, error) {
	// Replace, rather than append to, the parent's stage program. A private
	// helper is never promoted into an extra public participant or chair.
	ctx = context.WithValue(ctx, sessionKey{}, id+"-"+seat+"-"+childID)
	ctx = deliberation.WithInstructions(ctx, protocol(true, false))
	childData := make(map[string]any, len(contextData))
	for key, value := range contextData {
		childData[key] = value
	}
	delete(childData, "plugin_guidance")
	childData["allow_edits"], childData["max_children"] = false, 0
	evidence := newProjectEvidence()
	paths := make([]string, 0, len(selected))
	for path := range selected {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	selectedFiles := make(map[string]promptFile, len(selected))
	seenFiles := make(map[string]string, len(selected))
	for _, path := range paths {
		f := evidence.file(selected[path])
		selectedFiles[path] = f
		if !f.TextOmitted {
			seenFiles[path] = f.Version
		}
	}
	statements := newStatementReader(visibleStatements, contextData["prior_statements"].([]publicStatement))
	base := "PRIVATE TASK:\n" + marshal(map[string]any{"task": task, "roundtable": childData, "selected_files": selectedFiles})
	history := []map[string]any{}
	protocolFailures := 0
	nameRecorded := false
	for step := 0; step < settings.MaxSteps; step++ {
		if err := e.check(ctx, id); err != nil {
			return "", err
		}
		prompt := base + fmt.Sprintf("\nSTEPS REMAINING: %d\nACTION HISTORY:\n", settings.MaxSteps-step) + marshal(history)
		raw, err := e.invoke(ctx, seat, settings.ChildModels[seat], prompt, settings)
		if err != nil {
			return "", err
		}
		if err = e.check(ctx, id); err != nil {
			return "", err
		}
		a, err := decodeAction(raw)
		if err == nil && a.Action != "read" && a.Action != "read_statement" && a.Action != "say" {
			err = errors.New("子任务仅允许 read、read_statement 和 say，禁止写入或继续委派。")
		}
		if err != nil {
			if saveErr := e.protocolFailure(id, index, step, childID, raw, err); saveErr != nil {
				return "", saveErr
			}
			protocolFailures++
			if protocolFailures > 2 {
				return "", fmt.Errorf("子任务动作协议累计三次无效，已用完两次纠正机会：%w", err)
			}
			history = append(history, map[string]any{"ok": false, "protocol_error": err.Error(), "correction": protocolCorrection(true, false)})
			continue
		}
		// A child may relay its own CLI's name. A parent request carries only the task.
		if name := a.reportedChildName(); !nameRecorded && name != "" {
			if err := e.mutate(id, index, func(_ *Session, t *Turn) error {
				for i := range t.Children {
					if t.Children[i].ID == childID {
						t.Children[i].Name = name
						break
					}
				}
				return nil
			}); err != nil {
				return "", err
			}
			nameRecorded = true
		}
		if a.Action == "say" {
			if a.Text == nil || strings.TrimSpace(*a.Text) == "" {
				return "", errors.New("子任务 say 动作需要非空 text。")
			}
			return *a.Text, nil
		}
		var result any
		eventType, detail := "child_read", ""
		if a.Action == "read_statement" {
			eventType, detail = "child_read_statement", fmt.Sprintf("R%d · %s", a.Round, a.Seat)
			result, err = statements.read(a)
		} else {
			detail, err = relative(a.Path)
			if err == nil {
				var f workspace.File
				f, err = readFile(contextData["project"].(string), detail)
				if err == nil {
					result = f
					if seenFiles[detail] == f.Version {
						result = alreadyReadFile(f)
					}
					seenFiles[detail] = f.Version
				}
			}
		}
		feedback := map[string]any{"action": a, "ok": err == nil}
		if err != nil {
			feedback["error"] = err.Error()
			eventType, detail = eventType+"_error", err.Error()
		} else {
			feedback["result"] = result
		}
		history = append(history, feedback)
		if err = e.mutate(id, index, func(s *Session, t *Turn) error { addEvent(s, eventType, seat, detail).ChildID = childID; return nil }); err != nil {
			return "", err
		}
	}
	return "", errors.New("子任务已达到步骤上限。")
}

func (e *Engine) UserWrite(id, path, text, version string) (workspace.Change, error) {
	var result workspace.Change
	path, err := relative(path)
	if err != nil {
		return result, err
	}
	err = e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(s); err != nil {
			return err
		}
		if err = s.requireOpen(); err != nil {
			return err
		}
		op := Operation{ID: newID(), Seat: "user", Round: len(s.Rounds), Path: path, ExpectedVersion: version, Text: text, Status: "pending"}
		s.Operations = append(s.Operations, op)
		oi := len(s.Operations) - 1
		addEvent(s, "user_write_intent", "user", path).OperationID = op.ID
		if err = e.save(s); err != nil {
			return err
		}
		err = e.WithProjectDirectory(s, func(project string) error {
			var err error
			result, err = workspace.Write(project, path, text, version)
			return err
		})
		if err != nil {
			s.Operations[oi].Status, s.Operations[oi].Error = "error", err.Error()
			addEvent(s, "user_write_failed", "user", err.Error()).OperationID = op.ID
		} else {
			s.Operations[oi].Status, s.Operations[oi].Change = "applied", &result
			s.UserChanges = append(s.UserChanges, UserChange{At: now(), Change: result})
			addEvent(s, "user_write", "user", path).OperationID = op.ID
		}
		if saveErr := e.save(s); saveErr != nil {
			return saveErr
		}
		return err
	})
	return result, err
}
func (e *Engine) Markdown(id string) (string, error) {
	s, err := e.Get(id)
	if err != nil {
		return "", err
	}
	return renderTranscript(s), nil
}
