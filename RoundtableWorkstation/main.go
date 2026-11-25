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

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/plugins"
	"scistation.local/desktop/internal/research"
)

func defaultData() string {
	// A Finder launch must not read Documents before its first window exists.
	// Only an explicitly selected project belongs in the editing path.
	conf, err := os.UserConfigDir()
	if err != nil {
		log.Fatal(err)
	}
	return filepath.Join(conf, "Sci-Station Desktop")
}

func isStudio(url string) bool {
	client := http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{Proxy: nil}}
	resp, e := client.Get(url + "/api/health")
	if e != nil {
		return false
	}
	defer resp.Body.Close()
	var health struct {
		Name    string
		Version int
	}
	return resp.StatusCode == 200 && json.NewDecoder(resp.Body).Decode(&health) == nil && health.Name == "sci-station" && health.Version == 2
}

func run() error {
	flags := flag.NewFlagSet("sci-station", flag.ContinueOnError)
	port := flags.Int("port", 18765, "local HTTP port")
	headless := flags.Bool("headless", false, "run only the local web interface and JSON API")
	data := flags.String("data-dir", defaultData(), "meeting and settings directory")
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
	addr := fmt.Sprintf("127.0.0.1:%d", *port)
	address := "http://" + addr
	listener, e := net.Listen("tcp4", addr)
	if e != nil {
		if !*headless && isStudio(address) {
			return runDesktop(address+"/research", nil, nil)
		}
		return fmt.Errorf("无法监听 %s: %w", addr, e)
	}
	defer listener.Close()
	if e = os.MkdirAll(*data, 0700); e != nil {
		return e
	}
	// A second port must never recover a first instance's running sessions.
	guard, e := os.OpenFile(filepath.Join(*data, ".studio-process.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return e
	}
	defer guard.Close()
	if e = syscall.Flock(int(guard.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); e != nil {
		return errors.New("此数据目录已有一个圆桌实例在运行")
	}
	pref, e := openSettings(*data)
	if e != nil {
		return e
	}
	gateway := studioGateway(pref)
	call := gatewayCall(gateway)
	engine, e := meeting.New(filepath.Join(*data, "studio"), call, func() meeting.Settings { return pref.get().Settings })
	if e != nil {
		return e
	}
	lab, e := research.New(filepath.Join(*data, "research"))
	if e != nil {
		return e
	}
	market, marketErr := plugins.NewStore(filepath.Join(*data, "plugins"))
	api := &apiServer{desktop: !*headless, prefs: pref, meetings: engine, research: lab, plugins: market, pluginErr: marketErr}
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
		Handler:           api.serve(*port),
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
	})
	defer shutdown()
	fmt.Fprintf(os.Stderr, "Sci-Station · %s · %s\n", address, *data)
	done := make(chan error, 1)
	go func() { done <- server.Serve(listener) }()
	if !*headless {
		return runDesktop(address+"/research", api, shutdown)
	}
	stop, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	select {
	case <-stop.Done():
		return nil
	case e := <-done:
		return e
	}
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
