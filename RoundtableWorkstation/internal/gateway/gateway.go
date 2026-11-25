package gateway

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	"scistation.local/desktop/internal/magpieconfig"
)

// Model describes one current Magpie catalog entry. Auto leaves the request's
// reasoning controls unset, including on models with no advertised levels.
type Model struct {
	ID        string   `json:"id"`
	Source    string   `json:"source"`
	Label     string   `json:"label"`
	Endpoints []string `json:"endpoints"`
	Efforts   []string `json:"efforts"`
	preferred string
	textOnly  bool
}
type Catalog struct {
	Models       []Model `json:"models"`
	DefaultModel string  `json:"default_model"`
	MagpieError  string  `json:"magpie_error,omitempty"`
}
type completion struct {
	Text  string
	Model string
	Usage map[string]any
}
type Gateway struct {
	config     func() (magpieconfig.Config, error)
	client     *http.Client
	compatible CompatibleProfiles
}

var loopbackClient = &http.Client{
	Transport:     &http.Transport{Proxy: nil, DialContext: (&net.Dialer{Timeout: 5 * time.Second}).DialContext, IdleConnTimeout: 90 * time.Second},
	CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
}

func NewManagedGateway(port func() int, compatible CompatibleProfiles) *Gateway {
	return &Gateway{config: func() (magpieconfig.Config, error) { return magpieconfig.Load(port()) }, client: loopbackClient, compatible: compatible}
}
func newGateway(port func() int) *Gateway {
	return &Gateway{config: func() (magpieconfig.Config, error) { return magpieconfig.Config{Port: port()}, nil }, client: loopbackClient}
}

type message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

func gatewayError(s string) error { return errors.New(s) }
func (g *Gateway) request(ctx context.Context, cfg magpieconfig.Config, route string, payload any, session string, preferred, hasImages bool) (*http.Response, error) {
	p := cfg.Port
	if p < 1 || p > 65535 {
		return nil, gatewayError("Magpie 网关端口无效。")
	}
	var body io.Reader
	method := "GET"
	if payload != nil {
		b, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}
		body = bytes.NewReader(b)
		method = "POST"
	}
	req, err := http.NewRequestWithContext(ctx, method, "http://127.0.0.1:"+strconv.Itoa(p)+route, body)
	if err != nil {
		return nil, gatewayError("无法连接本机 Magpie。")
	}
	req.Header.Set("User-Agent", "SciStation/2")
	if preferred {
		req.Header.Set("X-Magpie-Drawers", "1")
	}
	req.Header.Set("Authorization", "Bearer "+magpieconfig.LoopbackIdentity)
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Accept", "text/event-stream")
		req.Header.Set("X-Magpie-Session", session)
	}
	resp, err := g.client.Do(req)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, gatewayError(fmt.Sprintf("无法连接本机 Magpie 网关（端口 %d），请在 Magpie 中确认网关已启动。", p))
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		defer resp.Body.Close()
		if hasImages && (resp.StatusCode == http.StatusBadRequest || resp.StatusCode == http.StatusUnsupportedMediaType || resp.StatusCode == http.StatusUnprocessableEntity) {
			var event map[string]any
			if json.NewDecoder(io.LimitReader(resp.Body, 16<<10)).Decode(&event) == nil && imageInputUnsupported(event) {
				return nil, errImageInputUnsupported
			}
		}
		if resp.StatusCode == 401 || resp.StatusCode == 403 {
			return nil, gatewayError(fmt.Sprintf("Magpie 拒绝访问（HTTP %d），请在 Magpie 的 Agents 中检查圆桌的连接和访问范围。", resp.StatusCode))
		}
		return nil, gatewayError(fmt.Sprintf("Magpie 返回 HTTP %d（%s）", resp.StatusCode, route))
	}
	return resp, nil
}

// Catalog reopens the agent configuration on every call. A missing default
// stays empty when the model is no longer offered by the active gateway key.
func (g *Gateway) Catalog(ctx context.Context) (Catalog, error) {
	var profiles []CompatibleProfile
	if g.compatible != nil {
		profiles = g.compatible.Profiles()
	}
	cfg, err := g.config()
	var catalog Catalog
	if err == nil {
		catalog, err = g.catalog(ctx, cfg, false)
	}
	if ctx.Err() != nil {
		return Catalog{}, ctx.Err()
	}
	if len(profiles) == 0 {
		return catalog, err
	}
	if err != nil {
		catalog.MagpieError = err.Error()
	}
	if len(catalog.Models) == 0 {
		catalog.DefaultModel = profiles[0].CatalogModel().ID
	}
	for _, profile := range profiles {
		catalog.Models = append(catalog.Models, profile.CatalogModel())
	}
	return catalog, nil
}

func (g *Gateway) catalog(ctx context.Context, cfg magpieconfig.Config, preferred bool) (Catalog, error) {
	parentCtx := ctx
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	resp, err := g.request(ctx, cfg, "/v1/models", nil, "", preferred, false)
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded && parentCtx.Err() == nil {
			return Catalog{}, gatewayError("读取 Magpie 模型目录超时，请检查本机网关。")
		}
		return Catalog{}, err
	}
	defer resp.Body.Close()
	var raw struct {
		Data []struct {
			ID        string   `json:"id"`
			Display   string   `json:"display_name"`
			Preferred string   `json:"magpie_prefers"`
			Owner     string   `json:"owned_by"`
			Kind      string   `json:"kind"`
			Endpoints []string `json:"native_endpoints"`
			Inputs    []string `json:"input_modalities"`
			Levels    []string `json:"reasoning_levels"`
			Supported []struct {
				Effort string `json:"effort"`
			} `json:"supported_reasoning_levels"`
		} `json:"data"`
	}
	if json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(&raw) != nil || raw.Data == nil {
		return Catalog{}, gatewayError("Magpie 返回的模型目录格式无效。")
	}
	out := Catalog{Models: []Model{}}
	seen := map[string]bool{}
	for _, m := range raw.Data {
		if strings.TrimSpace(m.ID) == "" || strings.HasPrefix(m.ID, compatibleModelPrefix) || seen[m.ID] || (m.Kind != "" && m.Kind != "chat") {
			continue
		}
		seen[m.ID] = true
		source, name, explicit := strings.Cut(m.ID, "/")
		if !explicit {
			source, name = "group", m.ID
		}
		if m.Owner != "" {
			source = m.Owner
		}
		label := m.Display
		if label == "" {
			label = name
		}
		levels := m.Levels
		if levels == nil {
			for _, l := range m.Supported {
				levels = append(levels, l.Effort)
			}
		}
		efforts := []string{"auto"}
		for _, level := range levels {
			if level != "" && !slices.Contains(efforts, level) {
				efforts = append(efforts, level)
			}
		}
		if m.Endpoints == nil {
			m.Endpoints = []string{}
		}
		textOnly := len(m.Inputs) > 0 && !slices.Contains(m.Inputs, "image") && !slices.Contains(m.Inputs, "vision")
		out.Models = append(out.Models, Model{ID: m.ID, Source: source, Label: label, Endpoints: m.Endpoints, Efforts: efforts, preferred: m.Preferred, textOnly: textOnly})
		if m.ID == cfg.Model {
			out.DefaultModel = m.ID
		}
	}
	return out, nil
}

// Generate obtains a response from the configured Magpie model.
func (g *Gateway) Generate(ctx context.Context, id, effort, rules, prompt, session string) (string, error) {
	return g.GenerateWithImages(ctx, id, effort, rules, prompt, session, nil)
}

// A supplied observer receives real provider output-text deltas only. An empty
// string retracts prior deltas if their stream is abandoned.
func (g *Gateway) GenerateWithImages(ctx context.Context, id, effort, rules, prompt, session string, images []InputImage, observer ...func(string)) (string, error) {
	messages := []message{}
	if rules != "" {
		messages = append(messages, message{Role: "system", Content: rules})
	}
	messages = append(messages, message{Role: "user", Content: prompt})
	var callbacks streamCallbacks
	if len(observer) != 0 && observer[0] != nil {
		observed := false
		callbacks.text = func(delta string) error {
			if err := ctx.Err(); err != nil {
				return err
			}
			observed = true
			observer[0](delta)
			return nil
		}
		callbacks.reset = func() {
			if observed {
				observed = false
				observer[0]("")
			}
		}
	}
	result, err := g.completeContext(ctx, id, effort, messages, session, images, callbacks)
	if (err != nil || ctx.Err() != nil) && callbacks.reset != nil {
		callbacks.reset()
	}
	if ctx.Err() != nil {
		return "", ctx.Err()
	}
	return result.Text, err
}

type streamCallbacks struct {
	text  func(string) error
	reset func()
}

// The model can echo an attached data URL. Hold a suffix that could start that
// marker so it cannot reach the live observer across event boundaries.
func (c streamCallbacks) guardImageEcho() streamCallbacks {
	if c.text == nil || c.reset == nil {
		return c
	}
	const marker = "data:image"
	next := c.text
	pending, muted := "", false
	c.text = func(delta string) error {
		if muted {
			return nil
		}
		chunk := pending + delta
		for i := 0; i+len(marker) <= len(chunk); i++ {
			if (chunk[i] == 'd' || chunk[i] == 'D') && strings.EqualFold(chunk[i:i+len(marker)], marker) {
				muted = true
				c.reset()
				return nil
			}
		}
		suffix := min(len(chunk), len(marker)-1)
		for suffix > 0 && !strings.EqualFold(chunk[len(chunk)-suffix:], marker[:suffix]) {
			suffix--
		}
		rest := len(chunk) - suffix
		pending = chunk[rest:]
		if rest == 0 {
			return nil
		}
		return next(chunk[:rest])
	}
	return c
}

func (g *Gateway) completeContext(ctx context.Context, id, effort string, messages []message, session string, images []InputImage, callbacks streamCallbacks) (completion, error) {
	if profileID, ok := strings.CutPrefix(id, compatibleModelPrefix); ok {
		return g.completeCompatible(ctx, profileID, effort, messages, images, callbacks)
	}
	cfg, err := g.config()
	if err != nil {
		return completion{}, err
	}
	// The extended list tells us the best protocol even for route groups
	// with no native_endpoints. Magpie omits optional bare aliases from that
	// list, so resolve a missing unqualified ID against its public list too.
	lookup := func(extended bool) (*Model, error) {
		cat, err := g.catalog(ctx, cfg, extended)
		if err != nil {
			return nil, err
		}
		for i := range cat.Models {
			if cat.Models[i].ID == id {
				return &cat.Models[i], nil
			}
		}
		return nil, nil
	}
	selected, err := lookup(true)
	if err == nil && selected == nil && !strings.Contains(id, "/") {
		selected, err = lookup(false)
	}
	if err != nil {
		return completion{}, err
	}
	if selected == nil {
		return completion{}, gatewayError(fmt.Sprintf("Magpie 当前目录中没有模型 %q，请检查模型或路由组的配置。", id))
	}
	if effort == "" {
		effort = "auto"
	}
	if !slices.Contains(selected.Efforts, effort) {
		return completion{}, gatewayError(fmt.Sprintf("Magpie 当前目录未列出模型 %q 的思考程度 %q。", id, effort))
	}
	// Magpie natively accepts both OpenAI wire formats. For Anthropic-only,
	// Gemini-only and routed models its documented Chat translation handles the
	// vendor-specific thinking controls rather than guessing a token budget.
	responses := selected.preferred == "/v1/responses" || (selected.preferred == "" && slices.Contains(selected.Endpoints, "/v1/responses"))
	if len(images) != 0 {
		if !selected.textOnly {
			wire := makeWireImages(images)
			// A one-call session keeps previews out of subsequent tool, private,
			// and text-only requests even if the gateway retains session state.
			visualSession := session + "-visual-" + rand.Text()
			result, err := g.completeMessages(ctx, cfg, id, effort, messages, visualSession, responses, wire, callbacks.guardImageEcho())
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
		last := len(messages) - 1
		messages[last].Content += imageUnavailable
	}
	return g.completeMessages(ctx, cfg, id, effort, messages, session, responses, nil, callbacks)
}

func (g *Gateway) completeMessages(ctx context.Context, cfg magpieconfig.Config, id, effort string, messages []message, session string, responses bool, images []wireImage, callbacks streamCallbacks) (completion, error) {
	route := "/v1/chat/completions"
	payload := map[string]any{"model": id, "messages": messages, "stream": true}
	if responses {
		route = "/v1/responses"
		instructions := []string{}
		input := []message{}
		for _, m := range messages {
			if m.Role == "system" {
				instructions = append(instructions, m.Content)
			} else {
				input = append(input, m)
			}
		}
		payload = map[string]any{"model": id, "instructions": strings.Join(instructions, "\n\n"), "input": input, "stream": true, "store": false}
		if len(images) != 0 {
			payload["input"] = imageMessages(input, images, true)
		}
	} else if len(images) != 0 {
		payload["messages"] = imageMessages(messages, images, false)
	}
	if effort != "auto" {
		if responses {
			payload["reasoning"] = map[string]string{"effort": effort}
		} else {
			payload["reasoning_effort"] = effort
		}
	}
	resp, err := g.request(ctx, cfg, route, payload, session, false, len(images) != 0)
	if err != nil {
		return completion{}, err
	}
	defer resp.Body.Close()
	return decodeCompletion(resp, responses, len(images) != 0, callbacks)
}

func decodeCompletion(resp *http.Response, responses, hasImages bool, callbacks streamCallbacks) (completion, error) {
	if strings.Contains(resp.Header.Get("Content-Type"), "text/event-stream") {
		return parseStream(io.LimitReader(resp.Body, 64<<20), responses, callbacks.text, callbacks.reset)
	}
	var event map[string]any
	if json.NewDecoder(io.LimitReader(resp.Body, 64<<20)).Decode(&event) != nil {
		return completion{}, gatewayError("Magpie 返回无效的发言格式。")
	}
	if event["error"] != nil {
		if hasImages && imageInputUnsupported(event) {
			return completion{}, errImageInputUnsupported
		}
		return completion{}, gatewayError("Magpie 报告上游发言失败。")
	}
	result := completion{Model: str(event["model"]), Usage: obj(event["usage"])}
	if responses {
		if str(event["status"]) != "completed" {
			return result, gatewayError("Magpie 返回未完成的发言。")
		}
		result.Text = responseText(event)
	} else {
		choices := array(event["choices"])
		if len(choices) > 0 {
			c := obj(choices[0])
			finish := str(c["finish_reason"])
			if finish != "stop" {
				return result, gatewayError("上游在发言完成前停止了输出。")
			}
			result.Text = str(obj(c["message"])["content"])
		}
	}
	if strings.TrimSpace(result.Text) == "" {
		return result, gatewayError("Magpie 没有返回可读的发言。")
	}
	return result, nil
}
func obj(v any) map[string]any {
	m, ok := v.(map[string]any)
	if !ok {
		return map[string]any{}
	}
	return m
}
func str(v any) string  { s, _ := v.(string); return s }
func array(v any) []any { s, _ := v.([]any); return s }
func responseText(v map[string]any) string {
	var b strings.Builder
	for _, value := range array(v["output"]) {
		item := obj(value)
		if str(item["type"]) != "message" {
			continue
		}
		for _, value := range array(item["content"]) {
			part := obj(value)
			switch str(part["type"]) {
			case "output_text":
				b.WriteString(str(part["text"]))
			case "refusal":
				b.WriteString(str(part["refusal"]))
			}
		}
	}
	return b.String()
}
func parseStream(reader io.Reader, responses bool, onDelta func(string) error, resetObserver ...func()) (completion, error) {
	var reset func()
	if len(resetObserver) != 0 {
		reset = resetObserver[0]
	}
	result := completion{Usage: map[string]any{}}
	var text strings.Builder
	finished := false
	done := false
	muted := false
	consume := func(block string) error {
		if block == "[DONE]" {
			done = true
			return nil
		}
		var event map[string]any
		if json.Unmarshal([]byte(block), &event) != nil {
			return gatewayError("Magpie 返回无效的发言流。")
		}
		kind := str(event["type"])
		if event["error"] != nil || kind == "error" || kind == "response.failed" || kind == "response.incomplete" {
			if text.Len() == 0 && imageInputUnsupported(event) {
				return errImageInputUnsupported
			}
			return gatewayError("Magpie 报告上游发言失败或不完整。")
		}
		delta, refusal := "", false
		if responses {
			meta := obj(event["response"])
			if m := str(meta["model"]); m != "" {
				result.Model = m
			}
			switch kind {
			case "response.output_text.delta":
				delta = str(event["delta"])
			case "response.refusal.delta":
				delta = str(event["delta"])
				refusal = delta != ""
			case "response.completed":
				if status := str(meta["status"]); status != "" && status != "completed" {
					return gatewayError("Magpie 返回未完成的发言。")
				}
				if u, ok := meta["usage"].(map[string]any); ok {
					result.Usage = u
				}
				if canonical := responseText(meta); canonical != "" {
					text.Reset()
					text.WriteString(canonical)
				}
				finished = true
			}
		} else {
			if m := str(event["model"]); m != "" {
				result.Model = m
			}
			if u, ok := event["usage"].(map[string]any); ok {
				result.Usage = u
			}
			for _, value := range array(event["choices"]) {
				c := obj(value)
				if index, ok := c["index"].(float64); ok && index != 0 {
					continue
				}
				part := obj(c["delta"])
				delta = str(part["content"])
				refusal = str(part["refusal"]) != ""
				reason := str(c["finish_reason"])
				if reason == "stop" {
					finished = true
				} else if reason != "" {
					return gatewayError("上游在发言完成前停止了输出。")
				}
			}
		}
		if delta != "" {
			text.WriteString(delta)
		}
		if refusal && reset != nil {
			reset()
			muted = true
		}
		if !muted && delta != "" && onDelta != nil {
			return onDelta(delta)
		}
		return nil
	}
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 4096), 8<<20)
	data := []string{}
	for scanner.Scan() {
		line := strings.TrimSuffix(scanner.Text(), "\r")
		if line == "" {
			if len(data) > 0 {
				if err := consume(strings.Join(data, "\n")); err != nil {
					return result, err
				}
				data = nil
				if done {
					break
				}
			}
		} else if strings.HasPrefix(line, "data:") {
			data = append(data, strings.TrimPrefix(strings.TrimPrefix(line, "data:"), " "))
		}
	}
	if scanner.Err() != nil {
		return result, gatewayError("发言流中断；可单独重试这一席。")
	}
	if !done && len(data) > 0 {
		if err := consume(strings.Join(data, "\n")); err != nil {
			return result, err
		}
	}
	result.Text = text.String()
	if !finished || strings.TrimSpace(result.Text) == "" {
		return result, gatewayError("发言流中断或未产生正文；可单独重试这一席。")
	}
	return result, nil
}
