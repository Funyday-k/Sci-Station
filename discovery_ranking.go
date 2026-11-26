package main

import (
	"math"
	"regexp"
	"slices"
	"strings"
	"time"

	"scistation.local/desktop/internal/research"
)

var discoveryWord = regexp.MustCompile(`[\p{L}\p{N}]{3,}`)
var discoveryQuerySyntax = regexp.MustCompile(`(?i)\b(?:all|ti|abs|cat|au|id|jr|co|rn):|\b(?:AND|OR|NOT)\b`)

type discoveryTerms map[string]struct{}

func discoveryTokens(text string) discoveryTerms {
	out := discoveryTerms{}
	for _, token := range discoveryWord.FindAllString(strings.ToLower(text), -1) {
		out[token] = struct{}{}
	}
	return out
}

func discoveryPaperTerms(p research.PaperMetadata) discoveryTerms {
	return discoveryTokens(p.Title + " " + p.Abstract + " " + strings.Join(p.Tags, " ") + " " + strings.Join(p.Categories, " "))
}

func discoverySimilarity(a, b discoveryTerms) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	if len(a) > len(b) {
		a, b = b, a
	}
	n := 0
	for term := range a {
		if _, ok := b[term]; ok {
			n++
		}
	}
	return float64(n) / math.Sqrt(float64(len(a))*float64(len(b)))
}

func discoveryNearest(words discoveryTerms, corpus []discoveryTerms) float64 {
	var best float64
	for _, terms := range corpus {
		best = max(best, discoverySimilarity(words, terms))
	}
	return best
}

func discoveryCategoryMatch(p research.DiscoveryCandidate, selected []string, crossList bool) bool {
	if len(selected) == 0 {
		return true
	}
	match := func(category string) bool { return slices.Contains(selected, strings.ToLower(category)) }
	if match(p.PrimaryCategory) {
		return true
	}
	return crossList && (slices.ContainsFunc(p.Categories, match) || slices.ContainsFunc(p.Tags, match))
}

type discoveryRanked struct {
	paper                 research.DiscoveryCandidate
	terms                 discoveryTerms
	relevance, redundancy float64
}

func rankDiscovery(items []research.DiscoveryCandidate, sources research.DiscoveryContext, run discoveryRun, state discoveryState, now time.Time) []research.DiscoveryCandidate {
	var core, refs, liked, disliked []discoveryTerms
	authors, inLibrary := map[string]bool{}, map[string]bool{}
	for _, p := range sources.Library {
		inLibrary[(research.DiscoveryCandidate{PaperMetadata: p.PaperMetadata, PaperID: p.ID}).Key()] = true
		if p.Rating >= 4 || p.Status == "read" || slices.Contains(p.CoreProjectIDs, sources.Project.ID) {
			core = append(core, discoveryPaperTerms(p.PaperMetadata))
			for _, author := range p.Authors {
				authors[strings.ToLower(strings.Join(strings.Fields(author), " "))] = true
			}
		}
	}
	for _, p := range sources.Refs {
		refs = append(refs, discoveryPaperTerms(p.PaperMetadata))
	}
	for key, item := range state.FeedbackPapers {
		switch state.Feedback[key] {
		case "saved", "liked", "opened":
			liked = append(liked, discoveryPaperTerms(item.PaperMetadata))
		case "hidden", "disliked":
			disliked = append(disliked, discoveryPaperTerms(item.PaperMetadata))
		}
	}
	project := discoveryTokens(sources.Project.Name + " " + sources.Project.Description)
	query := discoveryTokens(discoveryQuerySyntax.ReplaceAllString(run.Query, " "))
	seen := map[string]bool{}
	rows := make([]discoveryRanked, 0, len(items))
	for _, candidate := range items {
		key := candidate.Key()
		if seen[key] || !discoveryCategoryMatch(candidate, run.Categories, run.CrossList) {
			continue
		}
		seen[key] = true
		terms := discoveryPaperTerms(candidate.PaperMetadata)
		keyword := discoverySimilarity(terms, query)
		seed := discoveryNearest(terms, refs)
		library := discoveryNearest(terms, core)
		context := discoverySimilarity(terms, project)
		feedback := discoveryNearest(terms, liked) - 0.8*discoveryNearest(terms, disliked)
		published, err := time.Parse(time.RFC3339, candidate.PublishedAt)
		var freshness float64
		if err == nil {
			freshness = math.Exp(-max(0, now.Sub(published).Hours()) / (24 * 30))
		}
		citation := min(1, float64(len(candidate.GraphEvidence))/2)
		score := 0.24*keyword + 0.22*seed + 0.15*library + 0.13*context + 0.11*freshness + 0.08*feedback + 0.13*citation
		if (run.Source == "arxiv" || run.Source == "daily") && inLibrary[key] {
			score -= 0.20
		}
		if slices.ContainsFunc(candidate.Authors, func(name string) bool { return authors[strings.ToLower(strings.Join(strings.Fields(name), " "))] }) {
			score += 0.06
			candidate.Reasons = append(candidate.Reasons, "与阅读过或项目核心论文有共同作者")
		}
		if seed >= 0.1 {
			candidate.Reasons = append(candidate.Reasons, "与所选参考论文相关")
		}
		if keyword >= 0.1 {
			candidate.Reasons = append(candidate.Reasons, "与检索关键词相关")
		}
		if max(library, context) >= 0.1 {
			candidate.Reasons = append(candidate.Reasons, "与当前项目或文献库相关")
		}
		if feedback >= 0.1 {
			candidate.Reasons = append(candidate.Reasons, "与收藏或认可的论文相关")
		}
		rows = append(rows, discoveryRanked{paper: candidate, terms: terms, relevance: score})
	}

	// Maximal marginal relevance (Swift defaults to lambda=0.75).
	ordered := make([]research.DiscoveryCandidate, 0, len(rows))
	for len(rows) != 0 && len(ordered) < run.TopK {
		best := 0
		score := func(row discoveryRanked) float64 { return 0.75*row.relevance - 0.25*row.redundancy }
		for i := 1; i < len(rows); i++ {
			if score(rows[i]) > score(rows[best]) {
				best = i
			}
		}
		pick := rows[best]
		rows = slices.Delete(rows, best, best+1)
		ordered = append(ordered, pick.paper)
		for i := range rows {
			rows[i].redundancy = max(rows[i].redundancy, discoverySimilarity(rows[i].terms, pick.terms))
		}
	}
	return ordered
}
