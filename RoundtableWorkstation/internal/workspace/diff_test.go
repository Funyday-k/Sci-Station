package workspace

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func numberedDiffText(n int) string {
	var out strings.Builder
	for i := 1; i <= n; i++ {
		fmt.Fprintf(&out, "line %03d\n", i)
	}
	return out.String()
}

func applySystemPatch(t *testing.T, before, after, patch string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "file.txt"), []byte(before), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "/usr/bin/patch", "-s", "-p1")
	cmd.Dir = dir
	cmd.Stdin = strings.NewReader(patch)
	cmd.Env = []string{"LC_ALL=C", "LANG=C", "PATH=/usr/bin:/bin"}
	if body, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("system patch rejected output: %v %s\n%s", err, body, patch)
	}
	actual, err := os.ReadFile(filepath.Join(dir, "file.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if string(actual) != after {
		t.Fatalf("applied patch did not reconstruct new bytes: got=%q want=%q", actual, after)
	}
}

func TestDiffSeparatedEditsKeepUnchangedLines(t *testing.T) {
	before := numberedDiffText(120)
	after := strings.ReplaceAll(strings.ReplaceAll(before, "line 005\n", "changed first\n"), "line 110\n", "changed last\n")
	t.Setenv("PATH", "") // No Git, shell helpers or developer tools are required.
	patch, err := unifiedDiff("file.txt", before, after)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Count(patch, "@@ -") != 2 {
		t.Fatalf("expected two distant hunks: %s", patch)
	}
	if added, removed := ParseLineTotals(patch); added != 2 || removed != 2 {
		t.Fatalf("counted unchanged middle lines: +%d -%d", added, removed)
	}
	if strings.Contains(patch, "line 050") {
		t.Fatal("unchanged middle of file was included")
	}
	applySystemPatch(t, before, after, patch)
	again, err := NormalizePatch(patch)
	if err != nil || again != patch {
		t.Fatalf("minimal patch did not remain byte-identical: %v", err)
	}
}

func TestDiffByteAccurateEOFAndOffsets(t *testing.T) {
	for _, tc := range []struct {
		name, before, after string
		added, removed      int
	}{
		{"create", "", "a\n", 1, 0},
		{"remove", "a\n", "", 0, 1},
		{"empty to missing newline", "", "a", 1, 0},
		{"remove missing newline", "a", "", 0, 1},
		{"replace missing newline", "old", "new", 1, 1},
		{"add terminal newline", "same", "same\n", 1, 1},
		{"remove terminal newline", "same\n", "same", 1, 1},
		{"CRLF", "one\r\nold\r\nthree\r\n", "one\r\nnew\r\nthree\r\n", 1, 1},
		{"insert first", "keep\nend\n", "new\nkeep\nend\n", 1, 0},
		{"insert end", "keep\nend\n", "keep\nend\nnew\n", 1, 0},
		{"delete first", "old\nkeep\nend\n", "keep\nend\n", 0, 1},
		{"delete end", "keep\nend\nold\n", "keep\nend\n", 0, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			patch, err := unifiedDiff("file.txt", tc.before, tc.after)
			if err != nil {
				t.Fatal(err)
			}
			added, removed := ParseLineTotals(patch)
			if added != tc.added || removed != tc.removed {
				t.Fatalf("+%d -%d, want +%d -%d\n%s", added, removed, tc.added, tc.removed, patch)
			}
			applySystemPatch(t, tc.before, tc.after, patch)
			normalized, err := NormalizePatch(patch)
			if err != nil || normalized != patch {
				t.Fatalf("canonical EOF diff changed: %v\n%s", err, normalized)
			}
		})
	}
}

func oldReplacementPatch(headers string, oldStart, newStart int, before, after string) string {
	var out strings.Builder
	out.WriteString(headers)
	fmt.Fprintf(&out, "@@ -%d,%d +%d,%d @@\n", oldStart, diffLineCount(before), newStart, diffLineCount(after))
	for _, part := range []struct {
		mark byte
		text string
	}{{'-', before}, {'+', after}} {
		for pos := 0; pos < len(part.text); {
			line, next := nextDiffLine(part.text, pos)
			emitDiffLine(&out, part.mark, line)
			pos = next
		}
	}
	return out.String()
}

func TestNormalizeLegacyLargeHunkPreservesLabelsAndGlobalOffsets(t *testing.T) {
	before := numberedDiffText(60)
	after := strings.ReplaceAll(strings.ReplaceAll(before, "line 005\n", "first change\n"), "line 055\n", "last change\n")
	headers := "diff --git a/renamed doc.md b/renamed doc.md\n--- a/renamed doc.md\toriginal timestamp\n+++ b/renamed doc.md\tnew timestamp\n"
	legacy := oldReplacementPatch(headers, 101, 201, before, after)
	if added, removed := ParseLineTotals(legacy); added != 60 || removed != 60 {
		t.Fatal("legacy fixture was not coarse")
	}
	got, err := NormalizePatch(legacy)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(got, headers) {
		t.Fatal("original filenames or preamble were changed")
	}
	for _, header := range []string{"@@ -102,7 +202,7 @@", "@@ -152,7 +252,7 @@"} {
		if !strings.Contains(got, header) {
			t.Fatalf("incorrect original-file offset, missing %s:\n%s", header, got)
		}
	}
	if added, removed := ParseLineTotals(got); added != 2 || removed != 2 {
		t.Fatalf("normalized counts +%d -%d", added, removed)
	}
	second, err := NormalizePatch(got)
	if err != nil || second != got {
		t.Fatal("normalization was not idempotent")
	}
}

func TestNormalizeLegacyRetainsEOFAndCanBeApplied(t *testing.T) {
	before, after := "keep\nold\nmiddle\nend-old", "keep\nnew\nmiddle\nend-new"
	legacy := oldReplacementPatch("--- a/file.txt\n+++ b/file.txt\n", 1, 1, before, after)
	got, err := NormalizePatch(legacy)
	if err != nil {
		t.Fatal(err)
	}
	if added, removed := ParseLineTotals(got); added != 2 || removed != 2 {
		t.Fatalf("EOF counts +%d -%d:\n%s", added, removed, got)
	}
	if strings.Count(got, "\\ No newline at end of file") != 2 {
		t.Fatalf("lost end-of-file markers: %s", got)
	}
	applySystemPatch(t, before, after, got)
}

func TestNormalizeOverlongContextAndMinimalMoves(t *testing.T) {
	before := numberedDiffText(60)
	after := strings.ReplaceAll(strings.ReplaceAll(before, "line 005\n", "first\n"), "line 055\n", "last\n")
	var long strings.Builder
	long.WriteString("--- a/file.txt\n+++ b/file.txt\n@@ -1,60 +1,60 @@\n")
	for pos := 0; pos < len(before); {
		line, next := nextDiffLine(before, pos)
		pos = next
		switch line {
		case "line 005\n":
			long.WriteString("-line 005\n+first\n")
		case "line 055\n":
			long.WriteString("-line 055\n+last\n")
		default:
			long.WriteString(" " + line)
		}
	}
	got, err := NormalizePatch(long.String())
	if err != nil {
		t.Fatal(err)
	}
	if strings.Count(got, "@@ -") != 2 {
		t.Fatalf("did not split long unchanged context: %s", got)
	}
	applySystemPatch(t, before, after, got)
	move := "--- a/file.txt\n+++ b/file.txt\n@@ -1,4 +1,4 @@ keep function label\n-a\n b\n c\n+a\n d\n"
	_, bodyPos := nextDiffLine(move, 0)
	_, bodyPos = nextDiffLine(move, bodyPos)
	header, next := nextDiffLine(move, bodyPos)
	h, _ := parseDiffRange(header)
	body, err := parseDiffHunk(move, next, h)
	if err != nil || body.needsNormalize {
		t.Fatalf("minimal move was unnecessarily scheduled for recomputation: %v", err)
	}
	same, err := NormalizePatch(move)
	if err != nil || same != move {
		t.Fatal("already minimal move was rewritten")
	}
}

func TestNormalizeMultipleFilesAndInsertionOffset(t *testing.T) {
	a := "--- a/first.txt\n+++ b/first.txt\n@@ -20 +20,2 @@\n old\n+new\n"
	before := numberedDiffText(20)
	after := strings.Replace(before, "line 010\n", "changed\n", 1)
	second := oldReplacementPatch("--- a/second.txt\n+++ b/second.txt\n", 51, 52, before, after)
	got, err := NormalizePatch(a + second)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(got, a) || !strings.Contains(got, "--- a/second.txt\n+++ b/second.txt\n") || !strings.Contains(got, "@@ -57,7 +58,7 @@") {
		t.Fatalf("multi-file metadata or offsets changed:\n%s", got)
	}
	if added, removed := ParseLineTotals(got); added != 2 || removed != 1 {
		t.Fatalf("multi-file totals +%d -%d", added, removed)
	}
}

func TestLineTotalsExcludeHeadersEOFAndIncompleteHunks(t *testing.T) {
	patch := "--- a/file.txt\n+++ b/file.txt\n@@ -1,2 +1,2 @@\n--- old body\n-++ old body\n+++ new body\n+-- new body\n\\ No newline at end of file\n"
	if added, removed := ParseLineTotals(patch); added != 2 || removed != 2 {
		t.Fatalf("body resembling a filename header was lost: +%d -%d", added, removed)
	}
	for _, bad := range []string{
		"--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n-old\n+new\n",
		"@@ -0,1 +1,1 @@\n-old\n+new\n",
		"@@ -999999999999999999999999,1 +1,1 @@\n-old\n+new\n",
		"@@ -1,1 +1,1 @@\n-old\n\\ No newline at end of file\n\\ No newline at end of file\n+new\n",
	} {
		got, err := NormalizePatch(bad)
		if err == nil || got != bad {
			t.Fatal("malformed history was silently changed or accepted")
		}
	}
	if added, removed := ParseLineTotals("@@ -1,2 +1,2 @@\n-old\n+new\n"); added != 0 || removed != 0 {
		t.Fatal("incomplete hunk was counted")
	}
}

func TestDiffMaximumFilesAndLargeOutput(t *testing.T) {
	before := strings.Repeat("\n", MaxFileBytes)
	after := strings.Repeat("x\n", MaxFileBytes/2)
	start := time.Now()
	patch, err := unifiedDiff("file.txt", before, after)
	if err != nil {
		t.Fatal(err)
	}
	if len(patch) <= 4<<20 {
		t.Fatal("fixture did not exercise output larger than 4 MiB")
	}
	if added, removed := ParseLineTotals(patch); added != MaxFileBytes/2 || removed != MaxFileBytes {
		t.Fatalf("max-size totals +%d -%d", added, removed)
	}
	for _, texts := range [][2]string{{"", before}, {before, ""}} {
		patch, err := unifiedDiff("file.txt", texts[0], texts[1])
		if err != nil {
			t.Fatal(err)
		}
		if len(patch) <= 4<<20 {
			t.Fatal("max-size pure insertion/deletion was unexpectedly truncated")
		}
	}
	if time.Since(start) > 8*time.Second {
		t.Fatal("linear maximum-size diff path was unexpectedly slow")
	}
	if _, err := unifiedDiff("file.txt", "", strings.Repeat("x", MaxFileBytes+1)); err == nil {
		t.Fatal("oversize input was accepted")
	}
}

func TestDiffContextCancellationBeforeAnyTemporaryWork(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := unifiedDiffContext(ctx, "file.txt", "same\nold\n", "same\nnew\n"); err == nil {
		t.Fatal("cancelled diff context continued")
	}
}

func TestDiffMinimalCountsAgainstSmallIndependentLCS(t *testing.T) {
	random := rand.New(rand.NewSource(19))
	for trial := 0; trial < 60; trial++ {
		makeLines := func() []string {
			lines := make([]string, random.Intn(18))
			for i := range lines {
				lines[i] = []string{"a\n", "b\n", "c\n", "重复\r\n"}[random.Intn(4)]
			}
			if len(lines) > 0 && random.Intn(3) == 0 {
				last := len(lines) - 1
				lines[last] = strings.TrimSuffix(lines[last], "\n")
			}
			return lines
		}
		oldLines, newLines := makeLines(), makeLines()
		table := make([][]int, len(oldLines)+1)
		for i := range table {
			table[i] = make([]int, len(newLines)+1)
		}
		for i := 1; i <= len(oldLines); i++ {
			for j := 1; j <= len(newLines); j++ {
				if oldLines[i-1] == newLines[j-1] {
					table[i][j] = table[i-1][j-1] + 1
				} else {
					table[i][j] = max(table[i-1][j], table[i][j-1])
				}
			}
		}
		patch, err := unifiedDiff("file.txt", strings.Join(oldLines, ""), strings.Join(newLines, ""))
		if err != nil {
			t.Fatal(err)
		}
		added, removed := ParseLineTotals(patch)
		common := table[len(oldLines)][len(newLines)]
		if added != len(newLines)-common || removed != len(oldLines)-common {
			t.Fatalf("trial %d: nonminimal +%d -%d; LCS=%d\n%s", trial, added, removed, common, patch)
		}
		normalized, err := NormalizePatch(patch)
		if err != nil || normalized != patch {
			t.Fatalf("trial %d: minimal system patch scheduled for unnecessary rewrite: %v\n%s", trial, err, patch)
		}
	}
}

func TestBSDDiffRepeatedLinesAndMissingFinalLFRegression(t *testing.T) {
	// BSD diff -d originally matched the final c to c\n, then repaired LF
	// metadata, missing a preservable b line. Exact byte-aware LCS is three
	// lines, hence +10/-2 rather than the old +11/-3.
	before := "重复\r\n重复\r\nb\nb\nc"
	after := "a\nb\n重复\r\na\n重复\r\na\na\nc\n重复\r\na\n重复\r\n重复\r\nb\n"
	patch, err := unifiedDiff("file.txt", before, after)
	if err != nil {
		t.Fatal(err)
	}
	if added, removed := ParseLineTotals(patch); added != 10 || removed != 2 {
		t.Fatalf("BSD EOF alignment regression: +%d -%d\n%s", added, removed, patch)
	}
	if strings.Contains(patch, diffEOFSentinel) {
		t.Fatal("private EOF alignment sentinel leaked into output")
	}
	applySystemPatch(t, before, after, patch)
	legacy := oldReplacementPatch("--- a/file.txt\n+++ b/file.txt\n", 1, 1, before, after)
	normalized, err := NormalizePatch(legacy)
	if err != nil {
		t.Fatal(err)
	}
	if added, removed := ParseLineTotals(normalized); added != 10 || removed != 2 {
		t.Fatalf("legacy EOF alignment regression: +%d -%d", added, removed)
	}
	applySystemPatch(t, before, after, normalized)
}

func TestMaximumUnterminatedLineIsNotCountedAsOversize(t *testing.T) {
	oldText, newText := strings.Repeat("x", MaxFileBytes), strings.Repeat("y", MaxFileBytes)
	for _, texts := range [][2]string{{oldText, newText}, {"", newText}, {oldText, ""}} {
		patch, err := unifiedDiff("file.txt", texts[0], texts[1])
		if err != nil {
			t.Fatal(err)
		}
		added, removed := ParseLineTotals(patch)
		wantAdded, wantRemoved := 0, 0
		if texts[1] != "" {
			wantAdded = 1
		}
		if texts[0] != "" {
			wantRemoved = 1
		}
		if added != wantAdded || removed != wantRemoved {
			t.Fatalf("EOF transport newline was treated as file content: +%d -%d", added, removed)
		}
		normalized, err := NormalizePatch(patch)
		if err != nil || normalized != patch {
			t.Fatalf("valid 2 MiB unterminated line rejected: %v", err)
		}
	}
}
