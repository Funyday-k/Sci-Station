package research

import (
	"slices"
	"strings"
	"testing"
)

func TestPaperQuestionLocatesOnlyTheDisplayedPaperBody(t *testing.T) {
	s := newResearch(t, t.TempDir())
	project := createResearchProject(t, s, "Selected project")
	foreign := createResearchProject(t, s, "Different project")
	makePaper := func(title, projectID, body string, rank int) Paper {
		t.Helper()
		p, _, err := s.papers.create(PaperMetadata{
			Title: title, Abstract: "Unverified metadata abstract", ProjectIDs: []string{projectID},
			ProjectLinks: map[string]PaperProjectLink{projectID: {SortOrder: &rank}},
		}, "", "")
		if err != nil {
			t.Fatal(err)
		}
		if body != "" {
			p = decodeResearch[Paper](t, uploadMarkdownFixture(t, s, p, body, 200))
		}
		return p
	}
	first := makePaper("Recent control", project.ID, "# Results\nFigure 2. Distracting first caption.", 1)
	second := makePaper("Missing original", project.ID, "", 2)
	other := makePaper("Unrelated project result", foreign.ID, "# Results\nFigure 2. Foreign caption.", 1)
	const caption = "**Fig. 2.** Readable detector caption."
	const formula = "E_{\\odot}=kA(p_s-p_a)\\tag{2}"
	const body = "---\r\ntitle: Experiment\r\n---\r\n# Detector\r\n\r\n## Abstract\r\n😀 The experiment tests a bounded hypothesis.\r\n\r\n## Results\r\nFigure 2 shows a reference in body prose.\r\nFigure 20. A different caption.\r\n<!--\r\nFigure 2. Hidden comment.\r\n-->\r\n```text\r\nFigure 2. Code fence.\r\n```\r\n" + caption + "\r\n\r\n## Capture Rate\r\n$$C=kN\\tag{1}$$\r\n\r\n## Evaporation Rate\r\n$$\r\n" + formula + "\r\n$$\r\nwhere k is a rate coefficient.\r\n"
	target := makePaper("Referenced experiment", project.ID, body, 3)
	for _, tt := range []struct {
		text, want, heading string
		line                int
	}{
		{"第三篇论文的 Figure 2 讲了什么？", caption, "Results", 18},
		{"What is the abstract of the third paper?", "😀 The experiment tests a bounded hypothesis.", "Abstract", 7},
		{"第 3 篇论文的蒸发率公式是什么？", formula, "Evaporation Rate", 24},
		{"What is Equation (2) of the 3rd paper?", formula, "Evaporation Rate", 24},
	} {
		t.Run(tt.text, func(t *testing.T) {
			q := PaperQuestion{Text: tt.text, Project: project.ID, CurrentPaper: first.ID}
			got, err := s.SuggestPaperPassages(t.Context(), q)
			if err != nil || len(got) != 1 || got[0].ID != target.ID || !strings.Contains(got[0].Quote, tt.want) ||
				got[0].Heading != tt.heading || got[0].Line != tt.line || got[0].Hash != target.Markdown.Hash {
				t.Fatalf("wrong passage: %+v; %v", got, err)
			}
			if strings.Contains(tt.want, "tag{2}") && !strings.Contains(got[0].Quote, "where k is a rate coefficient.") {
				t.Fatal("formula excerpt omitted its adjacent definition")
			}
			original, err := s.WorkflowSource(t.Context(), project.ID, got[0].SourceLocation)
			if err != nil || !strings.HasPrefix(original.Text, got[0].Quote) || original.Line != got[0].Line {
				t.Fatalf("unverifiable excerpt: %+v; %v", original, err)
			}
		})
	}
	q := PaperQuestion{Text: "第三篇论文的图 2 说明什么？", Project: project.ID, VisiblePaperIDs: []string{target.ID, second.ID, first.ID}}
	got, err := s.SuggestPaperPassages(t.Context(), q)
	if err != nil || len(got) != 1 || got[0].ID != first.ID {
		t.Fatalf("sidebar did not honor displayed order: %+v; %v", got, err)
	}
	q.VisiblePaperIDs[2] = other.ID
	if got, err = s.SuggestPaperPassages(t.Context(), q); err == nil || len(got) != 0 {
		t.Fatal("read a paper from a different project", got, err)
	}
	q.VisiblePaperIDs = []string{}
	if _, err = s.SuggestPaperPassages(t.Context(), q); err == nil {
		t.Fatal("silently used the unfiltered order")
	}
	q.VisiblePaperIDs = nil
	for _, prompt := range []string{"第二篇论文的摘要", "第三篇论文的 Figure 27", "第五篇论文里的 Figure 2", "第三篇论文里的 neutrino decay 公式"} {
		q.Text = prompt
		if got, err = s.SuggestPaperPassages(t.Context(), q); err == nil || len(got) != 0 {
			t.Errorf("provided evidence for missing source of %q: %+v; %v", prompt, got, err)
		}
	}
	q.Text = "第三篇论文的 Figure 2"
	q.Selected = []PaperQuestionSelection{{SourceLocation: SourceLocation{Kind: "paper", ID: target.ID, Page: 4}, Quote: caption}}
	if got, err = s.SuggestPaperPassages(t.Context(), q); err != nil || len(got) != 0 {
		t.Fatalf("requested more evidence after explicit selection: %+v; %v", got, err)
	}
	q.Selected[0].ID = first.ID
	if got, err = s.SuggestPaperPassages(t.Context(), q); err != nil || !slices.ContainsFunc(got, func(p PaperPassage) bool { return p.ID == target.ID }) {
		t.Fatalf("an explicit excerpt from another paper hid the correct result: %+v; %v", got, err)
	}
}
