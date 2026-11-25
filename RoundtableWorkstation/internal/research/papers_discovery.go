package research

import (
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

func paperKeyWord(text string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return r
		}
		return -1
	}, text)
}
func defaultPaperKey(p Paper, records map[string]Paper) string {
	var stem string
	if len(p.Authors) > 0 {
		words := strings.Fields(p.Authors[0])
		if len(words) > 0 {
			stem = words[len(words)-1]
		}
	}
	stem = paperKeyWord(stem)
	if p.Year > 0 {
		stem += strconv.Itoa(p.Year)
	}
	if parts := strings.Fields(p.Title); len(parts) > 0 {
		stem += paperKeyWord(parts[0])
	}
	rs := []rune(stem)
	if len(rs) > 40 {
		stem = string(rs[:40])
	}
	if stem == "" {
		stem = "paper" + p.ID[:6]
	}
	keys := map[string]bool{}
	for _, item := range records {
		if item.ID != p.ID {
			keys[strings.ToLower(item.Citekey)] = true
		}
	}
	key := stem
	for i := 2; keys[strings.ToLower(key)]; i++ {
		key = fmt.Sprintf("%s%d", stem, i)
	}
	return key
}
func bibField(value string) string {
	return strings.NewReplacer("\\", `\textbackslash{}`, "{", `\{`, "}", `\}`, "&", `\&`, "%", `\%`, "#", `\#`, "_", `\_`).Replace(strings.Join(strings.Fields(value), " "))
}
func paperBibtex(p Paper) string {
	var fields []string
	add := func(k, v string) {
		if v != "" {
			fields = append(fields, "  "+k+" = {"+bibField(v)+"}")
		}
	}
	add("title", p.Title)
	add("author", strings.Join(p.Authors, " and "))
	if p.Year > 0 {
		add("year", strconv.Itoa(p.Year))
	}
	add("doi", p.DOI)
	add("url", p.URL)
	if p.Arxiv != "" {
		add("eprint", p.Arxiv)
		add("archivePrefix", "arXiv")
	}
	return "@misc{" + p.Citekey + ",\n" + strings.Join(fields, ",\n") + "\n}\n"
}
func sendBibtex(w http.ResponseWriter, papers []Paper) {
	sort.Slice(papers, func(i, j int) bool { return strings.ToLower(papers[i].Citekey) < strings.ToLower(papers[j].Citekey) })
	w.Header().Set("Content-Type", "application/x-bibtex; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="references.bib"`)
	for i, p := range papers {
		if i > 0 {
			fmt.Fprintln(w)
		}
		fmt.Fprint(w, paperBibtex(p))
	}
}

func rankPapers(papers []Paper, project string) []Paper {
	tagWeights := map[string]int{}
	for _, p := range papers {
		if project != "" && !paperContains(p.ProjectIDs, project) {
			continue
		}
		w := 0
		if p.Status == "read" {
			w++
		}
		if p.Rating >= 4 {
			w += 2
		}
		if paperContains(p.CoreProjectIDs, project) {
			w += 2
		}
		for _, tag := range p.Tags {
			tagWeights[strings.ToLower(tag)] += w
		}
	}
	score := func(p Paper) int {
		n := p.Priority * 3
		if p.Status == "reading" {
			n += 5
		}
		if project != "" && paperContains(p.ProjectIDs, project) {
			n += 3
		}
		for _, t := range p.Tags {
			n += tagWeights[strings.ToLower(t)]
		}
		return n
	}
	out := make([]Paper, 0, len(papers))
	for _, p := range papers {
		if p.Status != "read" {
			out = append(out, p)
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return score(out[i]) > score(out[j]) })
	return out
}
