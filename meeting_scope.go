package main

import (
	"fmt"
	"os"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
	"scistation.local/desktop/internal/workspace"
)

type meetingProjects interface {
	ProjectDirectory(id string) (string, error)
	WithProjectDirectory(id string, use func(string) error) error
	ProjectForDirectory(path string) (research.Project, bool)
	EnsureDirectoryProject(path string) (research.Project, error)
}

func (a *apiServer) withMeetingProject(id string, use func(string) error) error {
	projects, ok := a.research.(meetingProjects)
	if !ok {
		return fmt.Errorf("%w: 科研工作区不可用", os.ErrPermission)
	}
	return projects.WithProjectDirectory(id, use)
}

func (a *apiServer) meetingScope(id, path, scope string) (meeting.ProjectScope, error) {
	if scope == "global" && id == "" && path == "" {
		return meeting.ProjectScope{Global: true}, nil
	}
	if scope != "" {
		return meeting.ProjectScope{}, fmt.Errorf("请选择一个科研项目或全局圆桌")
	}
	projects, hasResearch := a.research.(meetingProjects)
	if id != "" {
		if !hasResearch {
			return meeting.ProjectScope{}, fmt.Errorf("%w: 科研工作区不可用", os.ErrPermission)
		}
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
	if !hasResearch {
		return meeting.ProjectScope{Directory: dir}, nil
	}
	project, found := projects.ProjectForDirectory(dir)
	if !found {
		if !a.approvedResearchPath(dir) {
			return meeting.ProjectScope{}, fmt.Errorf("%w: 请先选择并登记项目目录", os.ErrPermission)
		}
		project, err = projects.EnsureDirectoryProject(dir)
		if err != nil {
			return meeting.ProjectScope{}, err
		}
	}
	dir, err = projects.ProjectDirectory(project.ID)
	return meeting.ProjectScope{ID: project.ID, Directory: dir}, err
}
