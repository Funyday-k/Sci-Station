package research

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"os"
	"slices"

	"scistation.local/desktop/internal/workspace"
)

var errResetPending = fmt.Errorf("%w: 正在清理此项目的旧对话，请稍后重试", workspace.ErrConflict)
var errResetConfirmation = errors.New("切换目录将清除此项目的旧对话和草稿，请确认后继续")
var errConversationService = errors.New("项目会话服务暂不可用")

type directoryChange struct {
	Revision           int    `json:"revision"`
	Path               string `json:"path"`
	ResetConversations bool   `json:"resetConversations"`
}

// The host holds its CLI and meeting gates before calling begin. Never enter
// either service while holding the research mutex.
func (s *Service) SetConversationReset(reset func(string, func() error) error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.resetConversations = reset
}

// Ordinary archive reads remain available for archived projects. A pending
// rebind is the one state in which the partially cleaned archive is hidden.
func (s *Service) AnyConversationResetPending() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.pendingConversationResets > 0
}

func (s *Service) CheckConversationAccess(id string) error {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.projects[id].Project.ConversationResetPending {
		return errResetPending
	}
	return nil
}

func (s *Service) CheckConversationGeneration(id string, generation uint64) error {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.projects[id]
	if !ok || d.Archived {
		return os.ErrNotExist
	}
	if d.Project.ConversationResetPending {
		return errResetPending
	}
	if d.Project.ConversationGeneration != generation {
		return fmt.Errorf("%w: 项目目录已改变，请重新打开对话", workspace.ErrConflict)
	}
	return nil
}

func differentConversationFolder(d projectData, path string, target DirectoryGrant) bool {
	if d.Project.Path == "" {
		return false
	}
	last := d.Project.DirectoryGrant
	if last == nil {
		last = d.PreviousDirectoryIdentity
	}
	if last != nil {
		return *last != target
	}
	// Older revoked records only have their last path.
	return d.Project.Path != path
}

func (s *Service) changeDirectory(w http.ResponseWriter, r *http.Request) {
	var in directoryChange
	if !payload(w, r, &in) {
		return
	}
	if in.Revision < 1 {
		jsonFail(w, 428, "请携带已读取的 revision")
		return
	}
	s.directoryChanges.Lock()
	defer s.directoryChanges.Unlock()
	id := r.PathValue("project")
	project, err := s.changeProjectDirectory(id, in)
	switch {
	case err == nil:
		jsonReply(w, 200, project)
	case errors.Is(err, errResetConfirmation):
		jsonReply(w, 409, map[string]string{"error": err.Error(), "code": "confirmation_required"})
	case errors.Is(err, errResetPending):
		jsonReply(w, 503, map[string]string{"error": err.Error(), "code": "reset_pending"})
	case errors.Is(err, errConversationService):
		jsonFail(w, 503, err.Error())
	case errors.Is(err, os.ErrPermission):
		jsonFail(w, 403, "请重新选择授权文件夹")
	case errors.Is(err, os.ErrNotExist):
		jsonFail(w, 404, "未找到这条记录")
	case errors.Is(err, os.ErrInvalid):
		jsonFail(w, 400, err.Error())
	case errors.Is(err, workspace.ErrConflict), errors.Is(err, errProjectRecordChanged):
		jsonFail(w, 409, err.Error())
	default:
		jsonFail(w, 500, "无法保存项目目录或会话状态")
	}
}

// Inspect and validate in the research lock, then release it before the engine
// locks the archive. The commit rechecks revision, membership, picker identity
// and path after the potentially long preflight.
func (s *Service) changeProjectDirectory(id string, in directoryChange) (Project, error) {
	s.mu.Lock()
	d, ok := s.projects[id]
	if !ok || d.Archived {
		s.mu.Unlock()
		return Project{}, os.ErrNotExist
	}
	if d.Project.ConversationResetPending {
		s.mu.Unlock()
		if !in.ResetConversations || in.Path != d.Project.Path {
			return Project{}, errResetPending
		}
		return s.finishConversationReset(id, d.Project.ConversationGeneration, nil)
	}
	if d.Project.Revision != in.Revision {
		s.mu.Unlock()
		return Project{}, fmt.Errorf("%w: 内容已改变，请重新加载", workspace.ErrConflict)
	}
	if s.isManaged(d.Project) {
		s.mu.Unlock()
		return Project{}, fmt.Errorf("%w: 受管项目目录由工作区管理", os.ErrInvalid)
	}
	var target DirectoryGrant
	if in.Path != "" {
		var err error
		target, err = s.externalDirectory(in.Path)
		if err != nil {
			s.mu.Unlock()
			return Project{}, os.ErrPermission
		}
	}
	reset := in.Path != "" && differentConversationFolder(d, in.Path, target)
	if !reset {
		p, err := s.commitDirectoryChange(id, in, target, false)
		s.mu.Unlock()
		return p, err
	}
	s.mu.Unlock()
	if !in.ResetConversations {
		return Project{}, errResetConfirmation
	}
	if d.Project.ConversationGeneration >= math.MaxUint64 {
		return Project{}, workspace.ErrConflict
	}
	generation := d.Project.ConversationGeneration + 1
	return s.finishConversationReset(id, generation, func() error {
		s.mu.Lock()
		defer s.mu.Unlock()
		_, err := s.commitDirectoryChange(id, in, target, true)
		return err
	})
}

// Caller holds the research write lock.
func (s *Service) commitDirectoryChange(id string, in directoryChange, target DirectoryGrant, reset bool) (Project, error) {
	d, ok := s.projects[id]
	if !ok || d.Archived {
		return Project{}, os.ErrNotExist
	}
	if d.Project.Revision != in.Revision || d.Project.ConversationResetPending {
		return Project{}, fmt.Errorf("%w: 内容已改变，请重新加载", workspace.ErrConflict)
	}
	if in.Path == "" {
		if d.Project.DirectoryGrant != nil {
			d.PreviousDirectoryIdentity = d.Project.DirectoryGrant
		}
		d.Project.DirectoryGrant = nil
	} else {
		actual, err := s.externalDirectory(in.Path)
		if err != nil || actual != target {
			return Project{}, os.ErrPermission
		}
		for _, other := range s.projects {
			if other.Project.ID != id && !other.Archived && other.Project.Path == in.Path {
				return Project{}, fmt.Errorf("%w: 已有活动项目关联此文件夹", workspace.ErrConflict)
			}
		}
		if s.pathValidator == nil || !s.pathValidator(in.Path, actual) {
			return Project{}, os.ErrPermission
		}
		d.PreviousDirectoryIdentity = nil
		d.Project.Path = in.Path
		d.Project.DirectoryGrant = &actual
	}
	if reset {
		d.Project.ConversationGeneration++
		d.Project.ConversationResetPending = true
		d.Reviews = nil
		d.RoundtableRules = nil
	}
	d.Project.bump()
	if err := s.commit(d); err != nil {
		return Project{}, err
	}
	return d.Project, nil
}

// The durable marker keeps new conversations and drafts out until every old
// artifact has been removed. Retrying cleanup is safe even after a crash.
func (s *Service) finishConversationReset(id string, generation uint64, begin func() error) (Project, error) {
	s.mu.RLock()
	reset := s.resetConversations
	s.mu.RUnlock()
	if reset == nil {
		return Project{}, errConversationService
	}
	if begin == nil {
		begin = func() error {
			s.mu.RLock()
			defer s.mu.RUnlock()
			d, ok := s.projects[id]
			if !ok || !d.Project.ConversationResetPending || d.Project.ConversationGeneration != generation {
				return workspace.ErrConflict
			}
			return nil
		}
	}
	if err := reset(id, begin); err != nil {
		s.mu.RLock()
		pending := s.projects[id].Project.ConversationResetPending
		s.mu.RUnlock()
		if pending {
			return Project{}, fmt.Errorf("%w：%v", errResetPending, err)
		}
		return Project{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.projects[id]
	if !ok || !d.Project.ConversationResetPending || d.Project.ConversationGeneration != generation {
		return Project{}, workspace.ErrConflict
	}
	d.Project.ConversationResetPending = false
	if err := s.commit(d); err != nil {
		return Project{}, fmt.Errorf("%w：%v", errResetPending, err)
	}
	return d.Project, nil
}

// Recover only projects whose own grant transaction recorded pending cleanup.
func (s *Service) RecoverConversationResets() error {
	s.directoryChanges.Lock()
	defer s.directoryChanges.Unlock()
	s.mu.RLock()
	ids := []string{}
	for id, d := range s.projects {
		if d.Project.ConversationResetPending {
			ids = append(ids, id)
		}
	}
	s.mu.RUnlock()
	slices.Sort(ids)
	var failures []error
	for _, id := range ids {
		s.mu.RLock()
		generation := s.projects[id].Project.ConversationGeneration
		s.mu.RUnlock()
		if _, err := s.finishConversationReset(id, generation, nil); err != nil {
			failures = append(failures, fmt.Errorf("%s: %w", id, err))
		}
	}
	return errors.Join(failures...)
}
