package gateway

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

type gatewayTransport func(*http.Request) (*http.Response, error)

func (f gatewayTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestRouteGroupPreferredResponsesAndPublicAlias(t *testing.T) {
	g := newGateway(func() int { return 9999 })
	g.client = &http.Client{Transport: gatewayTransport(func(r *http.Request) (*http.Response, error) {
		if r.Header.Get("Authorization") != "Bearer magpie-sci-station" {
			t.Error("missing local Magpie attribution")
		}
		var body string
		switch r.URL.Path {
		case "/v1/models":
			if r.Header.Get("X-Magpie-Drawers") != "" {
				body = `{"data":[{"id":"committee","owned_by":"group","magpie_prefers":"/v1/responses","reasoning_levels":["max"]}]}`
			} else {
				body = `{"data":[{"id":"committee","owned_by":"group","reasoning_levels":["max"]},{"id":"alias","owned_by":"vendor"}]}`
			}
		case "/v1/responses":
			var p struct {
				Model     string
				Reasoning struct{ Effort string }
			}
			if err := json.NewDecoder(r.Body).Decode(&p); err != nil || p.Model != "committee" || p.Reasoning.Effort != "max" {
				t.Errorf("wrong response fields: %+v %v", p, err)
			}
			body = `{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}]}`
		case "/v1/chat/completions":
			var p map[string]any
			if err := json.NewDecoder(r.Body).Decode(&p); err != nil || p["model"] != "alias" || p["reasoning_effort"] != nil {
				t.Errorf("wrong alias request: %v", p)
			}
			body = `{"choices":[{"finish_reason":"stop","message":{"content":"ok"}}]}`
		default:
			t.Errorf("unexpected endpoint %s", r.URL.Path)
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{"Content-Type": {"application/json"}}}, nil
	})}
	catalog, err := g.Catalog(context.Background())
	if err != nil || len(catalog.Models) != 2 {
		t.Fatalf("public catalog missing alias: %v %v", catalog, err)
	}
	for _, tc := range []struct{ id, effort string }{{"committee", "max"}, {"alias", "auto"}} {
		if text, err := g.Generate(context.Background(), tc.id, tc.effort, "", "input", "session"); err != nil || text != "ok" {
			t.Fatalf("%s: %q %v", tc.id, text, err)
		}
	}
}
