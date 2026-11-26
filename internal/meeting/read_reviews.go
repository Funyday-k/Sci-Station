// Workstation read reviews apply only to the action protocol. They cannot
// grant a CLI permission or approve an edit.
package meeting

import (
	"context"
	"errors"
	"fmt"
	"sync"
)

type ReadReview struct {
	ID      string `json:"id"`
	Seat    string `json:"seat"`
	ChildID string `json:"child_id,omitempty"`
	Action  string `json:"action"`
	Target  string `json:"target"`
}

type pendingReadReview struct {
	ReadReview
	ctx      context.Context
	decision chan bool
}

type readReviewQueue struct {
	mu      sync.Mutex
	pending map[string]*pendingReadReview
}

func (e *Engine) PendingReadReview(session string) *ReadReview {
	e.readReviews.mu.Lock()
	defer e.readReviews.mu.Unlock()
	if pending := e.readReviews.pending[session]; pending != nil && pending.ctx.Err() == nil {
		view := pending.ReadReview
		return &view
	}
	return nil
}

func (e *Engine) DecideReadReview(session, id string, allow bool) error {
	e.readReviews.mu.Lock()
	defer e.readReviews.mu.Unlock()
	pending := e.readReviews.pending[session]
	if pending == nil || pending.ID != id || pending.ctx.Err() != nil {
		return fmt.Errorf("%w: 此读取请求已结束，请刷新", ErrConflict)
	}
	delete(e.readReviews.pending, session)
	pending.decision <- allow
	return nil
}

func (e *Engine) waitForReadDecision(ctx context.Context, id, seat, child string, index int, action, target string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := e.recordReadReview(ctx, id, index, child, "read_approval_requested", target); err != nil {
		return err
	}
	queue := &e.readReviews
	pending := &pendingReadReview{ReadReview: ReadReview{
		ID: newID(), Seat: seat, ChildID: child, Action: action, Target: target,
	}, ctx: ctx, decision: make(chan bool, 1)}
	queue.mu.Lock()
	if queue.pending == nil {
		queue.pending = make(map[string]*pendingReadReview)
	}
	if queue.pending[id] != nil {
		queue.mu.Unlock()
		return errors.New("该会话已有待读取审批")
	}
	queue.pending[id] = pending
	queue.mu.Unlock()
	defer func() {
		queue.mu.Lock()
		if queue.pending[id] == pending {
			delete(queue.pending, id)
		}
		queue.mu.Unlock()
	}()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case allow := <-pending.decision:
		if err := e.check(ctx, id); err != nil {
			return err
		}
		event := "read_approval_allowed"
		if !allow {
			event = "read_approval_denied"
		}
		if err := e.recordReadReview(ctx, id, index, child, event, target); err != nil {
			return err
		}
		if !allow {
			return errors.New("用户拒绝了本次读取。请根据现有证据继续")
		}
		return nil
	}
}

func (e *Engine) recordReadReview(ctx context.Context, id string, index int, child, event, target string) error {
	return e.mutate(id, index, func(s *Session, turn *Turn) error {
		if s.CancelRequested || ctx.Err() != nil {
			return context.Canceled
		}
		addEvent(s, event, turn.Seat, target).ChildID = child
		return nil
	})
}
