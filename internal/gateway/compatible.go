package gateway

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

const compatibleModelPrefix = "sci-station-byok/"

// CompatibleProfile contains shareable model settings. Credential resolution
// is delegated to the application and does not cache a token in the gateway.
type CompatibleProfile struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	BaseURL     string  `json:"base_url"`
	Model       string  `json:"model"`
	Temperature float64 `json:"temperature"`
	MaxTokens   int     `json:"max_tokens"`
	Vision      bool    `json:"vision"`
}

type CompatibleProfiles interface {
	Profiles() []CompatibleProfile
	ResolveKey(CompatibleProfile) (string, error)
}

func (p CompatibleProfile) CatalogModel() Model {
	return Model{ID: compatibleModelPrefix + p.ID, Source: "openai-compatible", Label: p.Name,
		Endpoints: []string{"/chat/completions"}, Efforts: []string{"auto"}}
}

// NormalizeCompatibleProfile accepts TLS services and cleartext loopback.
// In particular, a key can never be smuggled into persisted URL user info.
func NormalizeCompatibleProfile(p CompatibleProfile) (CompatibleProfile, error) {
	p.Name = strings.TrimSpace(p.Name)
	p.Model = strings.TrimSpace(p.Model)
	if p.Name == "" || utf8.RuneCountInString(p.Name) > 80 || strings.IndexFunc(p.Name, unicode.IsControl) != -1 {
		return p, errors.New("请输入不超过 80 字的配置名称")
	}
	if p.Model == "" || len(p.Model) > 512 || strings.IndexFunc(p.Model, func(c rune) bool {
		return unicode.IsSpace(c) || unicode.IsControl(c)
	}) != -1 {
		return p, errors.New("请输入有效的服务端模型 ID")
	}
	if math.IsNaN(p.Temperature) || p.Temperature < 0 || p.Temperature > 2 || p.MaxTokens < 0 || p.MaxTokens > 10_000_000 {
		return p, errors.New("温度应在 0–2 之间，输出限制可留空或填写 1–10000000")
	}
	u, err := url.Parse(strings.TrimSpace(p.BaseURL))
	if err != nil || u.Hostname() == "" || strings.HasSuffix(u.Host, ":") || u.User != nil || u.ForceQuery || u.RawQuery != "" || u.Fragment != "" ||
		u.RawFragment != "" || u.Opaque != "" || u.RawPath != "" || len(p.BaseURL) > 2048 {
		return p, errors.New("请输入有效的 API Base URL")
	}
	if port := u.Port(); port != "" {
		n, err := strconv.Atoi(port)
		if err != nil || n < 1 || n > 65535 {
			return p, errors.New("API Base URL 的端口无效")
		}
	}
	if u.Scheme == "http" && strings.EqualFold(u.Hostname(), "localhost") {
		port := u.Port()
		u.Host = "127.0.0.1"
		if port != "" {
			u.Host = net.JoinHostPort(u.Host, port)
		}
	}
	if u.Scheme != "https" && (u.Scheme != "http" || !net.ParseIP(u.Hostname()).IsLoopback()) {
		return p, errors.New("API Base URL 需要 HTTPS。本机回环地址支持 HTTP")
	}
	u.Host = strings.ToLower(u.Host)
	u.Path = strings.TrimRight(u.Path, "/")
	p.BaseURL = u.String()
	return p, nil
}

func (g *Gateway) completeCompatible(ctx context.Context, id, effort string, messages []message, images []InputImage, callbacks streamCallbacks) (completion, error) {
	if effort != "" && effort != "auto" {
		return completion{}, errors.New("直接模型配置使用自动推理设置")
	}
	if g.compatible != nil {
		for _, profile := range g.compatible.Profiles() {
			if profile.ID == id {
				return g.sendCompatible(ctx, profile, "", messages, images, callbacks)
			}
		}
	}
	return completion{}, errors.New("找不到选定的直接模型配置")
}

// TestCompatible sends a small connection-check prompt using the same route
// as a meeting. A typed key overrides the saved key for this call only.
func (g *Gateway) TestCompatible(ctx context.Context, profile CompatibleProfile, typedKey string) error {
	profile, err := NormalizeCompatibleProfile(profile)
	if err != nil {
		return err
	}
	_, err = g.sendCompatible(ctx, profile, typedKey, []message{{Role: "user", Content: "Reply with OK."}}, nil, streamCallbacks{})
	return err
}

func (g *Gateway) sendCompatible(ctx context.Context, p CompatibleProfile, key string, messages []message, images []InputImage, callbacks streamCallbacks) (completion, error) {
	var err error
	if key == "" && g.compatible != nil {
		key, err = g.compatible.ResolveKey(p)
		if err != nil {
			return completion{}, errors.New("无法从 macOS 钥匙串读取直接模型凭证")
		}
	}
	if key == "" && strings.HasPrefix(p.BaseURL, "https://") {
		return completion{}, errors.New("请先在直接模型配置中保存 API Key")
	}
	if len(images) == 0 {
		return g.compatibleRequest(ctx, p, key, messages, nil, callbacks)
	}
	if p.Vision {
		wire := makeWireImages(images)
		result, err := g.compatibleRequest(ctx, p, key, messages, wire, callbacks.guardImageEcho())
		if !errors.Is(err, errImageInputUnsupported) || ctx.Err() != nil {
			for _, image := range wire {
				result.Text = strings.ReplaceAll(result.Text, image.dataURL, "[image preview]")
			}
			return result, err
		}
		if callbacks.reset != nil {
			callbacks.reset()
		}
	}
	messages[len(messages)-1].Content += imageUnavailable
	return g.compatibleRequest(ctx, p, key, messages, nil, callbacks)
}

func (g *Gateway) compatibleRequest(ctx context.Context, p CompatibleProfile, key string, messages []message, images []wireImage, callbacks streamCallbacks) (completion, error) {
	payload := map[string]any{"model": p.Model, "messages": messages, "stream": true, "temperature": p.Temperature}
	if p.MaxTokens > 0 {
		payload["max_tokens"] = p.MaxTokens
	}
	if len(images) > 0 {
		payload["messages"] = imageMessages(messages, images, false)
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return completion{}, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.BaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return completion{}, errors.New("直接模型服务地址无效")
	}
	req.Header.Set("User-Agent", "SciStation/2")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream, application/json")
	if key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
	}
	resp, err := g.client.Do(req)
	if err != nil {
		if ctx.Err() != nil {
			return completion{}, ctx.Err()
		}
		return completion{}, errors.New("无法连接直接模型服务")
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		if len(images) > 0 && (resp.StatusCode == 400 || resp.StatusCode == 415 || resp.StatusCode == 422) {
			var event map[string]any
			if json.NewDecoder(io.LimitReader(resp.Body, 16<<10)).Decode(&event) == nil && imageInputUnsupported(event) {
				return completion{}, errImageInputUnsupported
			}
		}
		return completion{}, fmt.Errorf("直接模型服务返回 HTTP %d", resp.StatusCode)
	}
	guarded, flush := guardKeyEcho(callbacks, key)
	result, err := decodeCompletion(resp, false, len(images) != 0, guarded)
	if errors.Is(err, errImageInputUnsupported) || errors.Is(err, errKeyEcho) {
		return completion{}, err
	}
	if err != nil {
		return completion{}, errors.New("直接模型服务返回了无效或未完成的内容")
	}
	if key != "" && strings.Contains(result.Text, key) {
		return completion{}, errKeyEcho
	}
	return result, flush()
}

var errKeyEcho = errors.New("直接模型服务在输出中返回了凭证，发言已停止")

// Retain any suffix that could start the key so a split SSE event cannot
// forward credentials to the observer before final response redaction.
func guardKeyEcho(callbacks streamCallbacks, key string) (streamCallbacks, func() error) {
	if callbacks.text == nil || key == "" {
		return callbacks, func() error { return nil }
	}
	next, reset := callbacks.text, callbacks.reset
	var pending string
	callbacks.text = func(delta string) error {
		chunk := pending + delta
		if strings.Contains(chunk, key) {
			return errKeyEcho
		}
		suffix := min(len(chunk), len(key)-1)
		for suffix > 0 && chunk[len(chunk)-suffix:] != key[:suffix] {
			suffix--
		}
		pending = chunk[len(chunk)-suffix:]
		if len(chunk) == suffix {
			return nil
		}
		return next(chunk[:len(chunk)-suffix])
	}
	callbacks.reset = func() {
		pending = ""
		if reset != nil {
			reset()
		}
	}
	return callbacks, func() error {
		if pending == "" {
			return nil
		}
		return next(pending)
	}
}
