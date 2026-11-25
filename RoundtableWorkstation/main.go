package main

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
)

func rootRegistry() (desktopRoots, error) {
	if dir := os.Getenv("SCI_STATION_WORKSPACE_REGISTRY"); filepath.IsAbs(dir) {
		return desktopRoots{dir: dir}, nil
	}
	conf, err := os.UserConfigDir()
	return desktopRoots{dir: filepath.Join(conf, "Sci-Station Workstation")}, err
}

// A window may borrow a headless server only for the explicitly selected root.
func attachedWorkspace(dir string, port int) *workspaceInstance {
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
	if res.StatusCode != 200 || json.NewDecoder(res.Body).Decode(&info) != nil || info.Name != "sci-station" || info.Version != 2 || info.Workspace != rootID(dir) {
		return nil
	}
	return &workspaceInstance{dir: dir, address: address, close: func() {}}
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
	dir, _, err := inspectRoot(choice.dir, choice.create)
	if err != nil {
		return err
	}
	bindPort, err := roots.reserve(dir, requested)
	if err != nil {
		return err
	}
	instance, err := startWorkspace(dir, bindPort, false, choice.create)
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
	api     *apiServer
	done    <-chan error
	close   func()
}

func startWorkspace(dir string, port int, desktop bool, create bool) (*workspaceInstance, error) {
	dir, _, err := inspectRoot(dir, create)
	if err != nil {
		return nil, err
	}
	owned := false
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return nil, fmt.Errorf("工作区端口不可用：%w", err)
	}
	defer func() {
		if !owned {
			listener.Close()
		}
	}()
	flags := os.O_CREATE | os.O_RDWR | syscall.O_NOFOLLOW
	if create {
		flags |= os.O_EXCL
	}
	guard, err := os.OpenFile(filepath.Join(dir, ".studio-process.lock"), flags, 0600)
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
	address := "http://" + listener.Addr().String()
	if create {
		if err = markNewRoot(dir); err != nil {
			_ = os.Remove(filepath.Join(dir, ".studio-process.lock"))
			return nil, err
		}
	}
	pref, e := openSettings(dir)
	if e != nil {
		return nil, e
	}
	if desktop {
		setupProviderProfiles(pref, dir)
	}
	gateway := studioGateway(pref)
	call := gatewayCall(gateway)
	engine, e := meeting.New(filepath.Join(dir, "studio"), call, func() meeting.Settings { return pref.get().Settings })
	if e != nil {
		return nil, e
	}
	lab, e := research.New(filepath.Join(dir, "research"))
	if e != nil {
		return nil, e
	}
	market, marketErr := plugins.NewStore(filepath.Join(dir, "plugins"))
	api := &apiServer{desktop: desktop, workspaceDir: dir, prefs: pref, meetings: engine, research: lab, plugins: market, pluginErr: marketErr}
	if api.desktop {
		lab.SetNewTaskReminder(func(task research.Task) (string, error) { return api.sendReminder(task, true) })
		store, err := credentials.Open(dir)
		if err != nil {
			log.Print("无法为此数据目录启用 MinerU 钥匙串")
		} else if store != nil {
			api.minerCreds = newMinerCredentials(store)
		}
	}
	lab.SetPathValidator(api.approvedResearchPath)
	if marketErr == nil {
		engine.SetPluginGuidance(api.pluginGuidance)
	} else {
		// Unavailable extensions must not prevent access to the meeting archive.
		log.Printf("插件已暂停：%v", marketErr)
	}
	engine.SetProjectRuleSnapshot(api.projectRuleSnapshot)
	requestContext, cancelRequests := context.WithCancel(context.Background())
	server := &http.Server{
		BaseContext:       func(net.Listener) context.Context { return requestContext },
		Handler:           api.serve(listener.Addr().(*net.TCPAddr).Port),
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}
	// AppKit can terminate the process before app.Run returns to Go. Both native
	// quit and command-line shutdown use this owner's single cleanup deadline.
	shutdown := sync.OnceFunc(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		defer cancel()
		cancelRequests()
		httpDone := make(chan error, 1)
		go func() { httpDone <- server.Shutdown(ctx) }()
		if err := engine.Shutdown(ctx); err != nil {
			log.Printf("结束圆桌任务: %v", err)
		}
		if err := <-httpDone; err != nil {
			_ = server.Close()
			log.Printf("结束本机请求: %v", err)
		}
		guard.Close()
	})
	fmt.Fprintf(os.Stderr, "Sci-Station · %s · %s\n", address, dir)
	done := make(chan error, 1)
	go func() { done <- server.Serve(listener) }()
	owned = true
	return &workspaceInstance{dir: dir, address: address, api: api, done: done, close: shutdown}, nil
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "plugin" {
		os.Exit(runPluginCLI(os.Args[2:], os.Stdout, os.Stderr))
	}
	if e := run(); e != nil {
		log.Print(e)
		os.Exit(1)
	}
}
