package desktop

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/research"
)

func withMinerTransport(t *testing.T, f conversionTransport) {
	t.Helper()
	prior := scientificHTTP
	scientificHTTP = &http.Client{Transport: f}
	t.Cleanup(func() { scientificHTTP = prior })
}

func minerFixtureResponse(body string) (*http.Response, error) {
	return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body))}, nil
}

func TestMinerSubmissionSurvivesLostCreateAndRestart(t *testing.T) {
	dir := t.TempDir()
	lab, p, _ := minerPaperFixture(t, dir)
	source := minerSourceID(p.ID, p.FileSHA256)
	path := filepath.Join(dir, "library", "mineru", source+".json")
	read := func() map[string]string {
		t.Helper()
		b, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		var fields map[string]any
		if err := json.Unmarshal(b, &fields); err != nil || fields["version"] != float64(1) {
			t.Fatal("invalid receipt", err)
		}
		result := map[string]string{}
		for k, v := range fields {
			switch k {
			case "version":
			case "state", "batch", "attempt":
				result[k] = v.(string)
			default:
				t.Fatalf("unexpected field %s", k)
			}
		}
		return result
	}
	posts, puts := 0, 0
	remoteState := "running"
	withMinerTransport(t, func(r *http.Request) (*http.Response, error) {
		switch r.Method {
		case "POST":
			posts++
			if read()["state"] != "creating" {
				t.Fatal("missing intent before submission")
			}
			if posts == 1 {
				return nil, errors.New("synthetic lost response")
			}
			return minerFixtureResponse(fmt.Sprintf(`{"data":{"batch_id":"fixture-%d","file_urls":["https://cdn.mineru.net/fixture"]}}`, posts))
		case "PUT":
			puts++
			if read()["state"] != "batch" || read()["batch"] != fmt.Sprintf("fixture-%d", posts) {
				t.Fatal("missing batch before transfer")
			}
			if puts == 1 {
				return nil, errors.New("synthetic upload timeout")
			}
			return minerFixtureResponse("")
		case "GET":
			return minerFixtureResponse(fmt.Sprintf(`{"data":{"extract_result":[{"data_id":"%s","state":"%s"}]}}`, source, remoteState))
		default:
			t.Fatal("unexpected method", r.Method)
			return nil, nil
		}
	})
	host := &apiServer{}
	start := func(batch, confirmation string, status int) map[string]string {
		t.Helper()
		w := httptest.NewRecorder()
		host.startMinerConversion(context.Background(), lab, w, p, "fixture-token", batch, confirmation)
		if w.Code != status {
			t.Fatalf("got %d want %d: %s", w.Code, status, w.Body)
		}
		return scienceWorkflowDecode[map[string]string](t, w.Body.Bytes())
	}
	reopen := func() {
		t.Helper()
		var err error
		lab, err = research.New(dir)
		if err != nil {
			t.Fatal(err)
		}
		host = &apiServer{}
	}

	start("", "", 502)
	reopen()
	first := start("", "", 409)["recovery"]
	if first == "" || first != read()["attempt"] || posts != 1 {
		t.Fatal("uncertain create was not preserved")
	}
	if result := start("", first, 202); result["batch"] != "fixture-2" || posts != 2 || puts != 1 {
		t.Fatal("missing known batch after interrupted upload", result)
	}
	reopen()
	if result := start("", "", 200); result["batch"] != "fixture-2" || posts != 2 || puts != 1 {
		t.Fatal("restart did not resume accepted upload", result)
	}
	remoteState = "waiting-file"
	second := start("", "", 409)["recovery"]
	start("", first, 409)
	if posts != 2 || second == "" || second == first {
		t.Fatal("stale confirmation was accepted")
	}
	if result := start("fixture-2", second, 201); result["batch"] != "fixture-3" || posts != 3 || puts != 2 {
		t.Fatal("confirmed replacement did not get a new batch", result)
	}
}

func TestMinerSubmissionSerializesAndRetriesSameSignedUpload(t *testing.T) {
	dir := t.TempDir()
	lab, p, _ := minerPaperFixture(t, dir)
	other, err := research.New(dir)
	if err != nil {
		t.Fatal(err)
	}
	postEntered, allowPost := make(chan struct{}), make(chan struct{})
	firstDone := make(chan *httptest.ResponseRecorder, 1)
	posts, puts := 0, 0
	withMinerTransport(t, func(r *http.Request) (*http.Response, error) {
		switch r.Method {
		case "POST":
			posts++
			close(postEntered)
			<-allowPost
			return minerFixtureResponse(`{"data":{"batch_id":"same","file_urls":["https://cdn.mineru.net/one"]}}`)
		case "PUT":
			puts++
			if puts == 1 {
				return nil, errors.New("synthetic lost transfer")
			}
			return minerFixtureResponse("")
		case "GET":
			return minerFixtureResponse(fmt.Sprintf(`{"data":{"extract_result":[{"data_id":"%s","state":"waiting-file"}]}}`, minerSourceID(p.ID, p.FileSHA256)))
		default:
			return nil, fmt.Errorf("unexpected request %s", r.Method)
		}
	})
	api := &apiServer{}
	go func() {
		w := httptest.NewRecorder()
		api.startMinerConversion(context.Background(), lab, w, p, "fixture", "", "")
		firstDone <- w
	}()
	<-postEntered
	w := httptest.NewRecorder()
	(&apiServer{}).startMinerConversion(context.Background(), other, w, p, "fixture", "", "")
	close(allowPost)
	first := <-firstDone
	if w.Code != 409 || first.Code != 202 {
		t.Fatal(w.Code, first.Code)
	}
	w = httptest.NewRecorder()
	api.startMinerConversion(context.Background(), lab, w, p, "fixture", "", "")
	if w.Code != 201 || posts != 1 || puts != 2 {
		t.Fatal("expected retry of original upload", w.Code, posts, puts)
	}
}
