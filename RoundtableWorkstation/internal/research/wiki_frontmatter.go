package research

import (
	"errors"
	"io"
	"net/http"
	"slices"
	"strings"

	"go.yaml.in/yaml/v3"
)

type wikiMetadataEntry struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

func readWikiFrontmatter(contents string) (map[string]any, error) {
	lines := strings.Split(strings.ReplaceAll(strings.ReplaceAll(contents, "\r\n", "\n"), "\r", "\n"), "\n")
	end := wikiBodyStart(lines)
	if end == 0 {
		return nil, nil
	}
	decoder := yaml.NewDecoder(strings.NewReader(strings.Join(lines[1:end-1], "\n")))
	var node yaml.Node
	if err := decoder.Decode(&node); errors.Is(err, io.EOF) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	if len(node.Content) != 1 || node.Content[0].Kind != yaml.MappingNode {
		return nil, errors.New("元数据必须是 YAML 映射")
	}
	var extra yaml.Node
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return nil, errors.New("元数据只能包含一份 YAML 文档")
	}
	if err := normalizeWikiYAML(&node); err != nil {
		return nil, err
	}
	var mapping map[string]any
	if err := node.Decode(&mapping); err != nil {
		return nil, err
	}
	return mapping, nil
}

func normalizeWikiYAML(node *yaml.Node) error {
	if node.Kind == yaml.MappingNode {
		for i := 0; i < len(node.Content); i += 2 {
			key := node.Content[i]
			if key.Kind != yaml.ScalarNode || (key.ShortTag() != "!!str" && key.ShortTag() != "!!merge") {
				return errors.New("YAML 元数据的键必须是字符串")
			}
		}
	}
	if node.ShortTag() == "!!timestamp" {
		node.Tag = "!!str"
	}
	for _, child := range node.Content {
		if err := normalizeWikiYAML(child); err != nil {
			return err
		}
	}
	return nil
}

func wikiContentsOK(w http.ResponseWriter, n Note, in noteInput) bool {
	if in.Body == nil || *in.Body == n.Body || len(*in.Body) > 2<<20 {
		return true
	}
	if _, err := readWikiFrontmatter(*in.Body); err != nil {
		jsonFail(w, 400, "Markdown 元数据有误："+err.Error())
		return false
	}
	return true
}

func (s *Service) noteFrontmatter(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	s.mu.RUnlock()
	if !ok {
		return
	}
	n, ok := d.Notes[r.PathValue("note")]
	if !found(w, ok && !n.Archived) {
		return
	}
	if r.URL.Query().Has("revision") && !revisionOK(w, n.Revision, queryRevision(r.URL.Query())) {
		return
	}
	mapping, err := readWikiFrontmatter(n.Body)
	if err != nil {
		jsonFail(w, 422, "Markdown 元数据有误："+err.Error())
		return
	}
	keys := make([]string, 0, len(mapping))
	for key := range mapping {
		keys = append(keys, key)
	}
	slices.Sort(keys)
	entries := make([]wikiMetadataEntry, 0, len(keys))
	for _, key := range keys {
		value, ok := mapping[key].(string)
		if !ok {
			if mapping[key] == nil {
				value = "-"
			} else {
				encoded, _ := yaml.Marshal(mapping[key])
				value = strings.TrimSuffix(string(encoded), "\n")
			}
		}
		entries = append(entries, wikiMetadataEntry{Key: key, Value: value})
	}
	jsonReply(w, 200, entries)
}
