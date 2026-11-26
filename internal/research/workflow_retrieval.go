package research

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"slices"
	"strings"
	"unicode/utf8"
)

const (
	retrievalSourceLimit   = 256
	retrievalSourceBytes   = 4 << 20
	retrievalProjectBytes  = 16 << 20
	retrievalProjectChunks = 8192
)

type WorkflowRetrievalOptions struct {
	Mode    string
	Rebuild bool
	Source  SourceLocation
}

type WorkflowRetrievalMatch struct {
	SourceLocation
	Title            string  `json:"title"`
	Hash             string  `json:"hash"`
	Text             string  `json:"text"`
	Line             int     `json:"line"`
	EndLine          int     `json:"endLine"`
	Heading          string  `json:"heading,omitempty"`
	ChunkID          string  `json:"chunkId"`
	SourceHashStatus string  `json:"sourceHashStatus"`
	LexicalScore     float64 `json:"lexicalScore"`
	EmbeddingScore   float64 `json:"embeddingScore,omitempty"`
	Score            float64 `json:"score"`
	core             bool
}

type WorkflowRetrievalTrace struct {
	Mode           string `json:"mode"`
	QueryHash      string `json:"queryHash,omitempty"`
	Model          string `json:"model,omitempty"`
	CacheVersion   int    `json:"cacheVersion,omitempty"`
	CacheStatus    string `json:"cacheStatus,omitempty"`
	FallbackReason string `json:"fallbackReason,omitempty"`
	Sources        int    `json:"sources"`
	Verified       int    `json:"verified"`
	Skipped        int    `json:"skipped"`
	Reused         int    `json:"reused"`
	Updated        int    `json:"updated"`
	Removed        int    `json:"removed"`
	Bounded        bool   `json:"bounded"`
}

type WorkflowRetrieval struct {
	Items   []WorkflowRetrievalMatch `json:"items"`
	Limited bool                     `json:"limited"`
	Trace   WorkflowRetrievalTrace   `json:"trace"`
}

func workflowRetrievalQuery(query string, options WorkflowRetrievalOptions) (string, []string, error) {
	query = strings.ToLower(strings.TrimSpace(query))
	if options.Rebuild {
		if options.Mode != "hybrid" || query != "" || options.Source.Page != 0 || options.Source.Offset != 0 {
			return "", nil, ErrWorkflowSource
		}
		return "", nil, nil
	}
	if options.Source != (SourceLocation{}) || (options.Mode != "lexical" && options.Mode != "hybrid") ||
		query == "" || utf8.RuneCountInString(query) > 240 || strings.ContainsRune(query, 0) {
		return "", nil, errors.New("请输入 1 至 240 个字符以检索项目原文")
	}
	terms := retrievalTokens(query)
	slices.Sort(terms)
	return query, slices.Compact(terms), nil
}

// FindWorkflowProject searches only the active project's registered text records.
// The existing per-source search retains exact matching and PDF page extraction.
func (s *Service) FindWorkflowProject(ctx context.Context, project, query string, options WorkflowRetrievalOptions) (WorkflowRetrieval, error) {
	out := WorkflowRetrieval{Items: []WorkflowRetrievalMatch{}, Trace: WorkflowRetrievalTrace{Mode: "lexical"}}
	trace := &out.Trace
	if !validID(project) {
		return out, ErrWorkflowSource
	}
	query, terms, err := workflowRetrievalQuery(query, options)
	if err != nil {
		return out, err
	}
	if query != "" {
		trace.QueryHash = fmt.Sprintf("sha256:%x", sha256.Sum256([]byte(query)))
	}

	select {
	case s.retrievalWorker <- struct{}{}:
		defer func() { <-s.retrievalWorker }()
	case <-ctx.Done():
		return out, ctx.Err()
	}
	sources, err := s.workflowRetrievalSources(project)
	if err != nil {
		return out, err
	}
	eligible := sources
	if options.Source != (SourceLocation{}) {
		i := slices.IndexFunc(sources, func(source workflowRetrievalSource) bool {
			return source.SourceLocation == options.Source
		})
		if i < 0 {
			return out, ErrWorkflowSource
		}
		sources = sources[i : i+1]
	}
	trace.Sources = len(sources)
	if len(sources) > retrievalSourceLimit {
		sources = sources[:retrievalSourceLimit]
		trace.Bounded = true
	}

	useVectors := options.Mode == "hybrid" && (len(terms) > 0 || options.Rebuild)
	var old, next retrievalCache
	var cachePath string
	if useVectors {
		trace.Mode, trace.Model, trace.CacheVersion = "hybrid", retrievalModel, retrievalCacheVersion
		cachePath = s.retrievalCachePath(project)
		old, trace.CacheStatus = readRetrievalCache(cachePath, project)
		next = newRetrievalCache(project)
		if options.Source.ID != "" {
			for _, source := range eligible {
				if row, found := old.Sources[source.key()]; found {
					next.Sources[source.key()] = row
				}
			}
		}
	} else if options.Mode == "hybrid" {
		trace.FallbackReason = "query_has_no_vector"
	} else {
		trace.FallbackReason = "embeddings_disabled"
	}

	var queryVector retrievalVector
	if useVectors && !options.Rebuild {
		queryVector = vectorForRetrieval(retrievalTokens(query))
	}
	bytesLeft, chunksLeft := retrievalProjectBytes, retrievalProjectChunks
	for i, source := range sources {
		if err := ctx.Err(); err != nil {
			return out, err
		}
		if bytesLeft == 0 || chunksLeft == 0 {
			trace.Skipped += len(sources) - i
			trace.Bounded = true
			break
		}
		text, title, hash, err := s.readWorkflowRetrievalSource(project, source.SourceLocation, min(bytesLeft, retrievalSourceBytes))
		if errors.Is(err, os.ErrPermission) {
			return out, ErrWorkflowSource
		}
		key := source.key()
		if err != nil || !utf8.ValidString(text) || strings.ContainsRune(text, 0) {
			if options.Source.ID != "" {
				if errors.Is(err, errRetrievalSourceTooLarge) {
					return out, err
				}
				return out, errors.New("无法读取所选原文，请检查来源后再重建")
			}
			trace.Bounded = trace.Bounded || errors.Is(err, errRetrievalSourceTooLarge)
			trace.Skipped++
			delete(next.Sources, key)
			continue
		}
		trace.Verified++
		bytesLeft -= len(text)
		text = normalizeWorkflowText(text)
		chunks, limited := workflowRetrievalChunks(text, source.Kind != "material" || strings.HasSuffix(strings.ToLower(title), ".md"))
		if len(chunks) > chunksLeft {
			chunks, limited = chunks[:chunksLeft], true
		}
		trace.Bounded = trace.Bounded || limited
		chunksLeft -= len(chunks)
		var row retrievalCacheRow
		if useVectors {
			var reused bool
			row, reused = updateRetrievalVectors(old.Sources[key], hash, chunks, options.Rebuild)
			next.Sources[key] = row
			if reused {
				trace.Reused++
			} else {
				trace.Updated++
			}
		}
		if !options.Rebuild {
			out.Items = append(out.Items, rankWorkflowChunks(source, title, hash, chunks, query, terms, queryVector, row.Vectors)...)
		}
	}
	if err := ctx.Err(); err != nil {
		return out, err
	}
	// The active directory, enabled source modules, and record memberships must
	// still authorize the sources when the fetch completes.
	current, err := s.workflowRetrievalSources(project)
	if err != nil || !retrievalSourcesStillVisible(sources, current) {
		return out, ErrWorkflowSource
	}
	if useVectors {
		for key := range old.Sources {
			if _, found := next.Sources[key]; !found {
				trace.Removed++
			}
		}
		changed := trace.CacheStatus != "current" || trace.Updated+trace.Removed > 0 || options.Rebuild
		if changed {
			if err := writeRetrievalCache(cachePath, next); err != nil {
				trace.CacheStatus, trace.Mode, trace.FallbackReason = "unavailable", "lexical", "cache_write_failed"
			} else if options.Rebuild {
				trace.CacheStatus = "rebuilt"
			}
		}
	}
	hybrid := trace.Mode == "hybrid"
	out.Items = scoreWorkflowMatches(out.Items, hybrid)
	out.Limited = trace.Bounded || len(out.Items) > retrievalResultLimit
	out.Items = out.Items[:min(retrievalResultLimit, len(out.Items))]
	return out, nil
}

func retrievalSourcesStillVisible(searched, current []workflowRetrievalSource) bool {
	visible := make(map[string]bool, len(current))
	for _, source := range current {
		visible[source.key()] = true
	}
	for _, source := range searched {
		if !visible[source.key()] {
			return false
		}
	}
	return true
}

func updateRetrievalVectors(row retrievalCacheRow, hash string, chunks []retrievalChunk, rebuild bool) (retrievalCacheRow, bool) {
	if !rebuild && row.Hash == hash && len(row.Vectors) == len(chunks) {
		return row, true
	}
	row = retrievalCacheRow{Hash: hash, Vectors: make([]retrievalVector, len(chunks))}
	for i, chunk := range chunks {
		row.Vectors[i] = vectorForRetrieval(retrievalTokens(chunk.text))
	}
	return row, false
}

func rankWorkflowChunks(source workflowRetrievalSource, title, hash string, chunks []retrievalChunk, query string, terms []string, vector retrievalVector, vectors []retrievalVector) []WorkflowRetrievalMatch {
	hits := make([]WorkflowRetrievalMatch, 0)
	for i, chunk := range chunks {
		lexical, at := lexicalRetrievalScore(query, terms, retrievalTokens(chunk.text), chunk.text)
		semantic := 0.0
		if len(vectors) != 0 {
			semantic = vector.cosine(vectors[i])
		}
		if lexical == 0 && semantic <= 0 {
			continue
		}
		runes := []rune(chunk.text)
		begin := max(0, at-35)
		end := min(len(runes), begin+240)
		passage := string(runes[begin:end])
		line := chunk.line + strings.Count(string(runes[:begin]), "\n")
		location := source.SourceLocation
		location.Offset = chunk.offset + begin
		hits = append(hits, WorkflowRetrievalMatch{
			SourceLocation: location, Title: title, Hash: hash, Text: passage, Line: line,
			EndLine: line + strings.Count(passage, "\n"), Heading: chunk.heading,
			ChunkID:          fmt.Sprintf("%s:%d-%d:%d", source.key(), chunk.line, chunk.lastLine, chunk.offset),
			SourceHashStatus: "fresh", LexicalScore: lexical, EmbeddingScore: semantic, core: source.core,
		})
	}
	return hits
}

func scoreWorkflowMatches(hits []WorkflowRetrievalMatch, hybrid bool) []WorkflowRetrievalMatch {
	hits = slices.DeleteFunc(hits, func(hit WorkflowRetrievalMatch) bool {
		return !hybrid && hit.LexicalScore == 0
	})
	for i := range hits {
		hit := &hits[i]
		hit.Score = hit.LexicalScore
		if hybrid {
			hit.Score = 0.55*hit.LexicalScore + 0.45*hit.EmbeddingScore
			if hit.core {
				hit.Score += 0.2
			}
		} else {
			hit.EmbeddingScore = 0
		}
	}
	slices.SortFunc(hits, func(a, b WorkflowRetrievalMatch) int {
		switch {
		case a.Score > b.Score:
			return -1
		case a.Score < b.Score:
			return 1
		default:
			return strings.Compare(a.ChunkID, b.ChunkID)
		}
	})
	return hits
}
