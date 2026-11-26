package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"scistation.local/desktop/internal/plugins"
)

func runPluginCLI(args []string, stdout, stderr io.Writer) int {
	const usage = `用法
  sci-station plugin pack --manifest <manifest.json> [--module <module.wasm>] --out <package.json>
  sci-station plugin validate <package.json>
  sci-station plugin catalog --name <name> --out <catalog.json> <package.json>...
`
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return 2
	}
	switch args[0] {
	case "help", "-h", "--help":
		fmt.Fprint(stdout, usage)
		return 0
	case "pack", "validate", "catalog":
	default:
		fmt.Fprintf(stderr, "未知插件命令 %q\n%s", args[0], usage)
		return 2
	}

	flags := flag.NewFlagSet("plugin "+args[0], flag.ContinueOnError)
	flags.SetOutput(stderr)
	flags.Usage = func() { fmt.Fprint(stderr, usage) }
	var manifestPath, modulePath, name, out string
	switch args[0] {
	case "pack":
		flags.StringVar(&manifestPath, "manifest", "", "manifest JSON 文件")
		flags.StringVar(&modulePath, "module", "", "WebAssembly 模块文件")
		flags.StringVar(&out, "out", "", "待生成的插件包路径")
	case "catalog":
		flags.StringVar(&name, "name", "", "市场来源显示名称")
		flags.StringVar(&out, "out", "", "待生成的目录文件路径")
	}
	if err := flags.Parse(args[1:]); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}

	var err error
	switch args[0] {
	case "pack":
		if manifestPath == "" || out == "" || flags.NArg() != 0 {
			flags.Usage()
			return 2
		}
		err = packPlugin(manifestPath, modulePath, out)
		if err == nil {
			fmt.Fprintf(stdout, "已生成插件包 %s\n", out)
		}
	case "validate":
		if flags.NArg() != 1 {
			flags.Usage()
			return 2
		}
		path := flags.Arg(0)
		var raw []byte
		raw, err = readPluginFile(path, plugins.MaxPackageBytes)
		if err == nil {
			manifest, parseErr := plugins.ParsePackage(raw)
			if parseErr != nil {
				err = fmt.Errorf("插件包 %q: %w", path, parseErr)
			} else {
				fmt.Fprintf(stdout, "%s %s\nSHA-256 %x\n", manifest.ID, manifest.Version, sha256.Sum256(raw))
			}
		}
	case "catalog":
		if strings.TrimSpace(name) == "" || out == "" || flags.NArg() == 0 {
			flags.Usage()
			return 2
		}
		err = generatePluginCatalog(strings.TrimSpace(name), out, flags.Args())
		if err == nil {
			fmt.Fprintf(stdout, "已生成目录 %s（%d 个插件）\n", out, flags.NArg())
		}
	}
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

func packPlugin(manifestPath, modulePath, out string) error {
	raw, err := readPluginFile(manifestPath, plugins.MaxPackageBytes)
	if err != nil {
		return err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return fmt.Errorf("manifest %q: %w", manifestPath, err)
	}
	if fields == nil {
		return fmt.Errorf("manifest %q 必须是 JSON 对象", manifestPath)
	}
	if _, exists := fields["module"]; exists {
		return fmt.Errorf("manifest %q 已含 module 字段，请使用 --module 提供独立的 WASM 文件", manifestPath)
	}
	raw = bytes.TrimSpace(raw)
	if modulePath != "" {
		module, err := readPluginFile(modulePath, plugins.MaxModuleBytes)
		if err != nil {
			return err
		}
		if len(module) == 0 {
			return fmt.Errorf("WASM 模块 %q 为空", modulePath)
		}
		encoded, err := json.Marshal(module)
		if err != nil {
			return err
		}
		// Keep the original fields so the package parser can detect duplicate keys.
		raw = raw[:len(raw)-1]
		if len(fields) > 0 {
			raw = append(raw, ',')
		}
		raw = append(raw, `"module":`...)
		raw = append(raw, encoded...)
		raw = append(raw, '}')
	}
	var formatted bytes.Buffer
	if err := json.Indent(&formatted, raw, "", "  "); err != nil {
		return fmt.Errorf("manifest %q: %w", manifestPath, err)
	}
	formatted.WriteByte('\n')
	packaged := formatted.Bytes()
	if _, err := plugins.ParsePackage(packaged); err != nil {
		return fmt.Errorf("插件包校验失败: %w", err)
	}
	return writeNewPluginFile(out, packaged)
}

func generatePluginCatalog(name, out string, packagePaths []string) error {
	if len(packagePaths) > plugins.MaxCatalogEntries {
		return fmt.Errorf("目录最多包含 %d 个插件", plugins.MaxCatalogEntries)
	}
	directory, err := os.Stat(filepath.Dir(out))
	if err != nil {
		return err
	}
	catalog := plugins.Catalog{SchemaVersion: 1, Name: name, Plugins: make([]plugins.CatalogEntry, 0, len(packagePaths))}
	for _, path := range packagePaths {
		parent, err := os.Stat(filepath.Dir(path))
		if err != nil {
			return err
		}
		if !os.SameFile(parent, directory) {
			return fmt.Errorf("插件包 %q 必须和目录文件位于同一目录", path)
		}
		raw, err := readPluginFile(path, plugins.MaxPackageBytes)
		if err != nil {
			return err
		}
		manifest, err := plugins.ParsePackage(raw)
		if err != nil {
			return fmt.Errorf("插件包 %q: %w", path, err)
		}
		// Escape colons as well so filenames cannot be interpreted as URL schemes.
		packageURL := strings.ReplaceAll(url.PathEscape(filepath.Base(path)), ":", "%3A")
		catalog.Plugins = append(catalog.Plugins, plugins.CatalogEntry{
			ID:           manifest.ID,
			Version:      manifest.Version,
			Name:         manifest.Name,
			Author:       manifest.Author,
			Description:  manifest.Description,
			URL:          packageURL,
			SHA256:       fmt.Sprintf("%x", sha256.Sum256(raw)),
			Capabilities: append([]string{}, manifest.Capabilities()...),
		})
	}
	sort.Slice(catalog.Plugins, func(i, j int) bool { return catalog.Plugins[i].ID < catalog.Plugins[j].ID })
	raw, err := json.MarshalIndent(catalog, "", "  ")
	if err != nil {
		return err
	}
	raw = append(raw, '\n')
	if _, err := plugins.ParseCatalog(raw, "https://example.invalid/plugins/catalog.json"); err != nil {
		return fmt.Errorf("目录校验失败: %w", err)
	}
	return writeNewPluginFile(out, raw)
}

func readPluginFile(path string, limit int) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("%q 必须是普通文件", path)
	}
	if info.Size() > int64(limit) {
		return nil, fmt.Errorf("%q 超过 %d 字节上限", path, limit)
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, int64(limit)+1))
	if err != nil {
		return nil, fmt.Errorf("读取 %q: %w", path, err)
	}
	if len(data) > limit {
		return nil, fmt.Errorf("%q 超过 %d 字节上限", path, limit)
	}
	return data, nil
}

func writeNewPluginFile(path string, data []byte) error {
	temporary, err := os.CreateTemp(filepath.Dir(path), ".roundtable-plugin-*")
	if err != nil {
		return err
	}
	defer os.Remove(temporary.Name())
	defer temporary.Close()
	if _, err := temporary.Write(data); err != nil {
		return err
	}
	if err := temporary.Chmod(0644); err != nil {
		return err
	}
	if err := temporary.Sync(); err != nil {
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	// A link publishes complete contents and fails atomically if path exists.
	if err := os.Link(temporary.Name(), path); errors.Is(err, os.ErrExist) {
		return fmt.Errorf("输出文件 %q 已存在，请指定新路径", path)
	} else if err != nil {
		return fmt.Errorf("生成 %q: %w", path, err)
	}
	return nil
}
