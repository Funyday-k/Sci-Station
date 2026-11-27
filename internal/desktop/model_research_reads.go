package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

// The validator is shared by user-initiated and model-proposed reads. A grant
// or configuration that changes while the review is open invalidates the call.
func (a *apiServer) checkResearchConnection(lab *research.Service, project, expectedDir string, rev int, c research.LabConnector) (string, func() error, error) {
	current := func() (string, error) {
		dir, err := lab.ProjectDirectory(project)
		if err != nil || expectedDir != "" && dir != expectedDir {
			return "", errors.New("当前项目的目录授权已失效，请重新打开项目")
		}
		cfg, err := lab.LabSettings(project)
		if err != nil || cfg.Revision != rev {
			return "", research.ErrLabSettingsConflict
		}
		enabled, err := lab.ModuleEnabled(project, "ai-lab")
		if err != nil || !enabled {
			return "", errors.New("当前项目实验室不可用")
		}
		return a.labConnect.grant(project, c)
	}
	grant, err := current()
	return grant, func() error {
		active, err := current()
		if err != nil {
			return err
		}
		if active != grant {
			return errors.New("连接信任已改变，请重新确认本次操作")
		}
		return nil
	}, err
}

func (a *apiServer) ResearchConnections(scope meeting.ProjectScope) []meeting.ResearchConnection {
	lab := a.research
	if lab == nil || !a.desktop || a.minerCreds == nil || a.labConnect.key == nil || scope.ID == "" || scope.Directory == "" {
		return nil
	}
	cfg, err := lab.LabSettings(scope.ID)
	if err != nil {
		return nil
	}
	var rows []meeting.ResearchConnection
	for _, c := range cfg.Connections {
		if _, _, err := a.checkResearchConnection(lab, scope.ID, scope.Directory, cfg.Revision, c); err != nil {
			continue
		}
		row := meeting.ResearchConnection{ID: c.ID}
		for _, tool := range c.Tools {
			if labReadToolName(tool) {
				row.Tools = append(row.Tools, tool)
			}
		}
		rows = append(rows, row)
	}
	return rows
}

type connectorRetry struct {
	attempts int
	until    time.Time
	last     string
}
type researchRetryState struct {
	mu      sync.Mutex
	entries map[string]connectorRetry
	clock   func() time.Time
	http    *http.Client // Optional isolated protocol transport used by local tests.
}

func (s *researchRetryState) now() time.Time {
	if s.clock != nil {
		return s.clock()
	}
	return time.Now()
}
func (s *researchRetryState) canAttempt(key string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	item := s.entries[key]
	if !s.now().Before(item.until) {
		return nil
	}
	return fmt.Errorf("%w · %s · retry_count=%d · next_retry=%s", meeting.ErrResearchBackoff, item.last, item.attempts, item.until.UTC().Format(time.RFC3339Nano))
}
func (s *researchRetryState) failed(key string, err error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	if s.entries == nil {
		s.entries = map[string]connectorRetry{}
	}
	item := s.entries[key]
	if !now.Before(item.until) {
		item.attempts++
		delay := time.Duration(min(1<<min(item.attempts, 6), 60)) * time.Second
		item.until = now.Add(delay)
		item.last = err.Error()
	}
	// Overlapping requests keep the first local deadline. A longer wait from an
	// actual server response still applies to this connection.
	var failure labTransportFailure
	if errors.As(err, &failure) {
		if deadline := labRetryAfter(now, failure.retryAfter); deadline.After(item.until) {
			item.until = deadline
			item.last = err.Error()
		}
	}
	s.entries[key] = item
	return fmt.Errorf("%w · retry_count=%d · next_retry=%s", err, item.attempts, item.until.UTC().Format(time.RFC3339Nano))
}
func (s *researchRetryState) success(key string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	// A success that overlaps a failure must not clear its active cooldown.
	if !s.now().Before(s.entries[key].until) {
		delete(s.entries, key)
	}
}

func labRetryAfter(now time.Time, value string) time.Time {
	value = strings.TrimSpace(value)
	if seconds, err := strconv.ParseUint(value, 10, 64); err == nil && seconds <= uint64(math.MaxInt64/time.Second) {
		return now.Add(time.Duration(seconds) * time.Second)
	}
	deadline, _ := http.ParseTime(value)
	return deadline
}

// A discovery/transport failure can be retried after a delay. Credential
// failures and decisions about an unlisted or changed tool need human input.
type labAuthFailure struct{ cause error }

func (e labAuthFailure) Error() string { return e.cause.Error() }

type labTransportFailure struct {
	cause      error
	retryAfter string
}

func (e labTransportFailure) Error() string { return e.cause.Error() }
func canonicalReadArguments(raw json.RawMessage) (map[string]any, string, error) {
	if raw == nil {
		return nil, "", nil
	}
	if len(raw) > 8192 {
		return nil, "", errors.New("科研工具参数超过上限")
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	// Duplicate keys are ambiguous for both approval and the receiving service.
	if err := checkArgumentValue(decoder); err != nil {
		return nil, "", err
	}
	decoder = json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var value map[string]any
	if err := decoder.Decode(&value); err != nil || value == nil {
		return nil, "", errors.New("科研工具参数需要 JSON 对象")
	}
	clean, err := json.Marshal(value)
	return value, string(clean), err
}
func checkArgumentValue(decoder *json.Decoder) error {
	token, err := decoder.Token()
	if err != nil {
		return errors.New("科研工具参数无效")
	}
	delim, ok := token.(json.Delim)
	if !ok {
		return nil
	}
	if delim != '{' && delim != '[' {
		return errors.New("科研工具参数无效")
	}
	var keys map[string]bool
	if delim == '{' {
		keys = make(map[string]bool)
	}
	for decoder.More() {
		if keys != nil {
			key, err := decoder.Token()
			name, ok := key.(string)
			if err != nil || !ok || keys[name] {
				return errors.New("科研工具参数存在重复或无效字段")
			}
			keys[name] = true
		}
		if err := checkArgumentValue(decoder); err != nil {
			return err
		}
	}
	_, err = decoder.Token()
	return err
}
func (a *apiServer) PrepareResearchRead(scope meeting.ProjectScope, request meeting.ResearchRead) (meeting.ResearchProposal, error) {
	var plan meeting.ResearchProposal
	lab := a.research
	if lab == nil || !a.desktop || a.labConnect.key == nil || a.minerCreds == nil || scope.ID == "" || scope.Directory == "" {
		return plan, noConnector
	}
	config, err := lab.LabSettings(scope.ID)
	if err != nil {
		return plan, noConnector
	}
	i := connectorIndex(config, request.Connection)
	if i < 0 {
		return plan, noConnector
	}
	c := config.Connections[i]
	args, argsJSON, err := canonicalReadArguments(request.Arguments)
	if err != nil {
		return plan, err
	}
	in := labConnectorRequest{ProjectID: scope.ID, ID: c.ID, Revision: config.Revision, Action: request.Operation, Target: request.Resource, Definition: request.Definition, Arguments: args}
	if _, err := connectorActionSummary(in, c); err != nil {
		return plan, err
	}
	grant, check, err := a.checkResearchConnection(lab, scope.ID, scope.Directory, config.Revision, c)
	if err != nil {
		return plan, err
	}
	source := filepath.Base(c.Program)
	if c.Transport == "https" {
		u, _ := url.Parse(c.Endpoint)
		source = u.Host
	}
	plan.Audit = fmt.Sprintf("%s %s · %s %s · config=%s · request=%s", c.ID, in.Action, c.Transport, source, labJSONDigest(c), labJSONDigest(in))
	if in.Action == "tools/call" {
		plan.Audit = c.ID + " " + in.Target + " · " + plan.Audit
	}
	key := labJSONDigest([]string{scope.ID, c.ID, grant})
	state := &a.labConnect.modelAudit
	if err := state.canAttempt(key); err != nil {
		return plan, err
	}
	destination := c.Endpoint
	if c.Transport == "stdio" {
		argv, _ := json.Marshal(c.Arguments)
		destination = c.Program + " " + string(argv) + "\n程序 SHA-256 " + c.ProgramHash
		if c.ScriptHash != "" {
			destination += "\n脚本 SHA-256 " + c.ScriptHash
		}
	}
	label := ""
	if p, ok := lab.ProjectForDirectory(scope.Directory); ok && p.ID == scope.ID {
		label = p.Name
	}
	plan.Review = meeting.ReadReview{Target: c.ID + " · " + in.Action, ProjectLabel: label, Connection: c.ID, Operation: in.Action, Resource: in.Target, ArgumentsJSON: argsJSON, Definition: in.Definition, Destination: destination}
	plan.Execute = func(ctx context.Context) (any, error) {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if err := check(); err != nil {
			return nil, err
		}
		if err := state.canAttempt(key); err != nil {
			return nil, err
		}
		client := state.http
		if client == nil {
			client = research.PublicResourceClient()
		}
		run, cancel := context.WithTimeout(ctx, 18*time.Second)
		defer cancel()
		result, err := a.runLabConnector(run, client, in, c, func() error {
			if err := run.Err(); err != nil {
				return err
			}
			return check()
		})
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		if err != nil {
			var failure labTransportFailure
			if c.Transport == "https" && errors.As(err, &failure) {
				return nil, state.failed(key, err)
			}
			return nil, err
		}
		if err := check(); err != nil {
			return nil, err
		}
		state.success(key)
		// Raw service instructions are untrusted. Results enter only this seat's
		// bounded action feedback, not the public approval timeline.
		switch rows := result.(type) {
		case []labResource:
			return modelResearchDirectory(rows), nil
		case []labToolView:
			return modelResearchDirectory(rows), nil
		}
		return result, nil
	}
	return plan, nil
}

// Keep an unusual third-party schema catalogue within a model prompt even for
// older sessions without a configured tool budget. Entries remain valid JSON.
func modelResearchDirectory[T any](rows []T) any {
	size := 2
	for i, row := range rows {
		b, _ := json.Marshal(row)
		size += len(b) + 1
		if size > 60<<10 {
			return map[string]any{"items": rows[:i], "total": len(rows), "truncated": true}
		}
	}
	return rows
}
