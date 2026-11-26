package desktop

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/plugins"
	"scistation.local/desktop/internal/research"
	"scistation.local/desktop/internal/workspace"
)

func rootRegistry() (desktopRoots, error) {
	if dir := os.Getenv("SCI_STATION_WORKSPACE_REGISTRY"); filepath.IsAbs(dir) {
		return desktopRoots{dir: dir}, nil
	}
	conf, err := os.UserConfigDir()
	return desktopRoots{dir: filepath.Join(conf, "Sci-Station Workstation")}, err
}

// A window may borrow a headless server only for the explicitly selected root.
func attachedWorkspace(dir string, port int, binding rootBinding) *workspaceInstance {
	if port == 0 {
		return nil
	}
	address := fmt.Sprintf("http://127.0.0.1:%d", port)
	client := http.Client{Timeout: time.Second, Transport: &http.Transport{Proxy: nil}, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	res, err := client.Get(address + "/api/health")
	if err != nil {
		return nil
	}
	defer res.Body.Close()
	var info struct {
		Name, Workspace string
		Version         int
	}
	if res.StatusCode != 200 || json.NewDecoder(res.Body).Decode(&info) != nil || info.Name != "sci-station" || info.Version != 2 || info.Workspace != binding.ID {
		return nil
	}
	actual, err := folderIdentity(dir)
	if err != nil || !binding.matches(actual) {
		return nil
	}
	return &workspaceInstance{dir: dir, address: address, binding: binding, close: func() {}}
}

func run() error {
	flags := flag.NewFlagSet("sci-station", flag.ContinueOnError)
	port := flags.Int("port", 18765, "local HTTP port")
	headless := flags.Bool("headless", false, "run only the local web interface and JSON API")
	data := flags.String("data-dir", "", "meeting and settings directory")
	args := os.Args[1:]
	if len(args) > 0 && (args[0] == "serve" || args[0] == "app") {
		*headless = args[0] == "serve"
		args = args[1:]
	}
	// Older LaunchServices releases may append a process serial number.
	if len(args) == 1 && strings.HasPrefix(args[0], "-psn_") {
		args = nil
	}
	if e := flags.Parse(args); e != nil {
		return e
	}
	if *port < 1 || *port > 65535 {
		return errors.New("port must be between 1 and 65535")
	}
	var requested int
	flags.Visit(func(f *flag.Flag) {
		if f.Name == "port" {
			requested = *port
		}
	})
	if !*headless {
		return runDesktop(*data, requested)
	}
	roots, err := rootRegistry()
	if err != nil {
		return err
	}
	choice, err := roots.initial(*data)
	if err != nil {
		return err
	}
	if choice.dir == "" {
		return errors.New("请通过 --data-dir 指定一个新工作区，或先在桌面端选择工作区")
	}
	instance, err := startRegisteredWorkspace(roots, choice, requested, false)
	if err != nil {
		return err
	}
	defer instance.close()
	stop, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	select {
	case <-stop.Done():
		return nil
	case err := <-instance.done:
		return err
	}
}

type workspaceInstance struct {
	dir     string
	address string
	binding rootBinding
	api     *apiServer
	done    <-chan error
	close   func()
	freeze  func() bool
}

func startRegisteredWorkspace(roots desktopRoots, choice rootChoice, requested int, desktop bool, setup ...rootSetup) (*workspaceInstance, error) {
	dir, _, err := inspectRoot(choice.dir, choice.create)
	if err != nil {
		return nil, err
	}
	expected := choice.expected
	if !choice.create {
		actual, err := folderIdentity(dir)
		if err != nil || (expected.Marker != 0 && !expected.matches(actual)) {
			return nil, errWorkspaceReplaced
		}
		if expected.Marker == 0 {
			actual.ID = expected.ID
			expected = actual
		}
	}
	// An explicit desktop port can refer to an already running headless
	// process. Check that it serves the same authorized folder identity.
	if desktop && requested != 0 && !choice.create {
		expected, err = roots.authorize(dir, expected, false)
		if err != nil {
			return nil, err
		}
		if _, err := roots.reserve(expected, requested); err != nil {
			return nil, err
		}
		if instance := attachedWorkspace(dir, requested, expected); instance != nil {
			return instance, roots.refreshRecent(choice, instance)
		}
	}
	instance, err := startBoundWorkspace(dir, desktop, choice.create, expected, func(path string) (rootBinding, int, error) {
		binding, err := roots.authorize(path, expected, choice.create)
		if err != nil {
			return rootBinding{}, 0, err
		}
		port, err := roots.reserve(binding, requested)
		return binding, port, err
	}, setup...)
	if err != nil {
		return nil, err
	}
	if err := roots.refreshRecent(choice, instance); err != nil {
		instance.close()
		return nil, err
	}
	return instance, nil
}

// Unregistered workspaces are used only for isolated tests of the service.
func startWorkspace(dir string, port int, desktop bool, create bool, setup ...rootSetup) (*workspaceInstance, error) {
	return startBoundWorkspace(dir, desktop, create, rootBinding{}, func(path string) (rootBinding, int, error) {
		return rootBinding{ID: rootID(path)}, port, nil
	}, setup...)
}

func startBoundWorkspace(dir string, desktop, create bool, expected rootBinding, resolve func(string) (rootBinding, int, error), setup ...rootSetup) (*workspaceInstance, error) {
	dir, _, err := inspectRoot(dir, create)
	if err != nil {
		return nil, err
	}
	owned := false
	if expected.Marker != 0 {
		actual, err := folderIdentity(dir)
		if err != nil || !expected.matches(actual) {
			return nil, errWorkspaceReplaced
		}
	}
	flags := os.O_CREATE | os.O_RDWR | syscall.O_NOFOLLOW
	if create {
		flags |= os.O_EXCL
	}
	guard, err := workspace.ManagedOpenFile(filepath.Join(dir, ".studio-process.lock"), flags, 0600)
	if err != nil {
		return nil, err
	}
	if err = syscall.Flock(int(guard.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		guard.Close()
		return nil, fmt.Errorf("此工作区已在其他进程中打开：%w", err)
	}

	defer func() {
		if !owned {
			guard.Close()
		}
	}()
	if create {
		if len(setup) > 0 {
			if err := seedNewWorkspace(dir, setup[0]); err != nil {
				_ = workspace.ManagedRemove(filepath.Join(dir, ".studio-process.lock"))
				return nil, err
			}
		} else if err = markNewRoot(dir); err != nil {
			_ = workspace.ManagedRemove(filepath.Join(dir, ".studio-process.lock"))
			return nil, err
		}
	}
	binding, port, err := resolve(dir)
	if err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return nil, fmt.Errorf("工作区端口不可用：%w", err)
	}
	defer func() {
		if !owned {
			listener.Close()
		}
	}()
	pref, e := openSettings(dir)
	if e != nil {
		return nil, e
	}
	if desktop {
		setupProviderProfiles(pref, dir, binding.ID)
	}
	gateway := studioGateway(pref)
	call := gatewayCall(gateway)
	engine, e := meeting.New(filepath.Join(dir, "studio"), call, pref.meetingSettings)
	if e != nil {
		return nil, e
	}
	lab, e := research.New(filepath.Join(dir, "research"))
	if e != nil {
		return nil, e
	}
	market, marketErr := plugins.NewStore(filepath.Join(dir, "plugins"))
	api := &apiServer{desktop: desktop, workspaceDir: dir, boundRootID: binding.ID, prefs: pref, meetings: engine, research: lab, plugins: market, pluginErr: marketErr}
	if api.desktop {
		lab.SetNewTaskReminder(func(task research.Task) (string, error) { return api.sendReminder(task, true) })
		store, keys, err := credentials.WorkspaceStores(binding.ID)
		api.labConnect.key = keys
		if err != nil {
			log.Print("无法为此数据目录启用 MinerU 钥匙串")
		} else if store != nil {
			api.minerCreds = newMinerCredentials(store)
			engine.SetResearchReads(api)
		}
	}
	engine.SetManagedRootHistory(dir, binding.Paths)
	lab.SetPathValidator(api.approvedResearchPath)
	if marketErr == nil {
		engine.SetPluginGuidance(api.pluginGuidance)
	} else {
		// Unavailable extensions must not prevent access to the meeting archive.
		log.Printf("插件已暂停：%v", marketErr)
	}
	engine.SetProjectRuleSnapshot(api.projectRuleSnapshot)
	instance := api.serveOwnedWorkspace(listener, guard, binding, 8*time.Second)
	owned = true
	return instance, nil
}

// The instance owns the listener and the exclusive workspace lock from here.
func (api *apiServer) serveOwnedWorkspace(listener net.Listener, guard *os.File, binding rootBinding, grace time.Duration) *workspaceInstance {
	address := "http://" + listener.Addr().String()
	requestContext, cancelRequests := context.WithCancel(context.Background())
	var access sync.RWMutex
	frozen := false
	handler := api.serve(listener.Addr().(*net.TCPAddr).Port)
	server := &http.Server{
		BaseContext: func(net.Listener) context.Context { return requestContext },
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			access.RLock()
			defer access.RUnlock()
			if frozen || requestContext.Err() != nil {
				reject(w, 503, "Workspace is reopening")
				return
			}
			if binding.Marker != 0 {
				actual, err := folderIdentity(api.workspaceDir)
				if err != nil || !binding.matches(actual) {
					reject(w, 409, errWorkspaceReplaced.Error())
					return
				}
			}
			handler.ServeHTTP(w, r)
		}),
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}
	// AppKit bounds the caller's wait. A root switch leaves this process alive,
	// so keep its file lock until every admitted writer has actually returned.
	shutdown := sync.OnceFunc(func() {
		ctx, cancel := context.WithTimeout(context.Background(), grace)
		defer cancel()
		cancelRequests()
		api.forgetCLIEditWindow()
		var workers sync.WaitGroup
		workers.Go(func() { api.cliEdits.jobs.Close(context.Background()) })
		workers.Go(func() {
			if err := api.meetings.Shutdown(context.Background()); err != nil {
				log.Printf("结束圆桌任务: %v", err)
			}
		})
		released := make(chan struct{})
		go func() {
			if err := server.Shutdown(ctx); err != nil {
				_ = server.Close()
			}
			// Closing a socket does not wait for its handler. Drain admitted
			// readers; subsequent handlers observe the cancelled base context.
			access.Lock()
			access.Unlock()
			workers.Wait()
			guard.Close()
			close(released)
		}()
		select {
		case <-released:
		case <-ctx.Done():
			log.Print("工作区仍在结束后台任务")
		}
	})
	fmt.Fprintf(os.Stderr, "Sci-Station · %s · %s\n", address, api.workspaceDir)
	done := make(chan error, 1)
	go func() { done <- server.Serve(listener) }()
	return &workspaceInstance{dir: api.workspaceDir, address: address, binding: binding, api: api, done: done, close: shutdown, freeze: func() bool {
		if !access.TryLock() {
			return false
		}
		defer access.Unlock()
		if api.meetings.Busy() || api.cliEdits.jobs.Busy() {
			return false
		}
		frozen = true
		return true
	}}
}

// Main starts the desktop application or the selected command-line operation.
func Main() {
	if len(os.Args) > 1 && os.Args[1] == "plugin" {
		os.Exit(runPluginCLI(os.Args[2:], os.Stdout, os.Stderr))
	}
	if e := run(); e != nil {
		log.Print(e)
		os.Exit(1)
	}
}
