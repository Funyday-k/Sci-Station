package research

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const maxPaperPDF int64 = 256 << 20

type paperImport struct {
	PaperMetadata
	FetchPDF bool   `json:"fetch_pdf"`
	PDFURL   string `json:"pdf_url"`
}

func paperHTTPURL(raw string) bool {
	u, err := url.Parse(raw)
	return err == nil && (u.Scheme == "https" || u.Scheme == "http") && u.Hostname() != "" && u.User == nil
}

var excludedPaperNetworks = []netip.Prefix{
	netip.MustParsePrefix("0.0.0.0/8"), netip.MustParsePrefix("100.64.0.0/10"), netip.MustParsePrefix("192.0.0.0/24"), netip.MustParsePrefix("192.0.2.0/24"), netip.MustParsePrefix("198.18.0.0/15"), netip.MustParsePrefix("198.51.100.0/24"), netip.MustParsePrefix("203.0.113.0/24"), netip.MustParsePrefix("240.0.0.0/4"), netip.MustParsePrefix("2001:db8::/32"), netip.MustParsePrefix("2002::/16"), netip.MustParsePrefix("64:ff9b::/96"), netip.MustParsePrefix("64:ff9b:1::/48"), netip.MustParsePrefix("2001::/32"),
}

func safePaperAddress(ip netip.Addr) bool {
	ip = ip.Unmap()
	if !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
		return false
	}
	for _, reserved := range excludedPaperNetworks {
		if reserved.Contains(ip) {
			return false
		}
	}
	return true
}
func validPaperFetchURL(u *url.URL) bool {
	p := u.Port()
	return (u.Scheme == "https" || u.Scheme == "http") && u.User == nil && u.Hostname() != "" && (p == "" || p == "80" || p == "443")
}

var paperHTTPClient = &http.Client{
	Timeout: 50 * time.Second,
	Transport: &http.Transport{
		ForceAttemptHTTP2: true, MaxIdleConns: 12, IdleConnTimeout: 30 * time.Second, ResponseHeaderTimeout: 8 * time.Second, TLSHandshakeTimeout: 7 * time.Second,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			host, port, err := net.SplitHostPort(addr)
			if err != nil {
				return nil, err
			}
			addrs, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
			if err != nil {
				return nil, err
			}
			d := &net.Dialer{Timeout: 5 * time.Second}
			for _, ip := range addrs {
				if !safePaperAddress(ip) {
					continue
				}
				conn, e := d.DialContext(ctx, network, net.JoinHostPort(ip.String(), port))
				if e == nil {
					return conn, nil
				}
				err = e
			}
			if err != nil {
				return nil, err
			}
			return nil, errors.New("只允许从公共站点下载")
		},
	},
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) > 4 || !validPaperFetchURL(req.URL) {
			return errors.New("不支持此下载跳转")
		}
		return nil
	},
}

func fetchPaperURL(ctx context.Context, raw, accept string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, raw, nil)
	if err != nil || !validPaperFetchURL(req.URL) {
		return nil, fmt.Errorf("%w：下载地址无效", errInvalidPaper)
	}
	req.Header.Set("User-Agent", "Sci-Station/1 (desktop literature workspace)")
	req.Header.Set("Accept", accept)
	res, err := paperHTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	if res.StatusCode != http.StatusOK {
		res.Body.Close()
		return nil, fmt.Errorf("文献服务返回 HTTP %d", res.StatusCode)
	}
	return res, nil
}
func (s *PaperLibrary) stagePDF(reader io.Reader) (temp, digest string, err error) {
	r := bufio.NewReader(reader)
	prefix, err := r.Peek(5)
	if err != nil || string(prefix) != "%PDF-" {
		return "", "", fmt.Errorf("%w：请选择有效 PDF", errInvalidPaper)
	}
	f, err := os.CreateTemp(filepath.Join(s.dir, "pdf"), ".import-*")
	if err != nil {
		return "", "", err
	}
	defer func() {
		if err != nil {
			os.Remove(f.Name())
		}
	}()
	h := sha256.New()
	n, err := io.Copy(io.MultiWriter(f, h), io.LimitReader(r, maxPaperPDF+1))
	if err == nil && n > maxPaperPDF {
		err = fmt.Errorf("%w：单篇 PDF 超过 256 MiB", errInvalidPaper)
	}
	if err == nil {
		err = f.Sync()
	}
	e := f.Close()
	if err == nil {
		err = e
	}
	if err != nil {
		return "", "", err
	}
	return f.Name(), hex.EncodeToString(h.Sum(nil)), nil
}

type paperCrossref struct {
	Message struct {
		Title  []string                               `json:"title"`
		Author []struct{ Given, Family, Name string } `json:"author"`
		Issued struct {
			Parts [][]int `json:"date-parts"`
		} `json:"issued"`
		DOI      string `json:"DOI"`
		URL      string `json:"URL"`
		Abstract string `json:"abstract"`
		Links    []struct {
			URL  string `json:"URL"`
			Type string `json:"content-type"`
		} `json:"link"`
		References []struct {
			DOI string `json:"DOI"`
		} `json:"reference"`
	} `json:"message"`
}
type arxivCategory struct {
	Term string `xml:"term,attr"`
}

type paperFeed struct {
	Entries []struct {
		ID        string    `xml:"id"`
		Title     string    `xml:"title"`
		Summary   string    `xml:"summary"`
		Published time.Time `xml:"published"`
		Authors   []struct {
			Name string `xml:"name"`
		} `xml:"author"`
		DOI        string          `xml:"doi"`
		Primary    arxivCategory   `xml:"primary_category"`
		Categories []arxivCategory `xml:"category"`
		Links      []struct {
			Href string `xml:"href,attr"`
			Type string `xml:"type,attr"`
		} `xml:"link"`
	} `xml:"entry"`
}

func (f paperFeed) metadata() []paperImport {
	out := []paperImport{}
	for _, e := range f.Entries {
		id := normalizeArxiv(e.ID)
		if !arxivPattern.MatchString(id) {
			continue
		}
		m := paperImport{PaperMetadata: PaperMetadata{Title: strings.Join(strings.Fields(e.Title), " "), Abstract: strings.Join(strings.Fields(e.Summary), " "), DOI: e.DOI, Arxiv: id, URL: "https://arxiv.org/abs/" + id}}
		// arXiv feed tags preserve the primary category first, followed by cross-lists.
		for _, category := range append([]arxivCategory{e.Primary}, e.Categories...) {
			term := strings.TrimSpace(category.Term)
			if term != "" && !paperContains(m.Tags, term) {
				m.Tags = append(m.Tags, term)
			}
		}
		if !e.Published.IsZero() {
			m.Year = e.Published.Year()
		}
		for _, a := range e.Authors {
			m.Authors = append(m.Authors, a.Name)
		}
		m.PDFURL = "https://arxiv.org/pdf/" + id
		out = append(out, m)
	}
	return out
}
func arxivPaperSearch(ctx context.Context, query url.Values) ([]paperImport, error) {
	res, err := fetchPaperURL(ctx, "https://export.arxiv.org/api/query?"+query.Encode(), "application/atom+xml")
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	var f paperFeed
	if err = xml.NewDecoder(io.LimitReader(res.Body, 3<<20)).Decode(&f); err != nil {
		return nil, err
	}
	return f.metadata(), nil
}

var providerMarkup = regexp.MustCompile(`<[^>]{1,200}>`)

func enrichPaper(ctx context.Context, p *paperImport) {
	p.DOI = normalizeDOI(p.DOI)
	p.Arxiv = normalizeArxiv(p.Arxiv)
	if u, e := url.Parse(p.URL); e == nil {
		host := strings.ToLower(u.Hostname())
		if host == "arxiv.org" || host == "www.arxiv.org" {
			for _, prefix := range []string{"/abs/", "/pdf/"} {
				if strings.HasPrefix(u.Path, prefix) && p.Arxiv == "" {
					p.Arxiv = strings.TrimSuffix(strings.TrimPrefix(u.Path, prefix), ".pdf")
				}
			}
		}
		if host == "doi.org" && p.DOI == "" {
			p.DOI = strings.TrimPrefix(u.Path, "/")
		}
	}
	ctx, cancel := context.WithTimeout(ctx, 7*time.Second)
	defer cancel()
	learned := paperImport{}
	if p.Arxiv != "" && arxivPattern.MatchString(p.Arxiv) {
		learned.PDFURL = "https://arxiv.org/pdf/" + p.Arxiv
		learned.URL = "https://arxiv.org/abs/" + p.Arxiv
		if feed, err := arxivPaperSearch(ctx, url.Values{"id_list": {p.Arxiv}, "max_results": {"1"}}); err == nil && len(feed) > 0 {
			learned = feed[0]
		}
	} else if p.DOI != "" && doiPattern.MatchString(p.DOI) {
		learned.URL = "https://doi.org/" + p.DOI
		res, err := fetchPaperURL(ctx, "https://api.crossref.org/works/"+url.PathEscape(p.DOI), "application/json")
		if err == nil {
			defer res.Body.Close()
			var record paperCrossref
			if json.NewDecoder(io.LimitReader(res.Body, 3<<20)).Decode(&record) == nil {
				m := record.Message
				if len(m.Title) > 0 {
					learned.Title = m.Title[0]
				}
				for _, a := range m.Author {
					name := strings.TrimSpace(a.Given + " " + a.Family)
					if name == "" {
						name = a.Name
					}
					if name != "" {
						learned.Authors = append(learned.Authors, name)
					}
				}
				if len(m.Issued.Parts) > 0 && len(m.Issued.Parts[0]) > 0 {
					learned.Year = m.Issued.Parts[0][0]
				}
				learned.Abstract = providerMarkup.ReplaceAllString(m.Abstract, "")
				for _, l := range m.Links {
					if l.Type == "application/pdf" {
						learned.PDFURL = l.URL
						break
					}
				}
				for _, r := range m.References {
					if r.DOI != "" && len(learned.References) < 4096 {
						learned.References = append(learned.References, r.DOI)
					}
				}
			}
		}
	}
	if p.Title == "" {
		p.Title = learned.Title
	}
	if len(p.Authors) == 0 {
		p.Authors = learned.Authors
	}
	if p.Abstract == "" {
		p.Abstract = learned.Abstract
	}
	if p.Year == 0 {
		p.Year = learned.Year
	}
	if p.URL == "" {
		p.URL = learned.URL
	}
	if p.DOI == "" {
		p.DOI = learned.DOI
	}
	if p.PDFURL == "" {
		p.PDFURL = learned.PDFURL
	}
	if len(p.References) == 0 {
		p.References = learned.References
	}
	if p.Title == "" {
		switch {
		case p.Arxiv != "":
			p.Title = "arXiv " + p.Arxiv
		case p.DOI != "":
			p.Title = p.DOI
		default:
			p.Title = p.URL
		}
	}
}

// SearchArxiv searches the Atom feed with the caller's arXiv query expression.
func SearchArxiv(ctx context.Context, expr string) ([]PaperMetadata, error) {
	expr = strings.TrimSpace(expr)
	if expr == "" || len(expr) > 2048 {
		return nil, fmt.Errorf("%w：请输入有效的 arXiv 查询", errInvalidPaper)
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	results, err := arxivPaperSearch(ctx, url.Values{
		"search_query": {expr}, "start": {"0"}, "max_results": {"24"},
		"sortBy": {"submittedDate"}, "sortOrder": {"descending"},
	})
	if err != nil {
		return nil, err
	}
	out := make([]PaperMetadata, 0, len(results))
	for _, item := range results {
		out = append(out, item.PaperMetadata)
	}
	return out, nil
}
