package research

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// ParseDiscoveryFeed supports the Swift importer's JSON array and JSONL
// records. Imported bibliographic claims retain their file provenance.
func ParseDiscoveryFeed(data string, limit int) ([]DiscoveryCandidate, error) {
	if limit < 1 || limit > 500 {
		return nil, fmt.Errorf("每日文献候选上限无效")
	}
	if !utf8.ValidString(data) {
		return nil, fmt.Errorf("每日文献文件必须是 UTF-8")
	}
	data = strings.TrimSpace(strings.TrimPrefix(data, "\ufeff"))
	var rows []json.RawMessage
	if strings.HasPrefix(data, "[") {
		if err := json.Unmarshal([]byte(data), &rows); err != nil {
			return nil, fmt.Errorf("每日文献 JSON 列表无效")
		}
	} else {
		scanner := bufio.NewScanner(strings.NewReader(data))
		scanner.Buffer(make([]byte, 16<<10), 1<<20)
		for scanner.Scan() {
			raw := bytes.TrimSpace(scanner.Bytes())
			if len(raw) != 0 {
				rows = append(rows, slices.Clone(raw))
			}
		}
		if err := scanner.Err(); err != nil {
			return nil, fmt.Errorf("每日文献条目过大")
		}
	}
	if len(rows) == 0 || len(rows) > 5000 {
		return nil, fmt.Errorf("每日文献文件需要 1–5000 个条目")
	}
	items := make([]DiscoveryCandidate, 0, min(limit, len(rows)))
	for i, raw := range rows {
		candidate, err := discoveryFeedCandidate(raw)
		if err != nil {
			return nil, fmt.Errorf("每日文献第 %d 条：%w", i+1, err)
		}
		if len(items) < limit {
			items = append(items, candidate)
		}
	}
	return items, nil
}

func discoveryFeedCandidate(raw json.RawMessage) (DiscoveryCandidate, error) {
	var row map[string]json.RawMessage
	if json.Unmarshal(raw, &row) != nil || row == nil {
		return DiscoveryCandidate{}, fmt.Errorf("需要文献对象")
	}
	first := func(keys ...string) string {
		for _, key := range keys {
			var value string
			if json.Unmarshal(row[key], &value) == nil && strings.TrimSpace(value) != "" {
				return strings.TrimSpace(value)
			}
		}
		return ""
	}
	list := func(key string) []string {
		var value []string
		if json.Unmarshal(row[key], &value) != nil {
			value = strings.Split(first(key), ",")
		}
		out := []string{}
		for _, item := range value {
			item = strings.TrimSpace(item)
			if item != "" && !slices.Contains(out, item) {
				out = append(out, item)
			}
		}
		return out
	}
	title := first("title", "display_title", "displayTitle")
	abstract := first("abstract", "summary")
	if !label(title, 512) || len(abstract) > 128<<10 {
		return DiscoveryCandidate{}, fmt.Errorf("论文标题或摘要无效")
	}
	arxiv := ""
	for _, key := range []string{"arxiv", "arxiv_id", "id", "external_key"} {
		id := normalizeArxiv(first(key))
		if arxivPattern.MatchString(id) {
			arxiv = id
			break
		}
	}
	doi := normalizeDOI(first("doi"))
	if doi == "" {
		doi = normalizeDOI(first("external_key"))
	}
	if !doiPattern.MatchString(doi) {
		doi = ""
	}
	sourceURL := first("url", "source_url")
	if !paperHTTPURL(sourceURL) {
		sourceURL = ""
	}
	if arxiv != "" {
		sourceURL = "https://arxiv.org/abs/" + arxiv
	} else if sourceURL == "" && doi != "" {
		sourceURL = "https://doi.org/" + doi
	}
	year := 0
	for _, key := range []string{"published_year", "year"} {
		if json.Unmarshal(row[key], &year) != nil {
			year, _ = strconv.Atoi(first(key))
		}
		if year > 0 {
			break
		}
	}
	date := first("published", "published_date", "published_at")
	published, err := time.Parse(time.RFC3339, date)
	if err != nil {
		published, _ = time.Parse(time.DateOnly, date)
	}
	if !published.IsZero() && year == 0 {
		year = published.Year()
	}
	primary := first("primary_category", "primaryCategory")
	tags := append(list("categories"), list("category")...)
	firstCategory := primary == "" && len(tags) != 0
	if firstCategory {
		primary = tags[0]
	}
	provider := first("source")
	sourceKey := sourceURL
	if sourceKey == "" {
		sourceKey = strings.ToLower(provider + ":" + title)
	}
	checksum := sha256.Sum256([]byte(sourceKey))
	paper := DiscoveryCandidate{PaperMetadata: PaperMetadata{
		Title: title, Authors: list("authors"), Abstract: abstract, Year: year, Arxiv: arxiv, DOI: doi,
		URL: sourceURL, Tags: tags, Categories: tags, MetadataSource: "daily-feed",
	}, Provider: provider, PrimaryCategory: primary, FirstCategory: firstCategory, FeedID: hex.EncodeToString(checksum[:16])}
	if !published.IsZero() {
		paper.PublishedAt = published.UTC().Format(time.RFC3339)
	}
	return paper, nil
}

// LibraryDiscoveryCandidates preserves the actual paper ID for offline selection.
func LibraryDiscoveryCandidates(recent []Paper, cutoff time.Time) []DiscoveryCandidate {
	candidates := make([]DiscoveryCandidate, 0, len(recent))
	for _, paper := range recent {
		if paper.CreatedAt.Before(cutoff) && paper.UpdatedAt.Before(cutoff) {
			continue
		}
		candidates = append(candidates, DiscoveryCandidate{PaperID: paper.ID, Provider: "library", PaperMetadata: PaperMetadata{
			Title: paper.Title, Authors: paper.Authors, Abstract: paper.Abstract, Year: paper.Year,
			DOI: paper.DOI, Arxiv: paper.Arxiv, URL: paper.URL, Tags: paper.Tags, Categories: paper.Categories, MetadataSource: paper.MetadataSource,
		}})
	}
	return candidates
}
