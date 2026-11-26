// Line diffs are generated independently of Git. Actual project writes never
// receive a coarse replacement patch when a bounded minimal diff cannot finish.
package workspace

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const diffTimeout = 5 * time.Second

// Two 2 MiB files can produce over 8 MiB with line prefixes alone, and many
// isolated changes add hunk headers. Keep ample space for all supported input.
const maxDiffBytes = 32*MaxFileBytes + 16*1024

// BSD diff aligns line contents before accounting for missing final LF. With
// repeated lines this can produce a larger edit script than byte-aware LCS.
// This control byte is excluded by validText; it exists only in private
// snapshots, making unterminated final lines distinct during alignment.
const diffEOFSentinel = "\x1fROUNDTABLE_EOF\x1f"

func diffSnapshot(text string) string {
	if text != "" && !strings.HasSuffix(text, "\n") {
		return text + diffEOFSentinel + "\n"
	}
	return text
}
func restoreDiffEOF(patch string) string {
	var out strings.Builder
	for pos := 0; pos < len(patch); {
		line, next := nextDiffLine(patch, pos)
		pos = next
		if len(line) > 0 && strings.ContainsRune(" +-", rune(line[0])) && strings.HasSuffix(line, diffEOFSentinel+"\n") {
			emitDiffLine(&out, line[0], strings.TrimSuffix(line[1:], diffEOFSentinel+"\n"))
		} else {
			out.WriteString(line)
		}
	}
	return out.String()
}

func nextDiffLine(text string, pos int) (string, int) {
	if pos >= len(text) {
		return "", len(text)
	}
	if end := strings.IndexByte(text[pos:], '\n'); end >= 0 {
		return text[pos : pos+end+1], pos + end + 1
	}
	return text[pos:], len(text)
}
func diffLineCount(text string) int {
	if text == "" {
		return 0
	}
	n := strings.Count(text, "\n")
	if !strings.HasSuffix(text, "\n") {
		n++
	}
	return n
}
func emitDiffLine(out *strings.Builder, mark byte, line string) {
	out.WriteByte(mark)
	out.WriteString(line)
	if !strings.HasSuffix(line, "\n") {
		out.WriteString("\n\\ No newline at end of file\n")
	}
}

func disjointLines(a, b string) bool {
	if a == "" || b == "" {
		return true
	}
	// Most small edits retain the first line; avoid building an index then.
	firstA, _ := nextDiffLine(a, 0)
	firstB, _ := nextDiffLine(b, 0)
	if firstA == firstB {
		return false
	}
	if len(a) > len(b) {
		a, b = b, a
	}
	set := map[string]struct{}{}
	for pos := 0; pos < len(a); {
		line, next := nextDiffLine(a, pos)
		set[line] = struct{}{}
		pos = next
	}
	for pos := 0; pos < len(b); {
		line, next := nextDiffLine(b, pos)
		if _, ok := set[line]; ok {
			return false
		}
		pos = next
	}
	return true
}

// A whole replacement is minimal only if no complete line can be retained.
// Pure insertion/deletion and disjoint files use a linear in-process path.
func directDiff(path, before, after string) string {
	oldCount, newCount := diffLineCount(before), diffLineCount(after)
	oldStart, newStart := 1, 1
	if oldCount == 0 {
		oldStart = 0
	}
	if newCount == 0 {
		newStart = 0
	}
	var out strings.Builder
	out.Grow(len(before) + len(after) + oldCount + newCount + 128)
	fmt.Fprintf(&out, "--- a/%s\n+++ b/%s\n@@ -%d,%d +%d,%d @@\n", path, path, oldStart, oldCount, newStart, newCount)
	for _, part := range []struct {
		mark byte
		text string
	}{{'-', before}, {'+', after}} {
		if part.text == "" {
			continue
		}
		// Insert a prefix after each interior LF. The standard library writes
		// contiguous chunks and sizes its allocation once, even for huge hunks.
		out.WriteByte(part.mark)
		body, terminated := strings.CutSuffix(part.text, "\n")
		out.WriteString(strings.ReplaceAll(body, "\n", "\n"+string(part.mark)))
		out.WriteByte('\n')
		if !terminated {
			out.WriteString("\\ No newline at end of file\n")
		}
	}
	return out.String()
}

type diffOutput struct {
	bytes.Buffer
	overflow bool
}

func (b *diffOutput) Write(p []byte) (int, error) {
	n := len(p)
	left := maxDiffBytes - b.Len()
	if left < n {
		b.overflow = true
		if left > 0 {
			_, _ = b.Buffer.Write(p[:left])
		}
	} else {
		_, _ = b.Buffer.Write(p)
	}
	return n, nil
}

func unifiedDiff(path, before, after string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), diffTimeout)
	defer cancel()
	return unifiedDiffContext(ctx, path, before, after)
}
func unifiedDiffContext(ctx context.Context, path, before, after string) (string, error) {
	if before == after {
		return "", nil
	}
	if len(before) > MaxFileBytes || len(after) > MaxFileBytes {
		return "", errors.New("diff inputs exceed the 2 MiB file limit")
	}
	if strings.Contains(before, diffEOFSentinel) || strings.Contains(after, diffEOFSentinel) {
		return "", errors.New("diff input contains unsupported control bytes")
	}
	if err := ctx.Err(); err != nil {
		return "", errors.New("line diff timed out")
	}
	if disjointLines(before, after) {
		return directDiff(path, before, after), nil
	}
	if err := ctx.Err(); err != nil {
		return "", errors.New("line diff timed out")
	}
	dir, err := os.MkdirTemp("", "roundtable-diff-")
	if err != nil {
		return "", errors.New("cannot create the private diff workspace")
	}
	defer os.RemoveAll(dir)
	oldFile, newFile := filepath.Join(dir, "before"), filepath.Join(dir, "after")
	if err = os.WriteFile(oldFile, []byte(diffSnapshot(before)), 0600); err != nil {
		return "", errors.New("cannot stage the old diff snapshot")
	}
	if err = os.WriteFile(newFile, []byte(diffSnapshot(after)), 0600); err != nil {
		return "", errors.New("cannot stage the new diff snapshot")
	}
	// /usr/bin/diff is built into macOS; it is unrelated to Xcode's Git shim.
	// -d requests a minimal edit script; -a retains all text/EOF distinctions.
	cmd := exec.CommandContext(ctx, "/usr/bin/diff", "-a", "-d", "-U", "3", "-L", "a/"+path, "-L", "b/"+path, oldFile, newFile)
	cmd.Dir = dir
	cmd.Env = []string{"LC_ALL=C", "LANG=C", "PATH=/usr/bin:/bin"}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = 500 * time.Millisecond
	var output diffOutput
	cmd.Stdout = &output
	err = cmd.Run()
	if ctx.Err() != nil {
		return "", errors.New("line diff timed out; the project file was not written")
	}
	if output.overflow {
		return "", errors.New("line diff exceeded the bounded output size")
	}
	var status *exec.ExitError
	if err != nil && (!errors.As(err, &status) || status.ExitCode() != 1) {
		return "", errors.New("the system line diff is unavailable or failed; the project file was not written")
	}
	if err == nil && output.Len() == 0 {
		return "", errors.New("system diff returned no changes for different input")
	}
	return formatDiffHunks(restoreDiffEOF(output.String()), 0, 0)
}

var diffHunkHeader = regexp.MustCompile(`^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@(.*)$`)

type diffRange struct {
	oldStart, oldCount, newStart, newCount int
	suffix                                 string
}

func parseDiffRange(line string) (diffRange, bool) {
	var h diffRange
	m := diffHunkHeader.FindStringSubmatch(strings.TrimSuffix(line, "\n"))
	if m == nil {
		return h, false
	}
	values := []int{0, 1, 0, 1}
	for i := 0; i < 4; i++ {
		if m[i+1] != "" {
			n, err := strconv.Atoi(m[i+1])
			if err != nil {
				return h, false
			}
			values[i] = n
		}
	}
	h = diffRange{values[0], values[1], values[2], values[3], m[5]}
	if (h.oldCount > 0 && h.oldStart == 0) || (h.newCount > 0 && h.newStart == 0) {
		return diffRange{}, false
	}
	return h, true
}
func formatDiffHunks(patch string, oldOffset, newOffset int) (string, error) {
	var out strings.Builder
	for pos := 0; pos < len(patch); {
		line, next := nextDiffLine(patch, pos)
		pos = next
		if h, ok := parseDiffRange(line); ok {
			maxInt := int(^uint(0) >> 1)
			if h.oldStart > maxInt-oldOffset || h.newStart > maxInt-newOffset {
				return "", errors.New("diff line number overflow")
			}
			fmt.Fprintf(&out, "@@ -%d,%d +%d,%d @@%s\n", h.oldStart+oldOffset, h.oldCount, h.newStart+newOffset, h.newCount, h.suffix)
		} else {
			out.WriteString(line)
		}
	}
	return out.String(), nil
}

type parsedDiffHunk struct {
	end                int
	oldText, newText   string
	oldParts, newParts []string
	added, removed     int
	needsNormalize     bool
}

// parseDiffHunk uses declared hunk counts, so body lines resembling file headers
// remain real additions/deletions, and malformed/truncated hunks are not counted.
func parseDiffHunk(patch string, bodyPos int, h diffRange, collectLines bool) (parsedDiffHunk, error) {
	var result parsedDiffHunk
	oldUsed, newUsed, oldBytes, newBytes := 0, 0, 0, 0
	oldBlock, newBlock := 0, 0
	block := false
	seenEdit := false
	contextRun := 0
	previous := byte(0)
	previousHasLF := false
	finishBlock := func() {
		if !block {
			return
		}
		a, b := result.oldParts[oldBlock:], result.newParts[newBlock:]
		if len(a) > len(b) {
			a, b = b, a
		}
		index := map[string]struct{}{}
		for _, line := range a {
			index[line] = struct{}{}
		}
		for _, line := range b {
			if _, ok := index[line]; ok {
				result.needsNormalize = true
				break
			}
		}
		block = false
	}
	pos := bodyPos
	for {
		if pos >= len(patch) {
			if oldUsed != h.oldCount || newUsed != h.newCount {
				return result, errors.New("truncated unified diff hunk")
			}
			break
		}
		line, next := nextDiffLine(patch, pos)
		if strings.TrimRight(line, "\r\n") == "\\ No newline at end of file" {
			if previous == 0 {
				return result, errors.New("misplaced diff end-of-file marker")
			}
			if !previousHasLF {
				return result, errors.New("invalid end-of-file marker")
			}
			if previous == '-' || previous == ' ' {
				if collectLines {
					last := len(result.oldParts) - 1
					result.oldParts[last] = strings.TrimSuffix(result.oldParts[last], "\n")
				}
				oldBytes--
			}
			if previous == '+' || previous == ' ' {
				if collectLines {
					last := len(result.newParts) - 1
					result.newParts[last] = strings.TrimSuffix(result.newParts[last], "\n")
				}
				newBytes--
			}
			previous = 0
			pos = next
			continue
		}
		if oldUsed == h.oldCount && newUsed == h.newCount {
			break
		}
		if len(line) == 0 {
			return result, errors.New("invalid empty diff body line")
		}
		mark, text := line[0], line[1:]
		switch mark {
		case ' ':
			if oldUsed >= h.oldCount || newUsed >= h.newCount {
				return result, errors.New("diff context exceeds declared line counts")
			}
			finishBlock()
			contextRun++
			if !seenEdit && contextRun > 3 {
				result.needsNormalize = true
			}
			if collectLines {
				result.oldParts = append(result.oldParts, text)
				result.newParts = append(result.newParts, text)
			}
			oldUsed++
			newUsed++
			oldBytes += len(text)
			newBytes += len(text)
		case '-', '+':
			if collectLines && !block {
				if seenEdit && contextRun > 6 {
					result.needsNormalize = true
				}
				oldBlock, newBlock = len(result.oldParts), len(result.newParts)
				block = true
			}
			seenEdit = true
			contextRun = 0
			if mark == '-' {
				if oldUsed >= h.oldCount {
					return result, errors.New("diff deletion exceeds declared line count")
				}
				if collectLines {
					result.oldParts = append(result.oldParts, text)
				}
				oldUsed++
				oldBytes += len(text)
				result.removed++
			} else {
				if newUsed >= h.newCount {
					return result, errors.New("diff addition exceeds declared line count")
				}
				if collectLines {
					result.newParts = append(result.newParts, text)
				}
				newUsed++
				newBytes += len(text)
				result.added++
			}
		default:
			return result, errors.New("invalid unified diff body")
		}
		// A physical patch line adds LF before its EOF marker. Allow that
		// single transport byte until the next marker has been consumed.
		if oldBytes > MaxFileBytes+1 || newBytes > MaxFileBytes+1 {
			return result, errors.New("historical hunk exceeds the 2 MiB file limit")
		}
		previous = mark
		previousHasLF = strings.HasSuffix(text, "\n")
		pos = next
	}
	finishBlock()
	if oldBytes > MaxFileBytes || newBytes > MaxFileBytes {
		return result, errors.New("historical hunk exceeds the 2 MiB file limit")
	}
	if contextRun > 3 {
		result.needsNormalize = true
	}
	result.end = pos
	return result, nil
}

// NormalizePatch repairs old coarse hunks using only their included before/after
// fragments. File headers/preamble and original global line offsets are retained.
// Standard minimal hunks return byte-for-byte unchanged without invoking diff.
// On any failure, the original patch is returned together with the error.
func NormalizePatch(patch string) (string, error) {
	if len(patch) > maxDiffBytes {
		return patch, errors.New("historical patch exceeds the bounded diff size")
	}
	ctx, cancel := context.WithTimeout(context.Background(), diffTimeout)
	defer cancel()
	var out strings.Builder
	changed := false
	for pos := 0; pos < len(patch); {
		if ctx.Err() != nil {
			return patch, errors.New("historical diff normalization timed out")
		}
		line, next := nextDiffLine(patch, pos)
		h, ok := parseDiffRange(line)
		if !ok {
			if strings.HasPrefix(line, "@@ ") {
				return patch, errors.New("invalid unified diff hunk header")
			}
			out.WriteString(line)
			pos = next
			continue
		}
		body, err := parseDiffHunk(patch, next, h, true)
		if err != nil {
			return patch, err
		}
		if !body.needsNormalize {
			out.WriteString(patch[pos:body.end])
			pos = body.end
			continue
		}
		before, after := strings.Join(body.oldParts, ""), strings.Join(body.newParts, "")
		repaired, err := unifiedDiffContext(ctx, "fragment", before, after)
		if err != nil {
			return patch, err
		}
		if repaired != "" {
			// Drop temporary labels; keep the original file's exact headers.
			_, start := nextDiffLine(repaired, 0)
			_, start = nextDiffLine(repaired, start)
			oldOffset, newOffset := h.oldStart, h.newStart
			if h.oldCount > 0 {
				oldOffset--
			}
			if h.newCount > 0 {
				newOffset--
			}
			repaired, err = formatDiffHunks(repaired[start:], oldOffset, newOffset)
			if err != nil {
				return patch, err
			}
			out.WriteString(repaired)
		}
		changed = true
		pos = body.end
	}
	if !changed {
		return patch, nil
	}
	return out.String(), nil
}

// ParseLineTotals counts additions/removals inside complete unified hunks only.
// Headers, context and EOF markers are excluded. Normalize legacy patches first;
// this parser does not reinterpret the edit script or run external commands.
func ParseLineTotals(patch string) (added, removed int) {
	for pos := 0; pos < len(patch); {
		line, next := nextDiffLine(patch, pos)
		h, ok := parseDiffRange(line)
		if !ok {
			pos = next
			continue
		}
		body, err := parseDiffHunk(patch, next, h, false)
		if err != nil {
			pos = next
			continue
		}
		added += body.added
		removed += body.removed
		pos = body.end
	}
	return added, removed
}
