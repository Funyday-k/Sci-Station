package research

import (
	"fmt"
	"net/url"
	"regexp"
	"strings"
)

var inspirePattern = regexp.MustCompile(`^[0-9]{1,12}$`)
var errPaperIdentifier = fmt.Errorf("%w：请输入 DOI、arXiv 编号、INSPIRE 链接或 HTTP(S) 网址", errInvalidPaper)
var publisherDOIPath = regexp.MustCompile(`(?i)/(?:doi(?:/(?:abs|full|epdf))?|articles?|abstract|fulltext)/(10\.[0-9]{4,9}/[-._;()/:a-z0-9]+)$`)

func normalizeDOI(value string) string {
	value = strings.TrimSpace(value)
	if u, err := url.Parse(value); err == nil && paperHTTPURL(value) && (strings.EqualFold(u.Hostname(), "doi.org") || strings.EqualFold(u.Hostname(), "dx.doi.org")) {
		value = strings.TrimPrefix(u.Path, "/")
	}
	return strings.TrimSpace(strings.TrimPrefix(strings.ToLower(value), "doi:"))
}

func normalizeArxiv(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.TrimSpace(strings.TrimPrefix(value, "arxiv:"))
	value = strings.TrimSpace(strings.TrimPrefix(value, "arxiv "))
	if u, err := url.Parse(value); err == nil && paperHTTPURL(value) && (u.Hostname() == "arxiv.org" || u.Hostname() == "www.arxiv.org") {
		for _, prefix := range []string{"/abs/", "/pdf/"} {
			if id, ok := strings.CutPrefix(u.Path, prefix); ok {
				value = id
				break
			}
		}
	}
	return strings.TrimSuffix(value, ".pdf")
}

func normalizeInspire(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	if u, err := url.Parse(value); err == nil && paperHTTPURL(value) && u.Hostname() == "inspirehep.net" {
		if id, ok := strings.CutPrefix(u.Path, "/literature/"); ok {
			value = strings.TrimSuffix(id, "/")
		}
	}
	return strings.TrimSpace(strings.TrimPrefix(value, "inspire:"))
}

func arxivDOIAlias(doi string) string {
	if id, ok := strings.CutPrefix(normalizeDOI(doi), "10.48550/arxiv."); ok && arxivPattern.MatchString(id) {
		return id
	}
	return ""
}

func arxivPaperIdentity(metadata PaperMetadata) string {
	if metadata.Arxiv != "" {
		return ArxivWorkID(metadata.Arxiv)
	}
	return ArxivWorkID(arxivDOIAlias(metadata.DOI))
}

func conflictingArxivRevisions(first, second string) bool {
	first, second = normalizeArxiv(first), normalizeArxiv(second)
	id := ArxivWorkID(first)
	return id != "" && id == ArxivWorkID(second) && first != id && second != id && first != second
}

func addPaperImportAliases(existing *Paper, incoming PaperMetadata) {
	if existing.DOI == "" {
		existing.DOI = incoming.DOI
	}
	if existing.Arxiv == "" {
		existing.Arxiv = incoming.Arxiv
	}
	if existing.InspireID == "" {
		existing.InspireID = incoming.InspireID
	}
	if existing.PDFURL == "" && !existing.HasPDF && !conflictingArxivRevisions(existing.Arxiv, incoming.Arxiv) {
		existing.PDFURL = incoming.PDFURL
	}
}

func (p *paperImport) prepare() error {
	p.Identifier = strings.TrimSpace(p.Identifier)
	p.URL = strings.TrimSpace(p.URL)
	p.PDFURL = strings.TrimSpace(p.PDFURL)
	if len(p.Identifier) > 4096 || len(p.URL) > 4096 || len(p.PDFURL) > 4096 ||
		len(p.DOI) > 512 || len(p.Arxiv) > 128 || len(p.InspireID) > 4096 {
		return errInvalidPaper
	}
	p.Arxiv = normalizeArxiv(p.Arxiv)
	p.DOI = normalizeDOI(p.DOI)
	p.InspireID = normalizeInspire(p.InspireID)
	if p.Identifier != "" {
		if p.Arxiv != "" || p.DOI != "" || p.InspireID != "" || p.URL != "" {
			return fmt.Errorf("%w：每行请输入一个标识符或链接", errInvalidPaper)
		}
		if err := p.identifyTarget(p.Identifier); err != nil {
			return err
		}
		p.Identifier = ""
	} else if p.URL != "" && p.DOI == "" && p.Arxiv == "" && p.InspireID == "" {
		if err := p.identifyTarget(p.URL); err != nil {
			return err
		}
	}
	if p.Arxiv == "" {
		p.Arxiv = arxivDOIAlias(p.DOI)
	}
	switch {
	case p.Arxiv != "" && !arxivPattern.MatchString(p.Arxiv),
		p.DOI != "" && !doiPattern.MatchString(p.DOI),
		p.InspireID != "" && !inspirePattern.MatchString(p.InspireID),
		p.URL != "" && !paperHTTPURL(p.URL),
		p.PDFURL != "" && !paperHTTPURL(p.PDFURL):
		return errInvalidPaper
	case p.DOI != "" && arxivDOIAlias(p.DOI) != "" && ArxivWorkID(arxivDOIAlias(p.DOI)) != ArxivWorkID(p.Arxiv):
		return fmt.Errorf("%w：arXiv 与 DOI 指向不同论文", errInvalidPaper)
	}
	return nil
}

func (p *paperImport) identifyTarget(value string) error {
	if id := normalizeArxiv(value); arxivPattern.MatchString(id) {
		p.Arxiv = id
		return nil
	}
	if doi := normalizeDOI(value); doiPattern.MatchString(doi) {
		p.DOI = doi
		return nil
	}
	if id := normalizeInspire(value); value != id && inspirePattern.MatchString(id) {
		p.InspireID = id
		return nil
	}
	if paperHTTPURL(value) {
		p.URL = value
		link, _ := url.Parse(value)
		if !strings.HasSuffix(strings.ToLower(link.Path), ".pdf") {
			if match := publisherDOIPath.FindStringSubmatch(link.Path); len(match) > 1 && len(match[1]) <= 512 {
				p.DOI = normalizeDOI(match[1])
			}
		}
		return nil
	}
	return errPaperIdentifier
}
