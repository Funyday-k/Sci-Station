package research

import (
	"context"
	"encoding/json"
	"path/filepath"
	"regexp"
	"strings"
)

var (
	localDOILine   = regexp.MustCompile(`(?im)^\s*(?:doi\s*:\s*|https?://(?:dx\.)?doi\.org/)(10\.[0-9]{4,9}/[^\s<>"]+)`)
	localArxivLine = regexp.MustCompile(`(?im)^\s*arxiv\s*:\s*((?:[0-9]{4}\.[0-9]{4,5}|[a-z][a-z.\-]*/[0-9]{7})(?:v[0-9]+)?)\b`)
)

func pdfImportDetails(ctx context.Context, stagedPath string) (result struct {
	Title     string
	Author    string
	FirstPage string `json:"first_page"`
}) {
	select {
	case pageWorkers <- struct{}{}:
		defer func() { <-pageWorkers }()
	case <-ctx.Done():
		return result
	}
	if raw, err := nativePDFPage(stagedPath, "import-metadata", 0, ""); err == nil {
		if err := json.Unmarshal(raw, &result); err == nil {
			return result
		}
	}
	return
}

func (p *paperImport) readLocalMetadata(ctx context.Context, stagedPath, filename string) {
	name := filepath.Base(filename)
	base := strings.TrimSuffix(name, filepath.Ext(name))
	local := pdfImportDetails(ctx, stagedPath)
	if p.Title == "" {
		p.Title = firstPaperValue(local.Title, base)
	}
	if len(p.Authors) == 0 {
		p.Authors = strings.FieldsFunc(strings.ReplaceAll(local.Author, " and ", ";"), func(r rune) bool { return r == ';' })
	}
	if p.DOI == "" {
		if match := localDOILine.FindStringSubmatch(local.FirstPage); len(match) > 1 {
			p.DOI = normalizeDOI(strings.TrimRight(match[1], ".,;"))
		}
	}
	if p.Arxiv == "" {
		if match := localArxivLine.FindStringSubmatch(local.FirstPage); len(match) > 1 {
			p.Arxiv = normalizeArxiv(match[1])
		} else if candidate := normalizeArxiv(base); arxivPattern.MatchString(candidate) {
			p.Arxiv = candidate
		}
	}
	if p.MetadataSource == "" {
		p.MetadataSource = "PDF"
	}
}
