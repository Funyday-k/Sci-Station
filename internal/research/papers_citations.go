package research

import (
	"net/http"
	"strconv"
	"strings"
)

// These plain-text variants follow the existing desktop formatter. BibTeX
// stays on the shared formatter used by export and the workspace bibliography.
func paperCitation(p Paper, format string) (string, bool) {
	authors := strings.Join(p.Authors, ", ")
	if authors == "" {
		authors = "Unknown"
	}
	year := ""
	if p.Year > 0 {
		year = strconv.Itoa(p.Year)
	}
	url := p.URL
	if url == "" {
		url = p.PDFURL
	}
	locator := url
	switch {
	case p.DOI != "":
		locator = "https://doi.org/" + p.DOI
	case p.Arxiv != "":
		locator = "https://arxiv.org/abs/" + p.Arxiv
	}
	var fields []string
	switch format {
	case "bibtex":
		return paperBibtex(p), true
	case "apa":
		if year == "" {
			year = "n.d."
		}
		fields = []string{authors, "(" + year + ").", p.Title + ".", p.PublicationTitle, locator}
	case "mla", "chicago":
		fields = []string{authors, `"` + p.Title + `."`, p.PublicationTitle, year, locator}
	case "ieee":
		fields = []string{authors, `"` + p.Title + `,"`, p.PublicationTitle, year, locator}
	case "ris":
		output := []string{"TY  - JOUR"}
		add := func(key, value string) {
			if cleaned := strings.Join(strings.Fields(value), " "); cleaned != "" {
				output = append(output, key+"  - "+cleaned)
			}
		}
		add("TI", p.Title)
		for _, author := range p.Authors {
			add("AU", author)
		}
		add("PY", year)
		add("JO", p.PublicationTitle)
		add("DO", p.DOI)
		add("UR", url)
		add("AB", p.Abstract)
		return strings.Join(append(output, "ER  -"), "\n") + "\n", true
	default:
		return "", false
	}
	parts := fields[:0]
	for _, field := range fields {
		if part := strings.TrimSpace(field); part != "" {
			parts = append(parts, part)
		}
	}
	return strings.Join(parts, " "), true
}

func citationHTTP(w http.ResponseWriter, r *http.Request, paper Paper) {
	if r.Method != http.MethodGet {
		paperMethod(w, http.MethodGet)
		return
	}
	format := strings.ToLower(r.URL.Query().Get("format"))
	if format == "" {
		format = "bibtex"
	}
	text, ok := paperCitation(paper, format)
	if !ok {
		paperError(w, errInvalidPaper)
		return
	}
	paperReply(w, http.StatusOK, map[string]string{"format": format, "text": text})
}
