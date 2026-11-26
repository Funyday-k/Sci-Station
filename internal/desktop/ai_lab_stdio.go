package desktop

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"scistation.local/desktop/internal/research"
)

// The local registration is entered by the desktop user. The protocol never
// interprets a command line, expands environment variables or inherits secrets.
type labStdio struct {
	cmd  *exec.Cmd
	in   io.WriteCloser
	scan *bufio.Scanner
	out  io.ReadCloser
	stop func() bool
	dir  string
}

func labFileDigest(path string, executable bool) (string, error) {
	if !filepath.IsAbs(path) || filepath.Clean(path) != path || len(path) > 2048 {
		return "", errors.New("请选择本机文件的完整绝对路径")
	}
	f, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NONBLOCK, 0)
	if err != nil {
		return "", errors.New("无法打开已配置的 MCP 程序文件")
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() || executable && info.Mode().Perm()&0111 == 0 || info.Size() > 256<<20 {
		return "", errors.New("MCP 程序文件无效或超过 256 MiB")
	}
	h := sha256.New()
	n, err := io.Copy(h, io.LimitReader(f, (256<<20)+1))
	if err != nil || n != info.Size() {
		return "", errors.New("无法核对 MCP 程序版本")
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func inspectLabProgram(c *research.LabConnector) error {
	// Interpret only explicit Python/Node script files. Shell expressions and
	// command-mode flags never serve as protocol launchers.
	path, err := filepath.EvalSymlinks(c.Program)
	if err != nil {
		return errors.New("无法找到本地 MCP 程序")
	}
	name := strings.ToLower(filepath.Base(path))
	switch name {
	case "sh", "bash", "zsh", "fish", "csh", "tcsh", "ksh", "env", "osascript", "open", "sudo", "xargs", "perl", "ruby", "swift", "npm", "npx", "uv", "uvx", "bun", "deno", "dash", "busybox", "make", "java":
		return errors.New("请选择已安装的 MCP 服务程序，或通过 Python / Node 指定本机脚本文件")
	}
	c.ScriptHash = ""
	python := name == "python"
	if suffix, ok := strings.CutPrefix(name, "python"); ok && suffix != "" {
		_, err := strconv.ParseFloat(suffix, 64)
		python = err == nil
	}
	if !python && name != "node" && name != "nodejs" {
		for _, prefix := range []string{"/bin/", "/sbin/", "/usr/bin/", "/usr/sbin/", "/System/"} {
			if strings.HasPrefix(path, prefix) {
				return errors.New("请选择已安装的科研 MCP 服务程序")
			}
		}
		if len(c.Arguments) > 0 && !(len(c.Arguments) == 1 && c.Arguments[0] == "--stdio") {
			return errors.New("独立 MCP 服务支持无参数启动或 --stdio。Python / Node 服务可指定脚本文件及参数")
		}
	}
	if python || name == "node" || name == "nodejs" {
		if len(c.Arguments) == 0 {
			return errors.New("脚本解释器需要以本地 MCP 脚本的绝对路径为首个参数")
		}
		ext := strings.ToLower(filepath.Ext(c.Arguments[0]))
		if python && ext != ".py" || !python && ext != ".js" && ext != ".cjs" && ext != ".mjs" {
			return errors.New("MCP 启动脚本类型无效")
		}
		c.ScriptHash, err = labFileDigest(c.Arguments[0], false)
		if err != nil {
			return err
		}
	}
	c.ProgramHash, err = labFileDigest(c.Program, true)
	return err
}

func startLabStdio(ctx context.Context, c research.LabConnector) (*labStdio, error) {
	pinnedProgram, pinnedScript := c.ProgramHash, c.ScriptHash
	if err := inspectLabProgram(&c); err != nil {
		return nil, err
	}
	if pinnedProgram != c.ProgramHash || pinnedScript != c.ScriptHash {
		return nil, errors.New("本地 MCP 程序版本已改变，请重新保存并信任此版本")
	}
	dir, err := os.MkdirTemp("", "sci-mcp-")
	if err != nil {
		return nil, errors.New("无法创建 MCP 临时目录")
	}
	cmd := exec.CommandContext(ctx, c.Program, c.Arguments...)
	cmd.Dir = dir
	cmd.Env = []string{"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=" + dir, "TMPDIR=" + dir, "LANG=en_US.UTF-8"}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = time.Second
	in, err := cmd.StdinPipe()
	if err != nil {
		_ = os.RemoveAll(dir)
		return nil, errors.New("无法连接本地 MCP 标准输入")
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		in.Close()
		_ = os.RemoveAll(dir)
		return nil, errors.New("无法连接本地 MCP 标准输出")
	}
	if err := cmd.Start(); err != nil {
		in.Close()
		out.Close()
		_ = os.RemoveAll(dir)
		return nil, errors.New("本机 MCP 启动失败")
	}
	scan := bufio.NewScanner(out)
	scan.Buffer(make([]byte, 4096), 1<<20)
	// A child that leaves a descendant holding a pipe cannot prevent cancellation.
	stop := context.AfterFunc(ctx, func() { _ = out.Close(); _ = in.Close() })
	return &labStdio{cmd: cmd, in: in, out: out, stop: stop, scan: scan, dir: dir}, nil
}

func (s *labStdio) call(data []byte, id int, out any) error {
	if _, err := s.in.Write(append(data, '\n')); err != nil {
		return errors.New("本机 MCP 连接已关闭")
	}
	if id == 0 {
		return nil
	}
	for received := 0; received < 1<<20 && s.scan.Scan(); {
		line := s.scan.Bytes()
		received += len(line) + 1
		if received > 1<<20 {
			break
		}
		matched, err := decodeLabRPC(line, id, out)
		if err != nil || matched {
			return err
		}
	}
	return errors.New("本机 MCP 响应超限或未完成")
}
func (s *labStdio) close() {
	s.stop()
	_ = s.out.Close()
	_ = s.in.Close()
	_ = s.cmd.Cancel()
	_ = s.cmd.Wait()
	_ = os.RemoveAll(s.dir)
}
