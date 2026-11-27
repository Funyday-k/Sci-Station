package desktop

import (
	"errors"
	"fmt"
	"os"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/workspace"
)

func (a *apiServer) meetingScope(id, path, scope string) (meeting.ProjectScope, error) {
	if scope == "global" && id == "" && path == "" {
		return meeting.ProjectScope{Global: true}, nil
	}
	if scope != "" {
		return meeting.ProjectScope{}, fmt.Errorf("请选择一个科研项目或全局圆桌")
	}
	projects := a.research
	if projects == nil {
		return meeting.ProjectScope{}, fmt.Errorf("%w: 科研工作区不可用", os.ErrPermission)
	}
	if id != "" {
		dir, err := projects.ProjectDirectory(id)
		if err != nil {
			return meeting.ProjectScope{}, err
		}
		if path != "" && path != dir {
			return meeting.ProjectScope{}, fmt.Errorf("%w: 项目和目录授权不一致", os.ErrPermission)
		}
		return meeting.ProjectScope{ID: id, Directory: dir}, nil
	}
	dir, err := workspace.Validate(path)
	if err != nil {
		return meeting.ProjectScope{}, err
	}
	project, found := projects.ProjectForDirectory(dir)
	if !found {
		return meeting.ProjectScope{}, fmt.Errorf("%w: 请先选择并登记项目目录", os.ErrPermission)
	}
	dir, err = projects.ProjectDirectory(project.ID)
	return meeting.ProjectScope{ID: project.ID, Directory: dir}, err
}

func (a *apiServer) resetProjectConversations(id string, begin func() error) error {
	return a.cliEdits.jobs.ResetProject(id, func() error {
		err := a.meetings.ResetProjectSessions(id, begin)
		if errors.Is(err, meeting.ErrConflict) {
			return fmt.Errorf("%w: %s", workspace.ErrConflict, err)
		}
		return err
	})
}
