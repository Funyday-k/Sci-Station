package meeting

import (
	"fmt"
	"os"

	"scistation.local/desktop/internal/workspace"
)

// ProjectScope binds a new session to a research project and the approved
// directory used for its file tools. Global sessions have no file tools.
type ProjectScope struct {
	ID, Directory          string
	Global                 bool
	ConversationGeneration uint64
}

// SetConversationGenerationCheck installs the managed project's reset barrier.
// Callers supply the generation the editor saw, including zero for older clients.
func (e *Engine) SetConversationGenerationCheck(check func(string, uint64) error) {
	e.checkGeneration = check
}

func (e *Engine) checkConversationGeneration(projectID string, generation uint64) error {
	if projectID != "" && e.checkGeneration != nil {
		return e.checkGeneration(projectID, generation)
	}
	return nil
}

var ErrConversationResetPending = fmt.Errorf("%w: 正在清除此项目的旧对话，请稍后重试", ErrConflict)

// SetConversationAccessCheck hides pending archives from ordinary readers.
// anyPending lets unchanged-session and cursor polls avoid decoding transcripts
// while all projects are available. Both callbacks run under the storage lock.
func (e *Engine) SetConversationAccessCheck(check func(string) error, anyPending ...func() bool) {
	e.conversationAccess = check
	if len(anyPending) > 0 {
		e.anyResetPending = anyPending[0]
	}
}

func (e *Engine) checkPollAccess(id string) error {
	if e.conversationAccess == nil || (e.anyResetPending != nil && !e.anyResetPending()) {
		return nil
	}
	_, err := e.load(id)
	return err
}

// PathOnly reports an older session whose archive has no stable project identity.
func (s *Session) PathOnly() bool {
	return s.ProjectID == "" && s.Project != ""
}

func (s *Session) isGlobal() bool {
	return s.ProjectID == "" && s.Project == ""
}

// SetAIAvailability binds new work to the supplying workspace's module
// settings. Standalone engines can run independently of the research host.
func (e *Engine) SetAIAvailability(enabled func(string) (bool, error)) {
	e.aiEnabled = enabled
}

var ErrAIDisabled = fmt.Errorf("%w: 当前范围的 AI 模块已停用", ErrConflict)

// CheckAI checks admission for new work in an already resolved scope.
func (e *Engine) CheckAI(scope ProjectScope) error {
	if e.aiEnabled == nil {
		return nil
	}
	if scope.ID == "" && !scope.Global {
		return fmt.Errorf("%w: 此圆桌未关联有效的科研项目", os.ErrPermission)
	}
	enabled, err := e.aiEnabled(scope.ID)
	if err != nil {
		return err
	}
	if !enabled {
		return ErrAIDisabled
	}
	return nil
}

// SetProjectAccess installs the project authorization service before serving
// requests. Its callback holds the grant while performing local file I/O.
func (e *Engine) SetProjectAccess(access func(string, func(string) error) error) {
	e.projectAccess = access
}

func (e *Engine) WithProjectDirectory(s *Session, use func(string) error) error {
	if s.isGlobal() {
		return fmt.Errorf("%w: 全局圆桌没有项目目录", os.ErrPermission)
	}
	if e.projectAccess == nil && s.ProjectID == "" {
		return use(s.Project)
	}
	if e.projectAccess == nil || s.ProjectID == "" {
		return fmt.Errorf("%w: 此圆桌没有有效的科研项目授权", os.ErrPermission)
	}
	return e.projectAccess(s.ProjectID, func(dir string) error {
		if dir != s.Project {
			return fmt.Errorf("%w: 项目目录已更改，请为当前目录创建新的圆桌", os.ErrPermission)
		}
		return use(dir)
	})
}

func (e *Engine) readProjectFile(s *Session, path string) (workspace.File, error) {
	var file workspace.File
	err := e.WithProjectDirectory(s, func(dir string) error {
		var err error
		file, err = readFile(dir, path)
		return err
	})
	return file, err
}

func (e *Engine) SetManagedRootHistory(root string, previous []string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.managedRoot = root
	e.previousRoots = append([]string(nil), previous...)
}

func (e *Engine) Busy() bool {
	e.cancelMu.Lock()
	defer e.cancelMu.Unlock()
	return len(e.cancels) > 0 || len(e.agendaDraftCancels) > 0 || len(e.reportCancels) > 0 || len(e.titleFlights) > 0
}
