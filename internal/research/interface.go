package research

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"

	"scistation.local/desktop/internal/workspace"
)

const interfaceSettingsFile = "interface.json"

func validInterfaceLanguage(language string) bool {
	return language == "system" || language == "en" || language == "zh-Hans"
}

func (s *Service) readInterface() (string, map[string]json.RawMessage, error) {
	path := filepath.Join(s.dir, interfaceSettingsFile)
	fields := map[string]json.RawMessage{"version": json.RawMessage("1")}
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return "system", fields, nil
	}
	if err != nil {
		return "", nil, err
	}
	if !info.Mode().IsRegular() {
		return "", nil, errors.New("interface preferences are not a regular file")
	}
	body, err := workspace.ManagedReadFile(path)
	if err != nil {
		return "", nil, err
	}
	var version int
	var language string
	if json.Unmarshal(body, &fields) != nil || json.Unmarshal(fields["version"], &version) != nil || version != 1 ||
		json.Unmarshal(fields["language"], &language) != nil || !validInterfaceLanguage(language) {
		return "", nil, errors.New("invalid interface preferences")
	}
	return language, fields, nil
}

// InterfaceLanguage returns the choice owned by this research root.
func (s *Service) InterfaceLanguage() (string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	language, _, err := s.readInterface()
	return language, err
}

// OnWorkspaceMenuChanged registers the desktop host's notification.
// It runs after a successful write and outside the research service lock.
func (s *Service) OnWorkspaceMenuChanged(listener func()) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.onWorkspaceMenuChanged = listener
}

func (s *Service) registerInterface() {
	s.mux.HandleFunc("GET "+prefix+"/interface/layout", s.shellLayout)
	s.mux.HandleFunc("PATCH "+prefix+"/interface/layout", s.shellLayout)
	s.mux.HandleFunc("GET "+prefix+"/interface", s.getInterface)
	s.mux.HandleFunc("PATCH "+prefix+"/interface", s.changeInterface)
}

func (s *Service) getInterface(w http.ResponseWriter, _ *http.Request) {
	language, err := s.InterfaceLanguage()
	if err != nil {
		jsonFail(w, 500, "无法读取界面偏好")
		return
	}
	jsonReply(w, 200, map[string]string{"language": language})
}

func (s *Service) changeInterface(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Language string `json:"language"`
	}
	if !payload(w, r, &in) {
		return
	}
	if !validInterfaceLanguage(in.Language) {
		jsonFail(w, 400, "未知的界面语言")
		return
	}
	s.mu.Lock()
	var listener func()
	defer func() {
		s.mu.Unlock()
		if listener != nil {
			listener()
		}
	}()
	_, fields, err := s.readInterface()
	if err != nil {
		jsonFail(w, 500, "无法读取界面偏好")
		return
	}
	fields["language"], _ = json.Marshal(in.Language)
	body, err := json.MarshalIndent(fields, "", "  ")
	if err != nil || atomicWrite(filepath.Join(s.dir, interfaceSettingsFile), append(body, '\n')) != nil {
		jsonFail(w, 500, "无法保存界面偏好")
		return
	}
	listener = s.onWorkspaceMenuChanged
	jsonReply(w, 200, map[string]string{"language": in.Language})
}
