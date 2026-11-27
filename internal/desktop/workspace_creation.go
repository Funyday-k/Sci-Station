package desktop

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	"scistation.local/desktop/internal/research"
	"scistation.local/desktop/internal/workspace"
	"scistation.local/desktop/web"
)

const setupFile = ".sci-station-workspace.json"

type rootSetup struct {
	Name           string `json:"name"`
	Template       string `json:"template"`
	Sample         bool   `json:"sample"`
	Acknowledged   bool   `json:"acknowledged"`
	UseEmptyFolder bool   `json:"useEmptyFolder"`
}
type rootDescription struct {
	Folder   string `json:"folder,omitempty"`
	Version  int    `json:"version"`
	Name     string `json:"name"`
	Template string `json:"template"`
	Sample   bool   `json:"sample,omitempty"`
}

func validWorkspaceName(name string) bool {
	return utf8.ValidString(name) && utf8.RuneCountInString(name) <= 100 && strings.IndexFunc(name, unicode.IsControl) < 0 && !strings.ContainsAny(name, "/\\:") && name != "." && name != ".."
}
func (draft rootSetup) validate() error {
	name := strings.TrimSpace(draft.Name)
	available := slices.ContainsFunc(research.CreationTemplates(), func(template research.CreationTemplate) bool {
		return template.ID == draft.Template && template.Available
	})
	if !draft.Acknowledged || !available || !validWorkspaceName(name) || (!draft.UseEmptyFolder && (name == "" || strings.HasPrefix(name, "."))) {
		return errors.New("请确认工作区名称、模板和 AI 设置 / Check the name, template and AI setup acknowledgement")
	}
	return nil
}
func readRootDescription(dir string) (rootDescription, error) {
	var meta rootDescription
	data, err := workspace.ManagedReadFile(filepath.Join(dir, setupFile))
	if errors.Is(err, os.ErrNotExist) {
		return rootDescription{Version: 1, Template: "literature-review"}, nil
	}
	if err != nil {
		return meta, err
	}
	if err = json.Unmarshal(data, &meta); err != nil || meta.Version != 1 || !validWorkspaceName(meta.Name) {
		return meta, errors.New("无法读取工作区设置 / Unsupported workspace metadata")
	}
	return meta, nil
}
func rootDisplay(dir string) string {
	if dir == "" {
		return ""
	}
	if info, err := readRootDescription(dir); err == nil && info.Name != "" && (info.Folder == "" || info.Folder == filepath.Base(dir)) {
		return info.Name
	}
	return filepath.Base(dir)
}

// Resolve only the directory selected in the native panel. A new named root
// must be an exclusive child of that directory.
func prepareWorkspaceTarget(selected string, draft rootSetup) (string, error) {
	if err := draft.validate(); err != nil {
		return "", err
	}
	if draft.UseEmptyFolder {
		dir, _, err := inspectRoot(selected, true)
		return dir, err
	}
	parent, err := filepath.EvalSymlinks(selected)
	if err != nil {
		return "", err
	}
	parent, err = filepath.Abs(parent)
	if err != nil {
		return "", err
	}
	target := filepath.Join(parent, strings.TrimSpace(draft.Name))
	if err = workspace.CheckRootAncestors(target); err != nil {
		return "", err
	}
	if err = workspace.ManagedMkdir(target, 0700); err != nil {
		return "", err
	}
	return target, nil
}

func seedNewWorkspace(dir string, draft rootSetup) error {
	if err := draft.validate(); err != nil {
		return err
	}
	root, err := workspace.ManagedOpenDirectory(dir)
	if err != nil {
		return err
	}
	defer root.Close()
	stage := ".setup-" + rand.Text()
	if err := root.Mkdir(stage, 0700); err != nil {
		return err
	}
	defer root.RemoveAll(stage)
	path := filepath.Join(dir, stage)
	svc, err := research.New(filepath.Join(path, "research"))
	if err != nil {
		return err
	}
	name := strings.TrimSpace(draft.Name)
	if name == "" {
		name = filepath.Base(dir)
	}
	if err = svc.ConfigureNewWorkspace(draft.Template, name, draft.Sample, filepath.Join(dir, "research")); err != nil {
		return err
	}
	meta := rootDescription{Version: 1, Folder: filepath.Base(dir), Name: name, Template: draft.Template, Sample: draft.Sample}
	data, err := json.Marshal(meta)
	if err != nil {
		return err
	}
	if err = workspace.ManagedAtomicWrite(filepath.Join(path, setupFile), data); err != nil {
		return err
	}
	if err := markNewRoot(path); err != nil {
		return err
	}
	fd, err := root.Open(".")
	if err != nil {
		return err
	}
	defer fd.Close()
	published := []string{}
	for _, name := range []string{"research", setupFile, rootMarker} {
		if err := renameRootExclusive(int(fd.Fd()), filepath.Join(stage, name), name); err != nil {
			for i := len(published) - 1; i >= 0; i-- {
				old := published[i]
				err = errors.Join(err, root.Rename(old, filepath.Join(stage, old)))
			}
			return err
		}
		published = append(published, name)
	}
	return nil
}

// A welcome listener must not occupy the stable port of a closed workspace
// that the user could select while the welcome page is still open.
func listenForWorkspaceWelcome(roots desktopRoots) (net.Listener, error) {
	for range 32 {
		listener, err := net.Listen("tcp4", "127.0.0.1:0")
		if err != nil {
			return nil, err
		}
		port := listener.Addr().(*net.TCPAddr).Port
		_, err = os.Lstat(filepath.Join(roots.dir, fmt.Sprintf("port-%d", port)))
		if errors.Is(err, os.ErrNotExist) {
			return listener, nil
		}
		listener.Close()
		if err != nil {
			return nil, err
		}
	}
	return nil, errors.New("没有可用的欢迎窗口端口 / No available welcome port")
}

// A rootless welcome window gets an ephemeral listener with only chooser routes.
// No research repository or provider configuration is created to display it.
func startWorkspaceWelcome(roots desktopRoots, language, message string) (*workspaceInstance, error) {
	listener, err := listenForWorkspaceWelcome(roots)
	if err != nil {
		return nil, err
	}
	api := &apiServer{desktop: true}
	port := listener.Addr().(*net.TCPAddr).Port
	base := api.serve(port)
	page, err := template.ParseFS(web.Assets, "static/workspace-welcome.html")
	if err != nil {
		listener.Close()
		return nil, err
	}
	server := &http.Server{ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second, Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/welcome":
			if r.Host != listener.Addr().String() {
				http.NotFound(w, r)
				return
			}
			if r.Method != http.MethodGet {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'; base-uri 'none'")
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("Cache-Control", "no-store")
			w.Header().Set("X-Content-Type-Options", "nosniff")
			_ = page.Execute(w, struct{ Language, Message string }{language, message})
		case "/static/workspace-welcome.js", "/static/workspace-welcome.css", "/static/roundtable-mark.png", "/api/workspace", "/api/workspace/templates", "/api/workspace/open", "/api/workspace/setup", "/api/workspace/forget", "/api/workspace/default-storage", "/api/workspace/choose-storage":
			base.ServeHTTP(w, r)
		default:
			http.NotFound(w, r)
		}
	})}
	done := make(chan error, 1)
	go func() { done <- server.Serve(listener) }()
	stop := sync.OnceFunc(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if server.Shutdown(ctx) != nil {
			_ = server.Close()
		}
	})
	return &workspaceInstance{address: fmt.Sprintf("http://127.0.0.1:%d", port), api: api, done: done, close: stop}, nil
}
