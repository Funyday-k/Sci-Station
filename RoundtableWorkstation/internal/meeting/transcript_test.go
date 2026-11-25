package meeting

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/workspace"
)

func TestMarkdownTranscriptPreservesAttributionAndCompatibility(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("Markdown export must not call a model")
		return "", nil
	})
	if err := os.MkdirAll(project, 0700); err != nil {
		t.Fatal(err)
	}
	s, err := e.CreateConfigured("原始议题内容", project, []Member{{Model: "offline-model"}}, "review", AgendaInput{Title: "HOST_AGENDA_MARKER", Kind: "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	s.Agenda[0].Status = "done"
	s.Agenda[0].Source = "chair"
	s.Agenda[0].SourceRound = 1
	s.Agenda[0].SourceSeat = "member-1"
	s.Agenda[0].Reason = "主持人确认范围"
	s.Agenda[0].Revisions = []AgendaRevision{{Round: 2, Seat: "member-2", PreviousTitle: "旧议程标题", PreviousKind: "implementation", Reason: "发现范围变化"}}
	s.Agenda = append(s.Agenda, AgendaItem{AgendaInput: AgendaInput{Title: "DISCUSSION_AGENDA_MARKER", Kind: "implementation"}, ID: "agenda-two", Status: "pending", Source: "discussion", SourceRound: 3, SourceSeat: "member-2", Reason: "公开讨论提出"})
	if err = e.save(s); err != nil {
		t.Fatal(err)
	}

	const humanText = "HUMAN_SAVED_ORIGINAL_MARKER\n保留人工原文"
	if _, err = e.UserWrite(s.ID, "human.md", humanText, workspace.MissingVersion); err != nil {
		t.Fatal(err)
	}
	s, err = e.Get(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	s.Rounds = append(s.Rounds, Round{Number: 1, Preset: "review", Phase: "challenge", AgendaItemID: "agenda-two", Note: "ROUND_INSTRUCTION_MARKER", Turns: []Turn{{Seat: "member-2", Model: "offline-model", Status: "done", Text: "MODEL_PUBLIC_TEXT_MARKER", Changes: []workspace.Change{{Path: "model.md", Diff: "-before\n+MODEL_DIFF_MARKER\n+MODEL_SAVED_ORIGINAL_MARKER\n+模型原始内容", After: "version-digest"}}, Children: []Child{{Status: "done", Text: "PRIVATE_CHILD_MARKER"}}}}})
	if err = e.save(s); err != nil {
		t.Fatal(err)
	}

	markdown, err := e.Markdown(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"# 原始议题内容", "Project: " + filepath.Base(project), "Status: ready", "HOST_AGENDA_MARKER", "DISCUSSION_AGENDA_MARKER",
		"已完成", "主持人起草", "来源轮次：第 1 轮", "来源席位：member-1", "旧议程标题", "发现范围变化",
		"讨论发言", "来源轮次：第 3 轮", "来源席位：member-2", "## 第 1 轮 (Round 1)", "Mode:", "Stage:", "User instruction: ROUND_INSTRUCTION_MARKER",
		"MODEL_PUBLIC_TEXT_MARKER", "Changed: model.md", "MODEL_DIFF_MARKER", "+MODEL_SAVED_ORIGINAL_MARKER", "+模型原始内容", "人工保存", humanText,
	} {
		if !strings.Contains(markdown, want) {
			t.Errorf("Markdown transcript missing %q:\n%s", want, markdown)
		}
	}
	if strings.Contains(markdown, project) {
		t.Errorf("export exposed the absolute project path %q", project)
	}
	if strings.Contains(markdown, "PRIVATE_CHILD_MARKER") {
		t.Error("private child text leaked into the transcript")
	}
	if strings.Index(markdown, "模型修改（席位 member-2 · offline-model）") > strings.Index(markdown, "MODEL_DIFF_MARKER") {
		t.Error("model content lost its model attribution")
	}
	if strings.Index(markdown, "人工保存") > strings.Index(markdown, "HUMAN_SAVED_ORIGINAL_MARKER") {
		t.Error("UserWrite content lost its human attribution")
	}
}

func TestTranscriptCodeFenceDoesNotTruncateRawContent(t *testing.T) {
	content := "first\n```\nsecond"
	var b strings.Builder
	writeTranscriptCode(&b, "", content)
	if !strings.Contains(b.String(), content) || !strings.Contains(b.String(), "````") {
		t.Fatalf("raw content was not preserved with a safe fence: %q", b.String())
	}
}
