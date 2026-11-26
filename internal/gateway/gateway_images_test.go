package gateway

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestGatewayImageRequestFormats(t *testing.T) {
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, image.NewRGBA(image.Rect(0, 0, 2, 3))); err != nil {
		t.Fatal(err)
	}
	dataURL := "data:image/png;base64," + base64.StdEncoding.EncodeToString(encoded.Bytes())
	for _, endpoint := range []string{"/v1/responses", "/v1/chat/completions"} {
		t.Run(endpoint, func(t *testing.T) {
			g := newGateway(func() int { return 9999 })
			g.client = &http.Client{Transport: gatewayTransport(func(r *http.Request) (*http.Response, error) {
				if r.URL.Path == "/v1/models" {
					return imageGatewayResponse(200, "application/json", fmt.Sprintf(`{"data":[{"id":"vision","magpie_prefers":%q}]}`, endpoint)), nil
				}
				if r.URL.Path != endpoint || !strings.HasPrefix(r.Header.Get("X-Magpie-Session"), "test-session-visual-") {
					t.Errorf("wrong endpoint or unisolated visual session: %s %s", r.URL.Path, r.Header.Get("X-Magpie-Session"))
				}
				var body map[string]any
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					return nil, err
				}
				input, textType, imageType := "messages", "text", "image_url"
				if endpoint == "/v1/responses" {
					input, textType, imageType = "input", "input_text", "input_image"
					if body["instructions"] != "review rules" || body["store"] != false {
						t.Errorf("invalid Responses instructions or retention option: %v", body)
					}
				}
				msgs := array(body[input])
				if len(msgs) == 0 {
					return nil, fmt.Errorf("no %s in request", input)
				}
				user := obj(msgs[len(msgs)-1])
				parts := array(user["content"])
				if user["role"] != "user" || len(parts) != 3 {
					return nil, fmt.Errorf("invalid user content: %v", user)
				}
				if obj(parts[0])["type"] != textType || obj(parts[0])["text"] != "check the layout" ||
					obj(parts[1])["type"] != textType || obj(parts[1])["text"] != "Image preview for material ID material-id" ||
					obj(parts[2])["type"] != imageType {
					t.Errorf("invalid image content parts: %v", parts)
				}
				wireURL := obj(parts[2])["image_url"]
				if endpoint != "/v1/responses" {
					wireURL = obj(wireURL)["url"]
					if len(msgs) != 2 || obj(msgs[0])["content"] != "review rules" {
						t.Error("Chat system instructions changed")
					}
				}
				if wireURL != dataURL {
					t.Error("the uploaded PNG was absent from the image content")
				}
				if endpoint == "/v1/responses" {
					return imageGatewayResponse(200, "application/json", `{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"image checked"}]}]}`), nil
				}
				return imageGatewayResponse(200, "application/json", fmt.Sprintf(`{"choices":[{"finish_reason":"stop","message":{"content":%q}}]}`, "image checked "+dataURL)), nil
			})}
			out, err := g.GenerateWithImages(context.Background(), "vision", "auto", "review rules", "check the layout", "test-session", []InputImage{{"material-id", "image/png", encoded.Bytes()}})
			if err != nil || !strings.HasPrefix(out, "image checked") || strings.Contains(out, dataURL) {
				t.Fatalf("visual result or protection against payload echo: %q, %v", out, err)
			}
		})
	}
}

func TestGatewayImageFallbackIsExplicitAndSelective(t *testing.T) {
	tests := []struct {
		name, catalogFields, errorBody string
		status                         int
		stream, wantVision, wantPlain  bool
	}{
		{"catalog declares only text", `,"input_modalities":["text"]`, "", 0, false, false, true},
		{"HTTP rejects images", "", `{"error":{"message":"This model does not support image input."}}`, 400, false, true, true},
		{"stream rejects images", "", "data: {\"type\":\"error\",\"code\":\"image_input_not_supported\"}\n\n", 200, true, true, true},
		{"unrelated HTTP rejection", "", `{"error":{"message":"The response format is not supported by model image-preview."}}`, 400, false, true, false},
		{"rate limit", "", `{"error":{"message":"This model does not support image input."}}`, 429, false, true, false},
		{"stream fails after output", "", "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\ndata: {\"type\":\"error\",\"code\":\"image_input_not_supported\"}\n\n", 200, true, true, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			g := newGateway(func() int { return 9999 })
			visualCalls, plainCalls := 0, 0
			g.client = &http.Client{Transport: gatewayTransport(func(r *http.Request) (*http.Response, error) {
				if r.URL.Path == "/v1/models" {
					return imageGatewayResponse(200, "application/json", `{"data":[{"id":"vision"`+tc.catalogFields+`}]}`), nil
				}
				var body map[string]any
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					return nil, err
				}
				content := obj(array(body["messages"])[0])["content"]
				if plain, ok := content.(string); ok {
					plainCalls++
					if plain != "material excerpt"+imageUnavailable || r.Header.Get("X-Magpie-Session") != "test-session" {
						t.Errorf("wrong fallback or visual session reused: %q", plain)
					}
					return imageGatewayResponse(200, "application/json", `{"choices":[{"finish_reason":"stop","message":{"content":"text excerpt checked"}}]}`), nil
				}
				visualCalls++
				contentType := "application/json"
				if tc.stream {
					contentType = "text/event-stream"
				}
				return imageGatewayResponse(tc.status, contentType, tc.errorBody), nil
			})}
			got, err := g.GenerateWithImages(context.Background(), "vision", "auto", "", "material excerpt", "test-session", []InputImage{{"material-id", "image/png", []byte("preview")}})
			if visualCalls > 1 || plainCalls > 1 || (visualCalls == 1) != tc.wantVision || (plainCalls == 1) != tc.wantPlain {
				t.Fatalf("unexpected visual/plain calls: %d/%d", visualCalls, plainCalls)
			}
			if tc.wantPlain && (err != nil || got != "text excerpt checked") || !tc.wantPlain && err == nil {
				t.Fatalf("unexpected response: %q, %v", got, err)
			}
		})
	}
}

func imageGatewayResponse(status int, contentType, content string) *http.Response {
	return &http.Response{StatusCode: status, Header: http.Header{"Content-Type": {contentType}}, Body: io.NopCloser(strings.NewReader(content))}
}
