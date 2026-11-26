package meeting

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/deliberation"
)

func TestVisualMaterialsRejectInvalidOriginalsAndBoundPreviews(t *testing.T) {
	e := &Engine{dir: t.TempDir()}
	wide := image.NewNRGBA(image.Rect(0, 0, maxVisualPreviewSide*2, 8))
	wide.SetNRGBA(0, 0, color.NRGBA{R: 200, A: 255})
	var pngData, jpegData, oversized bytes.Buffer
	if err := png.Encode(&pngData, wide); err != nil {
		t.Fatal(err)
	}
	if err := jpeg.Encode(&jpegData, wide, nil); err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(&oversized, image.NewNRGBA(image.Rect(0, 0, maxVisualOriginalSide+1, 1))); err != nil {
		t.Fatal(err)
	}
	corrupt := pngData.Bytes()[:pngData.Len()-16]
	materials := []Material{
		storeVisualFixture(t, e, "photo.png", "image/png", jpegData.Bytes()),
		storeVisualFixture(t, e, "corrupt.png", "image/png", corrupt),
		storeVisualFixture(t, e, "oversized.png", "image/png", oversized.Bytes()),
	}
	for range maxVisualMaterials + 1 {
		materials = append(materials, storeVisualFixture(t, e, "layout.png", "image/png", pngData.Bytes()))
	}
	materials[4] = storeVisualFixture(t, e, "layout.jpg", "image/jpeg", jpegData.Bytes())
	got := ModelVisualMaterials(e.withVisualMaterials(context.Background(), materials))
	if len(got) != maxVisualMaterials || got[0].ID != materials[3].ID || got[1].ID != materials[4].ID {
		t.Fatalf("preview selection did not reject invalid originals or respect its count budget: %d", len(got))
	}
	total := 0
	for _, m := range got {
		preview, format, err := image.Decode(bytes.NewReader(m.Data))
		if err != nil || preview.Bounds().Dx() != maxVisualPreviewSide || preview.Bounds().Dy() != 4 || "image/"+format != m.MIME {
			t.Fatalf("invalid scaled preview %s: %v", m.MIME, err)
		}
		if len(m.Data) > maxVisualPreviewBytes {
			t.Fatalf("preview larger than the byte limit: %d", len(m.Data))
		}
		total += len(m.Data)
	}
	first, err := png.Decode(bytes.NewReader(got[0].Data))
	if err != nil || color.NRGBAModel.Convert(first.At(0, 0)) != (color.NRGBA{R: 200, A: 255}) || total > maxVisualRequestBytes {
		t.Fatalf("preview changed the visual evidence or exceeded the total byte limit: %d, %v", total, err)
	}
}

func TestVisualMaterialsAreScopedToDraftAndPublicFirstRequest(t *testing.T) {
	var agendaID, roundID string
	var publicCalls int
	e, project := engine(t, func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		images := ModelVisualMaterials(ctx)
		_, session := ModelRequest(ctx)
		if strings.Contains(prompt, "data:image/") {
			return "", fmt.Errorf("raw image URL was in meeting text")
		}
		if !strings.Contains(deliberation.InstructionsFrom(ctx), "Direct visual observations require an actual image preview in this request") {
			return "", fmt.Errorf("model was not told which images it can inspect")
		}
		switch {
		case strings.HasSuffix(session, "-agenda"):
			if len(images) != 1 || images[0].ID != agendaID || !strings.Contains(prompt, agendaID) {
				return "", fmt.Errorf("wrong visual agenda input")
			}
			return `{"agenda":[{"title":"Assess the two colors","kind":"discussion"}]}`, nil
		case strings.Contains(deliberation.InstructionsFrom(ctx), "PRIVATE read-only child"):
			if len(images) != 0 {
				return "", fmt.Errorf("image leaked into private context")
			}
			return say("private comparison"), nil
		default:
			publicCalls++
			if publicCalls == 1 {
				if len(images) != 2 || images[0].ID != roundID || images[1].ID != agendaID {
					return "", fmt.Errorf("wrong visual images or priority for the first public request")
				}
				return `{"action":"delegate","task":"consider the meeting topic"}`, nil
			}
			if len(images) != 0 {
				return "", fmt.Errorf("image leaked into a subsequent action request")
			}
			return say("public comparison"), nil
		}
	})
	var data bytes.Buffer
	if err := png.Encode(&data, image.NewNRGBA(image.Rect(0, 0, 8, 8))); err != nil {
		t.Fatal(err)
	}
	agenda := storeVisualFixture(t, e, "initial.png", "image/png", data.Bytes())
	round := storeVisualFixture(t, e, "current.png", "image/png", data.Bytes())
	unrelated := storeVisualFixture(t, e, "unrelated.png", "image/png", data.Bytes())
	agendaID, roundID = agenda.ID, round.ID
	if _, err := e.CreateConfiguredWithMaterials("Different topic", project, []Member{{Model: "provider/model"}}, "review", nil, []string{unrelated.ID}); err != nil {
		t.Fatal(err)
	}
	s, err := e.CreateConfiguredWithMaterials("Study colors", project, []Member{{Model: "provider/model"}}, "review", nil, []string{agenda.ID})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	s = waitForAgenda(t, e, s.ID)
	if s.AgendaDraftStatus != "ready" {
		t.Fatalf("image agenda request failed: %s", s.AgendaDraftError)
	}
	if _, err = e.StartRound(s.ID, "Compare the colors", "", 0, RoundOptions{MaterialIDs: []string{round.ID}}); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	turn := s.Rounds[0].Turns[0]
	if turn.Text != "public comparison" || len(turn.Children) != 1 || turn.Children[0].Text != "private comparison" {
		t.Fatalf("visual call isolation did not hold: %+v", turn)
	}
	saved, err := os.ReadFile(filepath.Join(e.dir, s.ID+".json"))
	if err != nil || bytes.Contains(saved, []byte("data:image/")) || bytes.Contains(saved, []byte(base64.StdEncoding.EncodeToString(data.Bytes()))) || bytes.Contains(saved, []byte(unrelated.ID)) {
		t.Fatalf("visual payload or unrelated materials leaked into meeting storage: %v", err)
	}
}

func storeVisualFixture(t *testing.T, e *Engine, name, mime string, data []byte) Material {
	t.Helper()
	m := Material{ID: newMaterialID(), Name: name, MIME: mime, Size: int64(len(data)), ReadStatus: MaterialReadNoText}
	dir := filepath.Join(e.dir, "materials", m.ID)
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	metadata, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "metadata.json"), metadata, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "original"), data, 0600); err != nil {
		t.Fatal(err)
	}
	return m
}
