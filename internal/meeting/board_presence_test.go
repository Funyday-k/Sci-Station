package meeting

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestPublicBoardStreamIsEphemeralAndHostRevisionWins(t *testing.T) {
	var calls atomic.Int32
	first := make(chan struct{})
	resume := make(chan struct{})
	continued := make(chan struct{})
	settle := make(chan struct{})
	const id = "ada51bef245a485bb269da5ccd60be36"
	firstPart := `{"action":"say","text":"Measured lag went down.","board_updates":[{"op":"revise_module","module_id":"` + id + `","title":"Finding","body":"Measured lag`
	lastPart := ` went down."}]}`
	e, project := engine(t, func(ctx context.Context, _, _, _, _ string) (string, error) {
		calls.Add(1)
		write := TextDeltaFromContext(ctx)
		if write == nil {
			return "", errors.New("missing public stream")
		}
		write(firstPart)
		close(first)
		select {
		case <-resume:
		case <-ctx.Done():
			return "", ctx.Err()
		}
		write(lastPart)
		close(continued)
		select {
		case <-settle:
		case <-ctx.Done():
			return "", ctx.Err()
		}
		return firstPart + lastPart, nil
	})
	s, err := e.Create("Live editing", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	s, err = hostEdit(t, e, s.ID, `{"op":"add_note","module_id":"`+id+`","title":"Finding","body":"Saved body"}`)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.Start(s.ID, "Discuss", "", 0); err != nil {
		t.Fatal(err)
	}
	select {
	case <-first:
	case <-time.After(3 * time.Second):
		t.Fatal("stream did not reach its partial public edit")
	}
	view, err := e.BoardPresence(context.Background(), s.ID, nil)
	if err != nil || len(view.Cursors) != 1 {
		t.Fatal(view, err)
	}
	c := view.Cursors[0]
	if c.Seat != "codex" || c.Round != 1 || c.TargetID != id || c.Field != "body" || c.Text != "Measured lag" || c.Offset != 12 || c.BaseVersion != 1 || c.Complete {
		t.Fatal(c)
	}
	check, err := e.Get(s.ID)
	if err != nil || check.Board.module(id).Body != "Saved body" || check.Rounds[0].Turns[0].Text != "" || len(check.Rounds[0].Turns[0].ProposedBoardUpdates) != 0 {
		t.Fatal("preview entered the durable session or blind context", check, err)
	}
	data, err := os.ReadFile(filepath.Join(e.dir, s.ID+".json"))
	if err != nil || strings.Contains(string(data), "Measured lag") {
		t.Fatal("preview was written to disk", err)
	}
	other, err := New(e.dir, e.call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	separate, err := other.BoardPresence(context.Background(), s.ID, nil)
	if err != nil || len(separate.Cursors) != 0 {
		t.Fatal("new process replayed a cursor", separate, err)
	}
	// An unrelated target neither resets the request nor changes its version.
	if _, err := hostEdit(t, e, s.ID, `{"op":"rename_board","title":"Host page","expected_version":0}`); err != nil {
		t.Fatal(err)
	}
	current, err := e.BoardPresence(context.Background(), s.ID, nil)
	if err != nil || len(current.Cursors) != 1 || current.Seq != view.Seq {
		t.Fatal(current, err)
	}
	// Run the host edit through another backend sharing this archive. The
	// active engine's revision watcher must invalidate the cursor.
	if _, err := hostEdit(t, other, s.ID, `{"op":"revise_module","module_id":"`+id+`","body":"Host kept this","expected_version":1}`); err != nil {
		t.Fatal(err)
	}
	waitCtx, stop := context.WithTimeout(context.Background(), 2*time.Second)
	defer stop()
	current, err = e.BoardPresence(waitCtx, s.ID, &view.Seq)
	if err != nil || len(current.Cursors) != 0 || current.Seq == view.Seq {
		t.Fatal("foreign edit did not withdraw cursor", current, err)
	}
	close(resume)
	select {
	case <-continued:
	case <-time.After(2 * time.Second):
		t.Fatal("stream did not finish")
	}
	current, err = e.BoardPresence(context.Background(), s.ID, nil)
	if err != nil || len(current.Cursors) != 0 {
		t.Fatal("stale characters revived cursor", current, err)
	}
	close(settle)
	end := settled(t, e, s.ID)
	if end.Board.module(id).Body != "Host kept this" || end.Rounds[0].Turns[0].Text != "Measured lag went down." || calls.Load() != 1 {
		t.Fatal(end.Board, calls.Load())
	}
}

func TestBoardCursorRoomsAndExpiry(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		return "", errors.New("unexpected model")
	})
	s, err := e.Create("Multiple editors", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	empty, endEmpty := e.presence.stream(ctx, s, "codex", 1)
	endEmpty()
	if TextDeltaFromContext(empty) != nil {
		t.Fatal("unpublished page streamed")
	}
	other, err := e.Create("Other meeting", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	s.Board.State, s.Status = boardPublished, "running"
	type stream struct {
		push func(string)
		stop func()
	}
	start := func(seat string) stream {
		child, finish := e.presence.stream(ctx, s, seat, 1)
		return stream{TextDeltaFromContext(child), finish}
	}
	a, b := start("codex"), start("cursor")
	defer a.stop()
	defer b.stop()
	prefix := `{"action":"say","text":"Note","board_updates":[{"op":"rename_board","title":"`
	a.push(prefix + "主持")
	b.push(prefix + "測量")
	view, err := e.BoardPresence(ctx, s.ID, nil)
	if err != nil || len(view.Cursors) != 2 || view.Cursors[0].Seat != "codex" || view.Cursors[0].Offset != 2 || view.Cursors[1].Text != "測量" {
		t.Fatal(view, err)
	}
	foreign, err := e.BoardPresence(ctx, other.ID, nil)
	if err != nil || len(foreign.Cursors) != 0 || foreign.Seq != 0 {
		t.Fatal("cross-session cursor", foreign, err)
	}
	a.push("") // This transport attempt is abandoned; no suffix is reused.
	a.push(prefix + "retry")
	a.stop()
	a.push("late")
	view, err = e.BoardPresence(ctx, s.ID, nil)
	if err != nil || len(view.Cursors) != 1 || view.Cursors[0].Seat != "cursor" {
		t.Fatal(view, err)
	}
	b.push(`"}]}`)
	view, err = e.BoardPresence(ctx, s.ID, nil)
	if err != nil || len(view.Cursors) != 1 || !view.Cursors[0].Complete {
		t.Fatal(view, err)
	}
	// Exercise actual long-poll expiry without an arbitrary delay in the test.
	e.presence.mu.Lock()
	e.presence.rooms[s.ID].requests["cursor"].expires = time.Now().Add(25 * time.Millisecond)
	e.presence.mu.Unlock()
	waitCtx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	expired, err := e.BoardPresence(waitCtx, s.ID, &view.Seq)
	if err != nil || len(expired.Cursors) != 0 || expired.Seq == view.Seq {
		t.Fatal(expired, err)
	}
	cancelled, stop := context.WithCancel(ctx)
	stop()
	if _, err := e.BoardPresence(cancelled, s.ID, &expired.Seq); !errors.Is(err, context.Canceled) {
		t.Fatal("cancelled client continued polling", err)
	}
	b.stop()
	e.presence.mu.Lock()
	defer e.presence.mu.Unlock()
	if len(e.presence.rooms) != 0 {
		t.Fatalf("retained %d cursor rooms", len(e.presence.rooms))
	}
}

func TestFailedAndCancelledStreamsWithdrawWithoutCommitting(t *testing.T) {
	for _, outcome := range []string{"failed", "cancelled"} {
		t.Run(outcome, func(t *testing.T) {
			started, fail := make(chan struct{}), make(chan struct{})
			e, project := engine(t, func(ctx context.Context, _, _, _, _ string) (string, error) {
				cb := TextDeltaFromContext(ctx)
				if cb == nil {
					return "", errors.New("missing callback")
				}
				cb(`{"action":"say","text":"Public","board_updates":[{"op":"rename_board","title":"Unfinished`)
				close(started)
				select {
				case <-ctx.Done():
					return "", ctx.Err()
				case <-fail:
					return "", errors.New("transport interrupted")
				}
			})
			s, err := e.Create("Keep this title", project, []string{"codex"})
			if err != nil {
				t.Fatal(err)
			}
			s, err = hostEdit(t, e, s.ID, `{"op":"add_note","module_id":"abcdefabcdef4def8defabcdefabcdef","title":"Public note","body":"Body"}`)
			if err != nil {
				t.Fatal(err)
			}
			if _, err = e.Start(s.ID, "Discuss", "", 0); err != nil {
				t.Fatal(err)
			}
			select {
			case <-started:
			case <-time.After(2 * time.Second):
				t.Fatal("no model stream")
			}
			before, err := e.BoardPresence(context.Background(), s.ID, nil)
			if err != nil || len(before.Cursors) != 1 {
				t.Fatal(before, err)
			}
			if outcome == "cancelled" {
				if _, err = e.Cancel(s.ID); err != nil {
					t.Fatal(err)
				}
			} else {
				close(fail)
			}
			final := settled(t, e, s.ID)
			after, err := e.BoardPresence(context.Background(), s.ID, nil)
			if err != nil || len(after.Cursors) != 0 || before.Seq == after.Seq || final.Board.Title != s.Board.Title || final.Board.Version != s.Board.Version {
				t.Fatal(final.Board, after, err)
			}
		})
	}
}
