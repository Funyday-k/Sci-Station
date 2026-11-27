package meeting

import (
	"fmt"
	"os"

	"scistation.local/desktop/internal/workspace"
)

// ProjectScope binds a new session to a research project and the approved
// directory used for its file tools. Global sessions have no file tools.
type ProjectScope struct {
	ID, Directory string
	Global        bool
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
