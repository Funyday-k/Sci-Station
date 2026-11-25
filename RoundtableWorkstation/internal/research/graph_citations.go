package research

import (
	"context"
	"crypto/sha256"
	"fmt"
	"regexp"
	"strings"
)

type paperGraphNode struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Kind  string `json:"kind"`
}

type paperGraphResult struct {
	Nodes []paperGraphNode `json:"nodes"`
	Edges []graphEdge      `json:"edges"`
}

func paperRefKey(raw string) string {
	key := strings.TrimSpace(raw)
	if doi := normalizeDOI(key); doiPattern.MatchString(doi) {
		return strings.ToLower(doi)
	}
	if arxiv := normalizeArxiv(key); arxivPattern.MatchString(arxiv) {
		return ArxivWorkID(arxiv)
	}
	return strings.ToLower(key)
}

var referenceDOI = regexp.MustCompile(`(?i)\b10\.[0-9]{4,9}/[^\s<>"\[\]]+`)
var referenceArxiv = regexp.MustCompile(`(?i)(?:arxiv:\s*|arxiv\.org/(?:abs|pdf)/)((?:[0-9]{4}\.[0-9]{4,5}|[a-z][a-z.\-]*/[0-9]{7})(?:v[0-9]+)?)\b`)

func citationKey(raw string) string {
	key := paperRefKey(raw)
	if doiPattern.MatchString(key) || arxivPattern.MatchString(key) {
		return key
	}
	if doi := referenceDOI.FindString(raw); doi != "" {
		doi = strings.TrimRight(doi, ".,;")
		for strings.HasSuffix(doi, ")") && strings.Count(doi, ")") > strings.Count(doi, "(") {
			doi = strings.TrimSuffix(doi, ")")
		}
		return paperRefKey(doi)
	}
	if match := referenceArxiv.FindStringSubmatch(raw); match != nil {
		return ArxivWorkID(match[1])
	}
	return key
}

var referenceSection = map[string]bool{
	"references": true, "bibliography": true, "works cited": true,
	"cited references": true, "literature": true, "参考文献": true, "引用文献": true,
}

var referenceEntry = regexp.MustCompile(`^(?:[-+*]|[0-9]{1,4}[.)]|\[[0-9]{1,4}\]\.?)\s+`)

func paperNoteReferences(body string) []graphOccurrence {
	var entries []graphOccurrence
	active := false
	fence := ""
	for i, raw := range strings.Split(body, "\n") {
		line := strings.TrimSpace(raw)
		if fence != "" {
			if strings.Trim(strings.TrimLeft(line, fence[:1]), " \t") == "" && strings.HasPrefix(line, fence) {
				fence = ""
			}
			continue
		}
		if strings.HasPrefix(line, "```") || strings.HasPrefix(line, "~~~") {
			fence = line[:len(line)-len(strings.TrimLeft(line, line[:1]))]
			continue
		}
		if strings.HasPrefix(line, "#") {
			heading := strings.ToLower(strings.Trim(strings.Trim(line, "#"), " \t"))
			if active && !referenceSection[heading] {
				break
			}
			active = referenceSection[heading]
			continue
		}
		if !active || line == "" {
			continue
		}
		marker := referenceEntry.FindStringIndex(line)
		if marker != nil {
			line = line[marker[1]:]
		}
		if marker != nil || len(entries) == 0 {
			entries = append(entries, graphOccurrence{Source: "paper-note", Ordinal: len(entries) + 1, Line: i + 1, EndLine: i + 1, Quote: line})
		} else {
			last := &entries[len(entries)-1]
			last.Quote += " " + line
			last.EndLine = i + 1
		}
	}
	return entries
}

func paperGraph(papers []Paper) paperGraphResult {
	return buildPaperGraph(context.Background(), papers)
}

func buildPaperGraph(ctx context.Context, papers []Paper) paperGraphResult {
	graph := paperGraphResult{Nodes: []paperGraphNode{}, Edges: []graphEdge{}}
	lookup := map[string]string{}
	ambiguous := map[string]bool{}
	external := map[string]bool{}
	edges := graphEdges{}
	for _, paper := range papers {
		graph.Nodes = append(graph.Nodes, paperGraphNode{paper.ID, paper.Title, "paper"})
		for _, identifier := range []string{paper.ID, paper.DOI, paper.Arxiv, paper.Citekey, paper.URL, paper.Title} {
			key := paperRefKey(identifier)
			if key == "" {
				continue
			}
			if id, exists := lookup[key]; exists && id != paper.ID {
				ambiguous[key] = true
			} else {
				lookup[key] = paper.ID
			}
		}
	}
	for _, paper := range papers {
		if ctx.Err() != nil {
			return graph
		}
		occurrences := paperNoteReferences(paper.Notes)
		for i, ref := range paper.References {
			occurrences = append(occurrences, graphOccurrence{Source: "metadata", Ordinal: i + 1, Quote: ref})
		}
		for _, occurrence := range occurrences {
			key := citationKey(occurrence.Quote)
			if key == "" {
				continue
			}
			target := lookup[key]
			if target == "" || ambiguous[key] {
				target = "reference:" + key
				if !doiPattern.MatchString(key) && !arxivPattern.MatchString(key) {
					target = fmt.Sprintf("reference:text:%x", sha256.Sum256([]byte(key)))
				}
				if !external[target] {
					graph.Nodes = append(graph.Nodes, paperGraphNode{target, key, "reference"})
					external[target] = true
				}
			}
			if target != paper.ID {
				occurrence.SourceRevision = paper.Revision
				edges.link(paper.ID, target, "cites").record(occurrence)
			}
		}
	}
	graph.Edges = sortedGraphEdges(edges)
	return graph
}
