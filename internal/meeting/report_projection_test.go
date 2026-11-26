package meeting

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestLongReportCoversEveryPublicTurnAndValidatesOnlyItsVisibleQuotes(t *testing.T) {
	m := reportMaterial{Topic: "根据会议材料回答", Seats: []string{"m1", "m2"}, Names: map[string]string{"m1": "甲", "m2": "乙"}}
	for i := 0; i < 100; i++ {
		id := fmt.Sprintf("R%d-T1", i+1)
		seat := m.Seats[i%2]
		src := reportSource{ID: id, Kind: "public", Seat: seat, Text: "开头原话【" + strings.Repeat("证据", 1500) + "仅在中间出现的材料" + strings.Repeat("研究", 1500) + "】末尾原话", Round: i + 1}
		m.Sources = append(m.Sources, src)
	}
	view, err := m.forReportPrompt()
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(view)
	if err != nil || len(data) > reportMaterialBudget || len(view.Sources) != len(m.Sources) || !strings.Contains(view.Coverage, "100 条提供首尾摘录") {
		t.Fatal(err, len(data), view.Coverage)
	}
	for i, s := range view.Sources {
		original := m.Sources[i]
		if s.ID != original.ID || !strings.HasPrefix(original.Text, s.Text) || !strings.HasSuffix(original.Text, s.Tail) || !utf8.ValidString(s.Text+s.Tail) || !s.Partial || !s.containsQuote("开头原话") || !s.containsQuote("末尾原话") {
			t.Fatalf("turn %d lost provenance or valid excerpts", i)
		}
		if s.containsQuote("仅在中间出现的材料") || s.containsQuote(s.Text+s.Tail) {
			t.Fatal("validated an unseen passage or joined noncontiguous excerpts")
		}
	}
	if strings.Contains(string(data), "仅在中间出现的材料") {
		t.Fatal("original leaked to projected JSON")
	}
	report := &Session{Topic: m.Topic, Report: &MeetingReport{AuthorSeat: "m1", ReviewerSeat: "m2", ReviewMode: "peer", Coverage: view.Coverage}}
	if !strings.Contains(reportDocument(report, m, "测试段落", true), view.Coverage) {
		t.Fatal("coverage not disclosed")
	}
}

func TestReportUsesLatestExplicitPositionAndPublicSeatLabels(t *testing.T) {
	s := &Session{Seats: []string{"member-1", "member-2", "member-3"}, Members: []Member{{ID: "member-1", Model: "model/a", Label: "甲"}, {ID: "member-2", Model: "model/a", Label: "甲"}, {ID: "member-3", Model: "model/b", Label: "乙"}}, Rounds: []Round{
		{Number: 1, Turns: []Turn{{Seat: "member-1", Model: "model/a", Status: "done", Text: "支持试点", Points: []DiscussionPoint{{ID: "p1", Text: "试点"}}, Positions: []Position{{PointID: "p1", Stance: "support", Reason: "支持试点"}}}}},
		{Number: 2, Turns: []Turn{{Seat: "member-1", Model: "model/a", Status: "done", Text: "看到追加预算，我现在反对了", Positions: []Position{{PointID: "p1", Stance: "oppose", Reason: "我现在反对了"}}}}},
	}}
	m := reportMaterials(s)
	out := m.appendices()
	for _, want := range []string{"甲 · 席位 1 · 不认同", "此前认同 [R1-T1]", "我现在反对了 [R2-T1]", "甲 · 席位 2 · 未表态", "乙 · 未表态"} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in %s", want, out)
		}
	}
	if strings.Contains(out, "member-") {
		t.Fatal("internal seat ID displayed")
	}
}

func TestReportAcceptsNaturalReviewAndOnlyBackedEmbeddedReferences(t *testing.T) {
	m := reportMaterial{Sources: []reportSource{{ID: "R1-T1", Kind: "public", Seat: "甲", Text: "先小规模试行"}}}
	review := `{"accuracy":"先区分讨论与决定 [R1-T1]。\n这是提议。","readability":"在开头写清条件 [R1]。","evidence":[{"id":"R1-T1","quote":"先小规模试行"}]}`
	got, err := renderReview(review, m)
	if err != nil || !strings.Contains(got, "这是提议") || !strings.Contains(got, "[R1-T1] 先小规模试行") {
		t.Fatal(got, err)
	}
	body := reportBody{Outcome: []reportParagraph{{Text: "提议小规模试行 [R1-T1]。\n仍待决定。", Evidence: []reportEvidence{{"R1-T1", "先小规模试行"}}}}}
	doc, err := body.render(m)
	if err != nil || strings.Count(doc, "[R1-T1]") != 2 {
		t.Fatal(doc, err)
	}
	body.Outcome[0].Text = "引用缺失 [R2-T1]。"
	if _, err = body.render(m); err == nil {
		t.Fatal("foreign citation accepted")
	}
	if _, err = renderReview(strings.Replace(review, "先小规模试行", "并不存在的原话", 1), m); err == nil {
		t.Fatal("fabricated review source")
	}
}

func TestReportMultilineEvidenceStaysInOneCitedItem(t *testing.T) {
	const quote = "23:00–28:00　自由讨论。\r\n- 28:00–30:00　总结。\n\n## 标题\u2028> 引文\u2029末句"
	const singleLine = "23:00–28:00　自由讨论。 - 28:00–30:00　总结。  ## 标题 > 引文 末句"
	src := reportSource{ID: "R1-T1", Kind: "public", Round: 1, Seat: "甲", Text: quote}
	m := reportMaterial{Sources: []reportSource{src}}
	body := reportBody{Outcome: []reportParagraph{{Text: "按时总结。", Evidence: []reportEvidence{{ID: src.ID, Quote: quote}}}}}
	rendered, err := body.render(m)
	if err != nil {
		t.Fatal(err)
	}
	_, appendix, found := strings.Cut(rendered, "## 引用原文\n\n")
	if !found || appendix != "- [R1-T1] 第 1 轮 · 甲 · "+singleLine+"\n" {
		t.Fatalf("citation markup splits or rewrites the quote: %q", appendix)
	}
	if !src.containsQuote(quote) || src.containsQuote(singleLine) || m.Sources[0].Text != quote {
		t.Fatal("display formatting changed the original evidence or verbatim validation")
	}

	reviewResponse, err := json.Marshal(map[string]any{"accuracy": "核对了时间。", "readability": "保留时间顺序。", "evidence": body.Outcome[0].Evidence})
	if err != nil {
		t.Fatal(err)
	}
	notes, err := renderReview(string(reviewResponse), m)
	if err != nil || !strings.Contains(notes, "[R1-T1] "+quote) {
		t.Fatalf("plain-text review notes lost the original quotation: %q, %v", notes, err)
	}
}

func TestReportTitleOmitsChineseFullStopBeforeSeparator(t *testing.T) {
	s := &Session{Topic: "制定读书会流程。", Report: &MeetingReport{}}
	if doc := reportDocument(s, reportMaterial{}, "正文。", false); !strings.HasPrefix(doc, "# 制定读书会流程 · 会议报告（草稿）\n") || !strings.Contains(doc, "正文。") || s.Topic != "制定读书会流程。" {
		t.Fatal(doc)
	}
}
