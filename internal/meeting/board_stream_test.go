package meeting

import (
	"slices"
	"strings"
	"testing"
	"unicode/utf8"
)

func streamFixture() *Session {
	return &Session{
		Board: MeetingBoard{State: boardPublished, Title: "Original", Modules: []BoardModule{
			{ID: "agenda", Kind: "agenda", BoardText: BoardText{Title: "Agenda"}},
			{ID: "materials", Kind: "materials", BoardText: BoardText{Title: "Materials"}},
		}},
		Materials: []Material{{ID: "actual-attachment", Name: "review.txt"}},
	}
}

func TestBoardStreamDecodesEachByteAndSignalsComplete(t *testing.T) {
	raw := `{"action":"say","text":"例子：这句🙂有\n换行和\"引号\"。","points":[{"text":"例子"}],"board_updates":[{"op":"rename_board","title":"更新为\u4e2d文"},{"op":"add_note","title":"记\ud83d\ude42","body":"这句\ud83d\ude42有\n换行和\"引号\"。"}]}`
	expect := []boardStreamEdit{
		{Op: "rename_board", Field: "title", Text: "更新为中文", Index: 0, Complete: true},
		{Op: "add_note", Field: "title", Text: "记🙂", Index: 1, Complete: true},
		{Op: "add_note", Field: "body", Text: "这句🙂有\n换行和\"引号\"。", Index: 1, Complete: true},
	}
	var edits []boardStreamEdit
	stream := newBoardStream(streamFixture(), func(e boardStreamEdit) { edits = append(edits, e) })
	for i := range len(raw) {
		stream.Write(raw[i : i+1])
	}
	var completed []boardStreamEdit
	incomplete := 0
	for _, e := range edits {
		if e.Op == "" || !utf8.ValidString(e.Text) || strings.ContainsRune(e.Text, utf8.RuneError) {
			t.Fatalf("unexpected or broken decoded update: %+v", e)
		}
		if e.Complete {
			completed = append(completed, e)
		} else {
			incomplete++
			if !slices.ContainsFunc(expect, func(final boardStreamEdit) bool {
				return final.Op == e.Op && final.Field == e.Field && final.Index == e.Index && strings.HasPrefix(final.Text, e.Text)
			}) {
				t.Errorf("not a prefix of the intended field: %+v", e)
			}
		}
	}
	if !slices.Equal(completed, expect) || incomplete < 6 {
		t.Fatalf("wanted completions %+v with incremental prefixes, got %+v", expect, edits)
	}
}

func TestBoardStreamWaitsForActionTargetAndCitation(t *testing.T) {
	var edits []boardStreamEdit
	stream := newBoardStream(streamFixture(), func(e boardStreamEdit) { edits = append(edits, e) })
	stream.Write(`{"text":"Evidence: only the excerpt was checked.","board_updates":[{"title":"Inspection","body":"only the excerpt was checked","op":"revise_module",`)
	if len(edits) != 0 {
		t.Fatal("published before action or target confirmation")
	}
	stream.Write(`"module_id":"materials","material_ids":["actual-attachment"]}],`)
	if len(edits) != 0 {
		t.Fatal("published before action was confirmed")
	}
	stream.Write(`"action":"say"}`)
	want := []boardStreamEdit{
		{Op: "revise_module", ModuleID: "materials", Field: "title", Text: "Inspection", Complete: true},
		{Op: "revise_module", ModuleID: "materials", Field: "body", Text: "only the excerpt was checked", Complete: true},
	}
	if !slices.Equal(edits, want) {
		t.Fatalf("late selectors lost their buffered fields: %+v", edits)
	}

	edits = nil
	stream = newBoardStream(streamFixture(), func(e boardStreamEdit) { edits = append(edits, e) })
	stream.Write(`{"action":"say","text":"The excerpt was checked.","board_updates":[{"op":"revise_module","module_id":"materials","title":"Evidence","body":"excerpt was checked",`)
	if len(edits) != 1 || edits[0].Field != "title" {
		t.Fatalf("material body escaped before its citation: %+v", edits)
	}
	stream.Write(`"material_ids":["actual-attachment"]}]}`)
	if len(edits) != 2 || edits[1].Field != "body" || !edits[1].Complete {
		t.Fatalf("cited material body was not released: %+v", edits)
	}
}

func TestBoardStreamIgnoresPrivateWrappedAndInvalidCandidates(t *testing.T) {
	const valid = `{"action":"say","text":"Public statement","board_updates":[{"op":"rename_board","title":"Visible"}]}`
	tests := map[string]string{
		"free preface":         "Consider this example: " + valid,
		"markdown code":        "```json\n" + valid + "\n```",
		"array wrapper":        "[" + valid + "]",
		"object wrapper":       `{"example":` + valid + "}",
		"quoted wrapper":       marshal(valid),
		"action text example":  `{"action":"say","text":` + marshal(valid) + "}",
		"nested example":       `{"action":"say","text":"Public","points":[` + valid + "]}",
		"read":                 `{"text":"Secret","board_updates":[{"op":"rename_board","title":"Secret"}],"action":"read"}`,
		"write":                `{"action":"write","path":"file","text":"Private source code","board_updates":[{"op":"rename_board","title":"Secret"}]}`,
		"delegate":             `{"action":"delegate","task":"Private","board_updates":[{"op":"rename_board","title":"Secret"}]}`,
		"invalid reference":    `{"action":"say","text":"Public","board_updates":[{"op":"add_note","title":"Visible","body":"Public","material_ids":["fake"]}]}`,
		"invalid module":       `{"action":"say","text":"Public","board_updates":[{"op":"revise_module","module_id":"another-room","title":"Visible"}]}`,
		"forbidden body":       `{"action":"say","text":"Public","board_updates":[{"op":"revise_module","module_id":"agenda","title":"Visible","body":"Public"}]}`,
		"forbidden action key": `{"action":"say","text":"Public","analysis":"Private","board_updates":[{"op":"rename_board","title":"Visible"}]}`,
		"malformed surrogate":  `{"action":"say","text":"Public","board_updates":[{"op":"rename_board","title":"Wrong\ud800!"}]}`,
		"non-verbatim body":    `{"action":"say","text":"Public","board_updates":[{"op":"add_note","title":"Visible","body":"Private"}]}`,
		"conflicting reply":    valid + valid,
		"beyond title limit":   strings.Replace(valid, "Visible", strings.Repeat("题", maxBoardTitle+1), 1),
		"beyond board limit":   strings.Replace(valid, "[{", "["+strings.Repeat(" ", maxBoardJSON)+"{", 1),
		"beyond nesting":       strings.Replace(valid, `"board_updates"`, `"points":`+strings.Repeat("[", maxBoardStreamDepth)+strings.Repeat("]", maxBoardStreamDepth)+`,"board_updates"`, 1),
	}
	for name, raw := range tests {
		t.Run(name, func(t *testing.T) {
			stream := newBoardStream(streamFixture(), func(e boardStreamEdit) { t.Errorf("unexpected edit: %+v", e) })
			stream.Write(raw)
		})
	}
}

func TestBoardStreamWithdrawsOnInvalidLateData(t *testing.T) {
	const start = `{"action":"say","text":"Public text","board_updates":[{"op":"add_note","title":"Vi`
	invalidSuffixes := []string{
		`sible","title":"Conflict"`,
		`sible","body":"Public text"}],"action":"delegate"`,
		`sible","body":"Public text"}]} {"action":"read"`,
		`sible","body":"Public secret`,
		`sible","body":"Public text","raw_html":"<x>"`,
		`sible dAtA\u003aImAgE/png;base64,NEVER_PREVIEW_THIS`,
		strings.Repeat("a", maxBoardTitle),
		strings.Repeat(" ", maxBoardStreamBytes),
	}
	for index, suffix := range invalidSuffixes {
		var edits []boardStreamEdit
		stream := newBoardStream(streamFixture(), func(e boardStreamEdit) { edits = append(edits, e) })
		stream.Write(start)
		stream.Write(suffix)
		stream.Write(`"}]} {"action":"say","text":"Late"}`)
		if len(edits) != 2 || edits[0].Text != "Vi" || edits[0].Complete || edits[1] != (boardStreamEdit{}) {
			t.Errorf("case %d did not withdraw safely: %+v", index, edits)
		}
	}
}

func TestBoardStreamKeepsFirstEligibleUpdateForATarget(t *testing.T) {
	var edits []boardStreamEdit
	stream := newBoardStream(streamFixture(), func(e boardStreamEdit) { edits = append(edits, e) })
	stream.Write(`{"action":"say","text":"Public","board_updates":[{"op":"rename_board","title":"First"},{"op":"rename_board","title":"Second"},{"op":"revise_module","module_id":"agenda","title":"New agenda"}]}`)
	want := []boardStreamEdit{
		{Op: "rename_board", Field: "title", Text: "First", Index: 0, Complete: true},
		{Op: "revise_module", ModuleID: "agenda", Field: "title", Text: "New agenda", Index: 2, Complete: true},
	}
	if !slices.Equal(edits, want) {
		t.Fatalf("conflicting edit was rendered: %+v", edits)
	}
}

func TestBoardStreamDoesNotClaimUnchangedModule(t *testing.T) {
	var edits []boardStreamEdit
	stream := newBoardStream(streamFixture(), func(e boardStreamEdit) { edits = append(edits, e) })
	stream.Write(`{"action":"say","text":"Public","board_updates":[{"op":"revise_module","module_id":"agenda","title":"Agenda"},{"op":"revise_module","module_id":"agenda","title":"New agenda"}]}`)
	want := []boardStreamEdit{{Op: "revise_module", ModuleID: "agenda", Field: "title", Text: "New agenda", Index: 1, Complete: true}}
	if !slices.Equal(edits, want) {
		t.Fatalf("unchanged proposal took the editable target: %+v", edits)
	}
}

func TestBoardStreamExplicitMaterialBodyDeletionWaitsForClosingQuote(t *testing.T) {
	s := streamFixture()
	module := s.Board.module("materials")
	module.Body, module.MaterialIDs = "Prior material interpretation.", []string{"actual-attachment"}
	var edits []boardStreamEdit
	stream := newBoardStream(s, func(e boardStreamEdit) { edits = append(edits, e) })
	stream.Write(`{"action":"say","text":"Review the attachment again.","board_updates":[{"op":"revise_module","module_id":"materials","title":"Review again","body":"`)
	if len(edits) != 1 || edits[0].Field != "title" {
		t.Fatalf("an unfinished body was treated as a deletion: %+v", edits)
	}
	stream.Write(`"}]}`)
	want := boardStreamEdit{Op: "revise_module", ModuleID: "materials", Field: "body", Complete: true}
	if len(edits) != 2 || edits[1] != want {
		t.Fatalf("explicit deletion did not complete: %+v", edits)
	}
}
