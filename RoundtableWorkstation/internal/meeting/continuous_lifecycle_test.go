package meeting

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
)

func TestContinuousPauseDuringReviewCanResumeWithoutRepeatingRound(t *testing.T) {
	entered := make(chan struct{})
	var calls atomic.Int32
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		if strings.Contains(deliberation.InstructionsFrom(ctx), "CONTINUOUS_REVIEW") {
			if calls.Add(1) == 1 {
				close(entered)
				<-ctx.Done()
				return "", ctx.Err()
			}
			return `{"decision":"complete","reason":"第二项已交付","progress":true,"evidence":[{"id":"R2-T1","quote":"已核对"}]}`, nil
		}
		return say("已核对"), nil
	})
	s, err := e.Create("task", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	opts := RoundOptions{Preset: "work", Continuous: &ContinuousConfig{MaxRounds: 3}}
	if _, err = e.StartRound(s.ID, "", "", 0, opts); err != nil {
		t.Fatal(err)
	}
	select {
	case <-entered:
	case <-time.After(4 * time.Second):
		t.Fatal("review did not start")
	}
	if _, err = e.StartRound(s.ID, "", "", 1, opts); !errors.Is(err, ErrConflict) {
		t.Fatalf("duplicate run = %v", err)
	}
	caller, err := New(e.dir, e.call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = caller.Cancel(s.ID); err != nil {
		t.Fatal(err)
	}
	stopped := settled(t, e, s.ID)
	if stopped.Continuous.Status != "paused" || len(stopped.Rounds) != 1 || !stopped.CancelRequested {
		t.Fatalf("bad pause %+v", stopped.Continuous)
	}
	if err = e.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	// Starting from disk must keep the previous round and outcome.
	reopened, err := New(e.dir, e.call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = reopened.StartRound(s.ID, "", "", 1, opts); err != nil {
		t.Fatal(err)
	}
	final := settled(t, reopened, s.ID)
	if final.Continuous.Status != "completed" || len(final.Rounds) != 2 || calls.Load() != 2 {
		t.Fatalf("bad resume %+v", final.Continuous)
	}
	for _, r := range final.Rounds {
		n := 0
		for _, ev := range final.Events {
			if ev.Type == "round_finished" && ev.Round == r.Number {
				n++
			}
		}
		if n != 1 {
			t.Fatalf("round %d finalized %d times", r.Number, n)
		}
	}
}

func TestContinuousStopsAtStallLimitAndRoundLimit(t *testing.T) {
	for _, test := range []struct {
		name          string
		limit, rounds int
		reason        string
	}{{"round limit", 1, 1, "上限"}, {"no progress", 5, 2, "新进展"}} {
		t.Run(test.name, func(t *testing.T) {
			e, p := engine(t, func(ctx context.Context, _, _, _, _ string) (string, error) {
				if strings.Contains(deliberation.InstructionsFrom(ctx), "CONTINUOUS_REVIEW") {
					return `{"decision":"continue","reason":"还缺原始测量","next":"寻找测量证据","progress":false,"evidence":[]}`, nil
				}
				return say("没有找到更多依据"), nil
			})
			s, err := e.Create("task", p, []string{"codex"})
			if err != nil {
				t.Fatal(err)
			}
			_, err = e.StartRound(s.ID, "", "", 0, RoundOptions{Continuous: &ContinuousConfig{MaxRounds: test.limit}})
			if err != nil {
				t.Fatal(err)
			}
			final := settled(t, e, s.ID)
			if len(final.Rounds) != test.rounds || final.Continuous.Status != "paused" || !strings.Contains(final.Continuous.Reason, test.reason) {
				t.Fatalf("unexpected stop %+v", final.Continuous)
			}
		})
	}
}
