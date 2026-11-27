package research

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"scistation.local/desktop/internal/workspace"
)

const maxPaperPDF int64 = 256 << 20

type paperImport struct {
	PaperMetadata
	ImportCollection *string   `json:"collection_id,omitempty"`
	Identifier       string    `json:"identifier,omitempty"`
	FetchPDF         bool      `json:"fetch_pdf"`
	AllowLinkOnly    bool      `json:"allow_link_only"`
	SkipLookup       bool      `json:"skip_metadata_lookup"`
	PrimaryCategory  string    `json:"-"`
	PublishedAt      time.Time `json:"-"`
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

var errInvalidPaperPDF = fmt.Errorf("%w：请选择有效 PDF", errInvalidPaper)
var errRemotePDF = errors.New("在线 PDF 无法下载")
var errPDFReaderUnavailable = errors.New("当前构建缺少 PDF 阅读支持")

func (s *PaperLibrary) downloadPDF(ctx context.Context, from string) (string, string, error) {
	response, err := fetchPaperURL(ctx, from, "application/pdf")
	if err != nil {
		if ctx.Err() != nil {
			return "", "", ctx.Err()
		}
		return "", "", errRemotePDF
	}
	defer response.Body.Close()
	if raw := response.Header.Get("Content-Type"); raw != "" {
		kind, _, err := mime.ParseMediaType(raw)
		if err != nil || (kind != "application/pdf" && kind != "application/octet-stream" && kind != "application/x-pdf" && kind != "binary/octet-stream") {
			return "", "", fmt.Errorf("%w：远端响应不是 PDF", errInvalidPaper)
		}
	}
	return s.stagePDF(ctx, response.Body)
}

func (s *PaperLibrary) stagePDF(ctx context.Context, reader io.Reader) (temp, digest string, err error) {
	r := bufio.NewReader(reader)
	prefix, err := r.Peek(5)
	if err != nil || string(prefix) != "%PDF-" {
		return "", "", errInvalidPaperPDF
	}
	f, err := workspace.ManagedCreateTemp(filepath.Join(s.dir, "pdf"), ".import-*")
	if err != nil {
		return "", "", err
	}
	defer func() {
		if err != nil {
			workspace.ManagedRemove(f.Name())
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
	if err = ctx.Err(); err != nil {
		return "", "", err
	}
	if err = validatePaperPDF(ctx, f.Name()); err != nil {
		return "", "", err
	}
	return f.Name(), hex.EncodeToString(h.Sum(nil)), nil
}

type arxivCategory struct {
	Term string `xml:"term,attr"`
}

type paperFeed struct {
	XMLName xml.Name `xml:"feed"`
	Entries []struct {
		ID        string    `xml:"id"`
		Title     string    `xml:"title"`
		Summary   string    `xml:"summary"`
		Published time.Time `xml:"published"`
		Authors   []struct {
			Name string `xml:"name"`
		} `xml:"author"`
		DOI        string          `xml:"doi"`
		Primary    arxivCategory   `xml:"http://arxiv.org/schemas/atom primary_category"`
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
		if !arxivPattern.MatchString(id) || strings.TrimSpace(e.Title) == "" {
			continue
		}
		m := paperImport{PaperMetadata: PaperMetadata{
			Title: strings.Join(strings.Fields(e.Title), " "), Abstract: strings.Join(strings.Fields(e.Summary), " "),
			DOI: normalizeDOI(e.DOI), Arxiv: id, URL: "https://arxiv.org/abs/" + id, ItemType: "preprint",
		}}
		m.PrimaryCategory = strings.TrimSpace(e.Primary.Term)
		m.PublishedAt = e.Published
		// arXiv feed tags preserve the primary category first, followed by cross-lists.
		for _, category := range append([]arxivCategory{e.Primary}, e.Categories...) {
			term := strings.TrimSpace(category.Term)
			if term != "" && !paperContains(m.Tags, term) {
				m.Tags = append(m.Tags, term)
				m.Categories = append(m.Categories, term)
			}
		}
		if !e.Published.IsZero() {
			m.Year = e.Published.Year()
		}
		for _, a := range e.Authors {
			m.Authors = append(m.Authors, a.Name)
		}
		m.PDFURL = "https://arxiv.org/pdf/" + id
		for _, link := range e.Links {
			if link.Type == "application/pdf" && normalizeArxiv(link.Href) == id && paperHTTPURL(link.Href) {
				m.PDFURL = link.Href
				break
			}
		}
		out = append(out, m)
	}
	return out
}

var arxivQuerySlot = make(chan struct{}, 1)
var arxivPreviousQuery time.Time // guarded by arxivQuerySlot

func arxivPaperSearch(ctx context.Context, query url.Values) ([]paperImport, error) {
	// arXiv's legacy API allows one connection and one request every three seconds.
	select {
	case arxivQuerySlot <- struct{}{}:
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	defer func() { <-arxivQuerySlot }()
	if delay := time.Until(arxivPreviousQuery.Add(3 * time.Second)); delay > 0 {
		timer := time.NewTimer(delay)
		defer timer.Stop()
		select {
		case <-timer.C:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	arxivPreviousQuery = time.Now()
	res, err := fetchPaperURL(ctx, "https://export.arxiv.org/api/query?"+query.Encode(), "application/atom+xml")
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	var f paperFeed
	if err = xml.NewDecoder(io.LimitReader(res.Body, 3<<20)).Decode(&f); err != nil {
		return nil, err
	}
	for _, entry := range f.Entries {
		if strings.Contains(entry.ID, "/api/errors#") {
			return nil, errors.New("arXiv 拒绝了检索式")
		}
	}
	return f.metadata(), nil
}

// SearchArxiv searches the Atom feed with the caller's arXiv query expression.
func SearchArxiv(ctx context.Context, expr string) ([]PaperMetadata, error) {
	candidates, err := SearchArxivCandidates(ctx, expr, 24)
	if err != nil {
		return nil, err
	}
	out := make([]PaperMetadata, 0, len(candidates))
	for _, item := range candidates {
		out = append(out, item.PaperMetadata)
	}
	return out, nil
}

// SearchArxivCandidates retains the provider's explicit primary category and publication date.
func SearchArxivCandidates(ctx context.Context, expr string, limit int) ([]DiscoveryCandidate, error) {
	expr = strings.TrimSpace(expr)
	if expr == "" || len(expr) > 2048 || limit < 1 || limit > 100 {
		return nil, fmt.Errorf("%w：请输入有效的 arXiv 查询", errInvalidPaper)
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	results, err := arxivPaperSearch(ctx, url.Values{
		"search_query": {expr}, "start": {"0"}, "max_results": {strconv.Itoa(limit)},
		"sortBy": {"submittedDate"}, "sortOrder": {"descending"},
	})
	if err != nil {
		return nil, err
	}
	out := make([]DiscoveryCandidate, 0, len(results))
	for _, item := range results {
		candidate := DiscoveryCandidate{PaperMetadata: item.PaperMetadata, Provider: "arXiv", PrimaryCategory: item.PrimaryCategory}
		candidate.MetadataSource = "arxiv"
		if !item.PublishedAt.IsZero() {
			candidate.PublishedAt = item.PublishedAt.Format(time.RFC3339)
		}
		out = append(out, candidate)
	}
	return out, nil
}

func (s *PaperLibrary) findImport(m PaperMetadata, digest string) (Paper, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	existing, err := s.findImportLocked(Paper{PaperMetadata: m, FileSHA256: digest})
	return clonePaper(existing), err
}

func (s *PaperLibrary) findImportLocked(incoming Paper) (Paper, error) {
	var found Paper
	for _, record := range s.records {
		if !samePaper(incoming, record) {
			continue
		}
		if found.ID != "" {
			return Paper{}, errPaperExists
		}
		found = record
	}
	return found, nil
}

// Hold the record lock before publishing a staged file so an outdated writer
// cannot replace or remove a PDF committed by another instance.
func (s *PaperLibrary) saveImportLocked(p *Paper, tempFile, digest string, collectionExplicit bool) (resultErr error) {
	lock, err := s.lockRecords()
	if err != nil {
		return err
	}
	defer lock.Close()
	if _, err := s.currentRecord(p.ID); err != nil {
		return err
	}
	current, exists := s.records[p.ID]
	if !exists {
		organization, _, err := s.readOrganization()
		if err != nil {
			return err
		}
		if !collectionExplicit && organization.Library != nil {
			p.CollectionID = organization.Library.DefaultCollection
		}
		if p.CollectionID != "" {
			if _, exists := organization.Collections[p.CollectionID]; !exists {
				return fmt.Errorf("%w：文献集合不存在", errInvalidPaper)
			}
		}
		finish, err := s.appendLibraryBibliography(*p)
		if err != nil {
			return err
		}
		if finish != nil {
			// Run compensation before releasing the paper-record lock.
			defer func() {
				if rollbackErr := finish(resultErr == nil); rollbackErr != nil {
					resultErr = errors.Join(resultErr, rollbackErr)
				}
			}()
		}
	}
	if tempFile == "" || (current.HasPDF && p.HasPDF) {
		return s.saveWithRecordLock(*p)
	}
	dest := filepath.Join(s.dir, "pdf", p.ID+".pdf")
	if err := workspace.ManagedRename(tempFile, dest); err != nil {
		return err
	}
	p.HasPDF = true
	p.FileSHA256 = digest
	if err := s.saveWithRecordLock(*p); err != nil {
		workspace.ManagedRemove(dest)
		return err
	}
	return nil
}
