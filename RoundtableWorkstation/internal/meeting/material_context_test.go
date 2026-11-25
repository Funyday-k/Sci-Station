package meeting

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestSessionMaterialLimitAndContextBudget(t *testing.T) {
	e, _ := engine(t, func(context.Context, string, string, string, string) (string, error) {
		t.Error("binding attachments made a model request")
		return "", nil
	})
	var ids []string
	for i := 0; i <= maxMaterialsPerSession; i++ {
		content := strings.Repeat("甲", maxPromptExcerptRunes+1)
		m, err := e.StoreMaterial(fmt.Sprintf("%d.txt", i), strings.NewReader(content))
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, m.ID)
	}
	s := &Session{}
	for start := 0; start < maxMaterialsPerSession; start += maxMaterialIDsPerRequest {
		batch := ids[start:min(start+maxMaterialIDsPerRequest, maxMaterialsPerSession)]
		if _, err := e.bindMaterials(s, batch); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := e.bindMaterials(s, ids[maxMaterialsPerSession:]); err == nil || len(s.Materials) != maxMaterialsPerSession {
		t.Fatal("session attachment limit did not reject the new selection atomically")
	}
	lastBound := ids[maxMaterialsPerSession-1]
	selected, err := e.bindMaterials(s, []string{lastBound})
	if err != nil || !slices.Equal(selected, []string{lastBound}) {
		t.Fatalf("could not select existing attachment at the bound: %v, %v", selected, err)
	}
	materials := s.materialReferences(selected)
	prompt := materialPromptContext(materials)
	if len(prompt) != maxMaterialsPerSession || prompt[0].ID != lastBound {
		t.Fatal("prompt did not prioritize the current selection and retain older material references")
	}
	count := 0
	for _, m := range prompt {
		length := utf8.RuneCountInString(m.Excerpt)
		if length == 0 || length > maxPromptExcerptRunes || !m.ExcerptShortened || m.ReadStatus != MaterialReadText {
			t.Fatalf("wrong text availability for %q: %d runes, status %q, shortened %v", m.Name, length, m.ReadStatus, m.ExcerptShortened)
		}
		count += length
	}
	if count > maxPromptMaterialRunes {
		t.Fatalf("attachment context exceeded its budget: %d", count)
	}
}

func TestSelectedScientificPassageKeepsTailAndLocator(t *testing.T) {
	text := "Sci-Station · 论文原文摘录 v1\n{\"page\":9}\n\n" + strings.Repeat("文", 2800)
	result := materialPromptContext([]Material{{ID: "passage", Name: "paper.txt", ReadStatus: MaterialReadText, Excerpt: text}})
	if len(result) != 1 || result[0].ExcerptShortened || result[0].Excerpt != text {
		t.Fatal("a single reader selection must reach the model with its full locator and text")
	}
}
