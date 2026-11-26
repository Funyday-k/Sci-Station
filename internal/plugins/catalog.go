package plugins

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	MaxCatalogBytes   = 1 << 20
	MaxCatalogEntries = 256
	catalogTimeout    = 10 * time.Second
)

// Catalog is the static index distributed by a plugin author.
type Catalog struct {
	SchemaVersion int            `json:"schema_version"`
	Name          string         `json:"name"`
	Plugins       []CatalogEntry `json:"plugins"`
}

type CatalogEntry struct {
	ID           string   `json:"id"`
	Version      string   `json:"version"`
	Name         string   `json:"name"`
	Author       string   `json:"author"`
	Description  string   `json:"description"`
	URL          string   `json:"url"`
	SHA256       string   `json:"sha256"`
	Capabilities []string `json:"capabilities"`
}

func checksum(data []byte) string {
	h := sha256.Sum256(data)
	return hex.EncodeToString(h[:])
}

func validChecksum(value string) bool {
	if len(value) != 2*sha256.Size {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func origin(u *url.URL) string {
	port := u.Port()
	if port == "" {
		if u.Scheme == "https" {
			port = "443"
		} else {
			port = "80"
		}
	}
	return u.Scheme + "://" + net.JoinHostPort(strings.ToLower(u.Hostname()), port)
}

func checkedURL(raw string) (*url.URL, error) {
	if len(raw) == 0 || len(raw) > 4096 || strings.ContainsAny(raw, "#\\") {
		return nil, errors.New("请输入有效的目录或插件 URL")
	}
	u, err := url.Parse(raw)
	if err != nil || u.Hostname() == "" || u.User != nil || u.Opaque != "" {
		return nil, errors.New("URL 必须包含主机且不能附带用户凭据")
	}
	if port := u.Port(); port != "" {
		n, err := strconv.Atoi(port)
		if err != nil || n <= 0 || n > 65535 {
			return nil, errors.New("URL 端口无效")
		}
	}
	if u.Scheme == "https" {
		return u, nil
	}
	ip, ipErr := netip.ParseAddr(u.Hostname())
	if u.Scheme == "http" && (strings.EqualFold(u.Hostname(), "localhost") || (ipErr == nil && ip.Unmap().IsLoopback())) {
		return u, nil
	}
	return nil, errors.New("远程来源需要 HTTPS，本机回环地址可使用 HTTP")
}

// ParseCatalog validates metadata and resolves package references against the
// final catalog URL. An empty URL selects the embedded filesystem rules.
func ParseCatalog(data []byte, catalogURL string) (Catalog, error) {
	var catalog Catalog
	if len(data) > MaxCatalogBytes || !utf8.Valid(data) {
		return catalog, errors.New("目录过大或不是 UTF-8")
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	if err := checkJSONValue(dec, 0); err != nil {
		return Catalog{}, fmt.Errorf("目录 JSON 无效: %w", err)
	}
	dec = json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&catalog); err != nil {
		return Catalog{}, fmt.Errorf("目录 JSON 无效: %w", err)
	}
	if err := dec.Decode(new(any)); err != io.EOF {
		return Catalog{}, errors.New("目录末尾有额外内容")
	}
	if catalog.SchemaVersion != 1 || catalog.Plugins == nil || len(catalog.Plugins) > MaxCatalogEntries {
		return Catalog{}, errors.New("目录版本、插件列表或数量无效")
	}
	if !validText(catalog.Name, 128, false) {
		return Catalog{}, errors.New("目录名称无效")
	}
	var base *url.URL
	var err error
	if catalogURL != "" {
		base, err = checkedURL(catalogURL)
		if err != nil {
			return Catalog{}, err
		}
	}
	seen := make(map[string]bool)
	for i := range catalog.Plugins {
		p := &catalog.Plugins[i]
		if err := ValidateMetadata(p.ID, p.Version, p.Name, p.Author, p.Description); err != nil {
			return Catalog{}, fmt.Errorf("目录条目 %d: %w", i+1, err)
		}
		if seen[p.ID] {
			return Catalog{}, fmt.Errorf("目录中插件 ID 重复: %s", p.ID)
		}
		seen[p.ID] = true
		if !validChecksum(p.SHA256) {
			return Catalog{}, fmt.Errorf("插件 %s 缺少有效 SHA-256", p.ID)
		}
		p.SHA256 = strings.ToLower(p.SHA256)
		if p.Capabilities == nil {
			return Catalog{}, fmt.Errorf("插件 %s 缺少权限列表", p.ID)
		}
		slices.Sort(p.Capabilities)
		for j, cap := range p.Capabilities {
			switch cap {
			case CapRoundGuidance, CapReportGuidance, CapPublicTurns, CapReport, CapCodeExecute:
			default:
				return Catalog{}, fmt.Errorf("未知插件权限 %q", cap)
			}
			if j > 0 && cap == p.Capabilities[j-1] {
				return Catalog{}, fmt.Errorf("权限重复 %q", cap)
			}
		}
		p.URL, err = packageURL(base, p.URL)
		if err != nil {
			return Catalog{}, fmt.Errorf("插件 %s: %w", p.ID, err)
		}
	}
	return catalog, nil
}

func packageURL(base *url.URL, raw string) (string, error) {
	if raw == "" || len(raw) > 4096 || strings.ContainsAny(raw, "#\\") {
		return "", errors.New("无效的插件包位置")
	}
	u, err := url.Parse(raw)
	if err != nil || u.User != nil || u.Opaque != "" {
		return "", errors.New("无效的插件包 URL")
	}
	if base == nil {
		if u.Scheme != "" || u.Host != "" || u.RawQuery != "" || u.ForceQuery || !fs.ValidPath(u.Path) || u.Path == "." {
			return "", errors.New("内置包需要相对文件路径")
		}
		return u.Path, nil
	}
	resolved, err := checkedURL(base.ResolveReference(u).String())
	if err != nil || origin(resolved) != origin(base) {
		return "", errors.New("插件包需与订阅目录同源")
	}
	return resolved.String(), nil
}

func readLimited(r io.Reader, limit int64) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(r, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > limit {
		return nil, errors.New("文件超出大小限制")
	}
	return data, nil
}

func fetch(ctx context.Context, rawURL string, limit int64) ([]byte, string, error) {
	start, err := checkedURL(rawURL)
	if err != nil {
		return nil, "", err
	}
	client := http.Client{
		Timeout: catalogTimeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			redirect, err := checkedURL(req.URL.String())
			if err != nil || origin(redirect) != origin(start) || len(via) > 3 {
				return errors.New("目录和插件只允许最多三次同源跳转")
			}
			req.Header.Del("Referer")
			return nil
		},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, start.String(), nil)
	if err != nil {
		return nil, "", err
	}
	res, err := client.Do(req)
	if err != nil {
		return nil, "", fmt.Errorf("读取插件来源失败: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("读取插件来源失败 (HTTP %d)", res.StatusCode)
	}
	if res.ContentLength > limit {
		return nil, "", errors.New("远程文件超出大小限制")
	}
	data, err := readLimited(res.Body, limit)
	return data, res.Request.URL.String(), err
}
