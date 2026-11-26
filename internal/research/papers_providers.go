package research

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net/url"
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const providerResponseLimit = 3 << 20

var providerMarkup = regexp.MustCompile(`<[^>]{1,200}>`)

func cleanProviderAbstract(value string) string {
	return strings.Join(strings.Fields(html.UnescapeString(providerMarkup.ReplaceAllString(value, " "))), " ")
}

func decodeProviderRecord(ctx context.Context, address string, target any) error {
	response, err := fetchPaperURL(ctx, address, "application/json")
	if err != nil {
		return err
	}
	defer response.Body.Close()
	dec := json.NewDecoder(io.LimitReader(response.Body, providerResponseLimit))
	if err = dec.Decode(target); err != nil {
		return err
	}
	var trailing any
	if dec.Decode(&trailing) != io.EOF {
		return errors.New("unexpected data after provider record")
	}
	return nil
}

type crossrefDate struct {
	Parts [][]int `json:"date-parts"`
}

type crossrefRecord struct {
	Message struct {
		ContainerTitle []string                               `json:"container-title"`
		Publisher      string                                 `json:"publisher"`
		Volume         string                                 `json:"volume"`
		Issue          string                                 `json:"issue"`
		Pages          string                                 `json:"page"`
		ItemType       string                                 `json:"type"`
		Categories     []string                               `json:"subject"`
		Title          []string                               `json:"title"`
		Author         []struct{ Given, Family, Name string } `json:"author"`
		Print          crossrefDate                           `json:"published-print"`
		Online         crossrefDate                           `json:"published-online"`
		Issued         crossrefDate                           `json:"issued"`
		Created        crossrefDate                           `json:"created"`
		DOI            string                                 `json:"DOI"`
		Abstract       string                                 `json:"abstract"`
		Links          []struct {
			URL  string `json:"URL"`
			Type string `json:"content-type"`
		} `json:"link"`
		References []struct {
			DOI string `json:"DOI"`
		} `json:"reference"`
	} `json:"message"`
}

func lookupCrossref(ctx context.Context, doi string) (PaperMetadata, error) {
	var record crossrefRecord
	address := "https://api.crossref.org/works/" + url.PathEscape(doi)
	if err := decodeProviderRecord(ctx, address, &record); err != nil {
		return PaperMetadata{}, err
	}
	m := record.Message
	resolved := normalizeDOI(m.DOI)
	if (resolved != "" && resolved != doi) || len(m.Title) == 0 || strings.TrimSpace(m.Title[0]) == "" {
		return PaperMetadata{}, errors.New("Crossref record did not identify the requested paper")
	}
	result := PaperMetadata{
		Title: m.Title[0], DOI: doi, Abstract: cleanProviderAbstract(m.Abstract),
		PublicationTitle: firstPaperValue(m.ContainerTitle...), Publisher: m.Publisher,
		Volume: m.Volume, Issue: m.Issue, Pages: m.Pages, ItemType: m.ItemType, Categories: m.Categories,
	}
	for _, a := range m.Author {
		name := strings.TrimSpace(a.Given + " " + a.Family)
		if name == "" {
			name = strings.TrimSpace(a.Name)
		}
		if name != "" {
			result.Authors = append(result.Authors, name)
		}
	}
	for _, date := range []crossrefDate{m.Print, m.Online, m.Issued, m.Created} {
		if len(date.Parts) > 0 && len(date.Parts[0]) > 0 {
			result.Year = date.Parts[0][0]
			break
		}
	}
	for _, l := range m.Links {
		if strings.EqualFold(l.Type, "application/pdf") && paperHTTPURL(l.URL) {
			result.PDFURL = l.URL
			break
		}
	}
	for _, r := range m.References {
		if id := normalizeDOI(r.DOI); doiPattern.MatchString(id) && len(result.References) < 4096 {
			result.References = append(result.References, id)
		}
	}
	return result, nil
}

type inspireRecord struct {
	Metadata struct {
		ID            int `json:"control_number"`
		CitationCount int `json:"citation_count"`
		References    []struct {
			Record struct {
				Ref string `json:"$ref"`
			} `json:"record"`
		} `json:"references"`
		Titles  []struct{ Title string } `json:"titles"`
		Authors []struct {
			Name string `json:"full_name"`
		} `json:"authors"`
		Abstracts []struct{ Value string } `json:"abstracts"`
		DOIs      []struct{ Value string } `json:"dois"`
		ArxivIDs  []struct {
			Value      string
			Categories []string
		} `json:"arxiv_eprints"`
		Categories   []struct{ Term string } `json:"inspire_categories"`
		Documents    []struct{ URL string }  `json:"documents"`
		EarliestDate string                  `json:"earliest_date"`
		Publication  []struct {
			Year    int
			Journal string          `json:"journal_title"`
			Volume  json.RawMessage `json:"journal_volume"`
			Issue   json.RawMessage `json:"journal_issue"`
			Article json.RawMessage `json:"artid"`
			Start   json.RawMessage `json:"page_start"`
			End     json.RawMessage `json:"page_end"`
		} `json:"publication_info"`
	} `json:"metadata"`
}

func lookupInspire(ctx context.Context, id string) (PaperMetadata, error) {
	var record inspireRecord
	if err := decodeProviderRecord(ctx, "https://inspirehep.net/api/literature/"+id, &record); err != nil {
		return PaperMetadata{}, err
	}
	m := record.Metadata
	if (m.ID != 0 && strconv.Itoa(m.ID) != id) || len(m.Titles) == 0 || strings.TrimSpace(m.Titles[0].Title) == "" {
		return PaperMetadata{}, errors.New("INSPIRE record did not identify the requested paper")
	}
	result := PaperMetadata{Title: m.Titles[0].Title, InspireID: id, ItemType: "preprint"}
	for _, author := range m.Authors {
		result.Authors = append(result.Authors, author.Name)
	}
	if len(m.Abstracts) > 0 {
		result.Abstract = cleanProviderAbstract(m.Abstracts[0].Value)
	}
	for _, publication := range m.Publication {
		if result.Year == 0 {
			result.Year = publication.Year
		}
		if strings.TrimSpace(publication.Journal) == "" {
			continue
		}
		if publication.Year > 0 {
			result.Year = publication.Year
		}
		result.PublicationTitle = publication.Journal
		result.ItemType = "journal-article"
		result.Volume = providerLabel(publication.Volume)
		result.Issue = providerLabel(publication.Issue)
		result.Pages = providerLabel(publication.Article)
		if result.Pages == "" {
			start, end := providerLabel(publication.Start), providerLabel(publication.End)
			result.Pages = firstPaperValue(start, end)
			if start != "" && end != "" && start != end {
				result.Pages = start + "-" + end
			}
		}
		break
	}
	if result.Year == 0 && len(m.EarliestDate) >= 4 {
		result.Year, _ = strconv.Atoi(m.EarliestDate[:4])
	}
	for _, doi := range m.DOIs {
		if normalized := normalizeDOI(doi.Value); doiPattern.MatchString(normalized) {
			result.DOI = normalized
			break
		}
	}
	for _, eprint := range m.ArxivIDs {
		if normalized := normalizeArxiv(eprint.Value); arxivPattern.MatchString(normalized) {
			result.Arxiv = normalized
			result.Categories = eprint.Categories
			result.PDFURL = "https://arxiv.org/pdf/" + normalized
			break
		}
	}
	for _, category := range m.Categories {
		result.Categories = append(result.Categories, category.Term)
	}
	if result.PDFURL == "" {
		for _, doc := range m.Documents {
			if paperHTTPURL(doc.URL) {
				result.PDFURL = doc.URL
				break
			}
		}
	}
	return result, nil
}

func providerLabel(raw json.RawMessage) string {
	var label string
	if err := json.Unmarshal(raw, &label); err == nil {
		return strings.TrimSpace(label)
	}
	var number json.Number
	if err := json.Unmarshal(raw, &number); err == nil {
		return number.String()
	}
	return ""
}

func lookupArxiv(ctx context.Context, id string) (PaperMetadata, error) {
	results, err := arxivPaperSearch(ctx, url.Values{"id_list": {id}, "max_results": {"1"}})
	if err != nil {
		return PaperMetadata{}, err
	}
	for _, result := range results {
		if ArxivWorkID(id) == ArxivWorkID(result.Arxiv) && (id == ArxivWorkID(id) || id == result.Arxiv) && result.Title != "" {
			result.DOI = normalizeDOI(result.DOI)
			if !doiPattern.MatchString(result.DOI) {
				result.DOI = ""
			}
			return result.PaperMetadata, nil
		}
	}
	return PaperMetadata{}, errors.New("arXiv returned no matching paper")
}

func (p *paperImport) lookupTarget() (string, string, func(context.Context, string) (PaperMetadata, error)) {
	switch {
	case p.InspireID != "":
		return "INSPIRE", p.InspireID, lookupInspire
	case p.Arxiv != "":
		return "arXiv", p.Arxiv, lookupArxiv
	case p.DOI != "":
		return "Crossref", p.DOI, lookupCrossref
	default:
		return "", "", nil
	}
}

// Build a draft from one exact source. A provider outage leaves the URL and
// identifiers available for an explicit link-only import.
func enrichPaper(ctx context.Context, p *paperImport) (string, error) {
	if err := p.prepare(); err != nil {
		return "", err
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	provider, id, lookup := p.lookupTarget()
	var warning string
	if lookup != nil && !p.SkipLookup {
		lookupCtx, cancel := context.WithTimeout(ctx, 7*time.Second)
		learned, err := lookup(lookupCtx, id)
		cancel()
		if ctx.Err() != nil {
			return "", ctx.Err()
		}
		if err != nil {
			warning = fmt.Sprintf("%s 暂时无法提供该文献的元数据。", provider)
		} else {
			p.mergeProviderMetadata(learned)
			p.MetadataSource = provider
		}
	}
	switch {
	case p.InspireID != "":
		p.URL = firstPaperValue(p.URL, "https://inspirehep.net/literature/"+p.InspireID)
		p.Title = firstPaperValue(p.Title, "INSPIRE "+p.InspireID)
	case p.Arxiv != "":
		p.URL = firstPaperValue(p.URL, "https://arxiv.org/abs/"+p.Arxiv)
		p.Title = firstPaperValue(p.Title, "arXiv "+p.Arxiv)
	case p.DOI != "":
		doiPath := (&url.URL{Path: "/" + p.DOI}).EscapedPath()
		p.URL = firstPaperValue(p.URL, "https://doi.org"+doiPath)
		p.Title = firstPaperValue(p.Title, p.DOI)
	}
	if p.Arxiv != "" {
		p.PDFURL = firstPaperValue(p.PDFURL, "https://arxiv.org/pdf/"+p.Arxiv)
	}
	if p.PDFURL == "" {
		if u, err := url.Parse(p.URL); err == nil && strings.HasSuffix(strings.ToLower(u.Path), ".pdf") {
			p.PDFURL = p.URL
		}
	}
	p.Title = firstPaperValue(p.Title, paperLinkTitle(firstPaperValue(p.URL, p.PDFURL)))
	return warning, nil
}

func paperLinkTitle(source string) string {
	link, err := url.Parse(source)
	if err != nil {
		return ""
	}
	filename := path.Base(link.Path)
	if strings.EqualFold(path.Ext(filename), ".pdf") {
		if title := strings.Join(strings.Fields(strings.TrimSuffix(filename, path.Ext(filename))), " "); title != "" && len(title) <= 1000 {
			return title
		}
	}
	return link.Hostname()
}

func firstPaperValue(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func (p *paperImport) mergeProviderMetadata(m PaperMetadata) {
	p.Title = firstPaperValue(p.Title, m.Title)
	p.Abstract = firstPaperValue(p.Abstract, m.Abstract)
	p.URL = firstPaperValue(p.URL, m.URL)
	p.PDFURL = firstPaperValue(p.PDFURL, m.PDFURL)
	p.DOI = firstPaperValue(p.DOI, m.DOI)
	// The provider may resolve a version for a bare identifier. Keep the exact
	// requested version when the input already specifies one.
	if p.Arxiv == "" || (p.Arxiv == ArxivWorkID(p.Arxiv) && ArxivWorkID(m.Arxiv) == p.Arxiv) {
		p.Arxiv = m.Arxiv
	}
	if p.Year == 0 {
		p.Year = m.Year
	}
	if len(p.Authors) == 0 {
		p.Authors = m.Authors
	}
	if len(p.References) == 0 {
		p.References = m.References
	}
	mergeProviderBibliography(&p.PaperMetadata, m)
}

// Keep imported bibliography alongside researcher-supplied tags and retain
// the researcher's values when a provider is queried again.
func mergeProviderBibliography(p *PaperMetadata, learned PaperMetadata) bool {
	changed := false
	for _, field := range []struct {
		destination *string
		source      string
	}{
		{&p.PublicationTitle, learned.PublicationTitle}, {&p.Publisher, learned.Publisher},
		{&p.Volume, learned.Volume}, {&p.Issue, learned.Issue}, {&p.Pages, learned.Pages},
		{&p.ItemType, learned.ItemType},
	} {
		if *field.destination == "" && field.source != "" {
			*field.destination = field.source
			changed = true
		}
	}
	if len(p.Categories) == 0 && len(learned.Categories) > 0 {
		p.Categories = learned.Categories
		changed = true
	}
	return changed
}

// A successful retry can fill the fields of an offline entry. Keep any title
// or metadata the researcher added in the meantime.
func recoverPaperMetadata(p *Paper, learned PaperMetadata) bool {
	if (p.MetadataSource != "" && p.MetadataSource != "PDF") || learned.MetadataSource == "" || learned.MetadataSource == "PDF" {
		return false
	}
	changed := mergeProviderBibliography(&p.PaperMetadata, learned)
	switch p.Title {
	case p.DOI, "arXiv " + p.Arxiv, "INSPIRE " + p.InspireID, p.URL, paperLinkTitle(p.URL):
		if learned.Title != "" && p.Title != learned.Title {
			p.Title = learned.Title
			changed = true
		}
	}
	if p.Year == 0 && learned.Year != 0 {
		p.Year = learned.Year
		changed = true
	}
	if p.Abstract == "" && learned.Abstract != "" {
		p.Abstract = learned.Abstract
		changed = true
	}
	if len(p.Authors) == 0 && len(learned.Authors) > 0 {
		p.Authors = learned.Authors
		changed = true
	}
	if len(p.References) == 0 && len(learned.References) > 0 {
		p.References = learned.References
		changed = true
	}
	if changed {
		p.MetadataSource = learned.MetadataSource
	}
	return changed
}
