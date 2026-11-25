package research

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"go.yaml.in/yaml/v3"
)

const defaultWikiSnippets = `- trigger: ";h2"
  title: "Heading 2"
  body: "## ${cursor}"
- trigger: ";eq"
  title: "Display Equation"
  body: |
    $$
    ${cursor}
    $$
- trigger: ";fig"
  title: "Figure Reference"
  body: "![${cursor}](../figures/)"
- trigger: ";todo"
  title: "Todo Item"
  body: "- [ ] ${cursor}"
- trigger: ";paper"
  title: "Paper Note"
  body: |
    ## Why It Matters

    ${cursor}

    ## Method


    ## Limits
`

type wikiSnippet struct {
	Trigger string `json:"trigger" yaml:"trigger"`
	Title   string `json:"title" yaml:"title"`
	Body    string `json:"body" yaml:"body"`
}

type wikiSnippetSettings struct {
	Content    string        `json:"content"`
	Revision   string        `json:"revision"`
	Snippets   []wikiSnippet `json:"snippets"`
	ParseError string        `json:"parseError,omitempty"`
}

func parseWikiSnippets(content string) ([]wikiSnippet, error) {
	decoder := yaml.NewDecoder(strings.NewReader(content))
	var snippets []wikiSnippet
	if err := decoder.Decode(&snippets); err != nil && !errors.Is(err, io.EOF) {
		return nil, err
	}
	var extra yaml.Node
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return nil, errors.New("片段只能包含一份 YAML 文档")
	}
	if len(snippets) > 100 {
		return nil, errors.New("Markdown 片段最多 100 条")
	}
	seen := map[string]bool{}
	for i := range snippets {
		entry := &snippets[i]
		if entry.Title == "" {
			entry.Title = entry.Trigger
		}
		if !label(entry.Trigger, 80) || strings.TrimSpace(entry.Trigger) != entry.Trigger ||
			!label(entry.Title, 200) || len(entry.Body) > 64<<10 || strings.TrimSpace(entry.Body) == "" || seen[entry.Trigger] {
			return nil, fmt.Errorf("第 %d 条片段的触发词、标题或正文无效，或触发词重复", i+1)
		}
		seen[entry.Trigger] = true
	}
	return snippets, nil
}

func snippetSettings(content string) wikiSnippetSettings {
	revision := sha256.Sum256([]byte(content))
	snippets, err := parseWikiSnippets(content)
	settings := wikiSnippetSettings{Content: content, Revision: hex.EncodeToString(revision[:]), Snippets: snippets}
	if err != nil {
		settings.ParseError = err.Error()
	}
	if len(settings.Snippets) == 0 {
		settings.Snippets, _ = parseWikiSnippets(defaultWikiSnippets)
	}
	return settings
}

func readWikiSnippetFile(path string) (wikiSnippetSettings, error) {
	if info, err := os.Lstat(filepath.Dir(path)); err == nil && !info.IsDir() {
		return wikiSnippetSettings{}, errors.New("无法读取片段设置目录")
	}
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return snippetSettings(defaultWikiSnippets), nil
	}
	if err != nil {
		return wikiSnippetSettings{}, err
	}
	if !info.Mode().IsRegular() || info.Size() > 512<<10 {
		return wikiSnippetSettings{}, errors.New("片段设置必须是普通 YAML 文件，且不超过 512 KiB")
	}
	body, err := os.ReadFile(path)
	if err != nil {
		return wikiSnippetSettings{}, err
	}
	return snippetSettings(string(body)), nil
}

func (s *Service) wikiSnippets(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Content  string `json:"content"`
		Revision string `json:"revision"`
	}
	if r.Method == http.MethodPut && !payload(w, r, &in) {
		return
	}
	path := filepath.Join(s.dir, "settings", "markdown_snippets.yaml")
	s.mu.Lock()
	defer s.mu.Unlock()
	current, err := readWikiSnippetFile(path)
	if err != nil {
		jsonFail(w, 500, "无法读取 Markdown 片段设置")
		return
	}
	if r.Method != http.MethodPut {
		jsonReply(w, 200, current)
		return
	}
	if in.Revision == "" {
		jsonFail(w, 428, "请携带已读取的片段修订")
		return
	}
	if in.Revision != current.Revision {
		jsonFail(w, 409, "片段设置已改变，当前草稿可以复制后与最新版本对照")
		return
	}
	if len(in.Content) > 512<<10 {
		jsonFail(w, 400, "Markdown 片段设置超过 512 KiB")
		return
	}
	next := snippetSettings(in.Content)
	if next.ParseError != "" {
		jsonFail(w, 400, "Markdown 片段设置有误："+next.ParseError)
		return
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil || atomicWrite(path, []byte(in.Content)) != nil {
		jsonFail(w, 500, "无法保存 Markdown 片段设置")
		return
	}
	jsonReply(w, 200, next)
}
