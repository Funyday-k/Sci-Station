package meeting

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	boardCursorTTL = 3 * time.Second
	boardWaitLimit = 4 * time.Second
)

type textDeltaKey struct{}

// TextDeltaFromContext returns a callback only for a public parent request
// that can edit an existing page. A transport may send an empty string to
// withdraw all text from an abandoned attempt before starting a retry.
func TextDeltaFromContext(ctx context.Context) func(string) {
	fn, _ := ctx.Value(textDeltaKey{}).(func(string))
	return fn
}

type BoardCursor struct {
	Seat        string `json:"seat"`
	Round       int    `json:"round"`
	Seq         uint64 `json:"seq"`
	Op          string `json:"op"`
	TargetID    string `json:"target_id"`
	Field       string `json:"field"`
	Text        string `json:"text"`
	Title       string `json:"title,omitempty"`
	Offset      int    `json:"offset"`
	Complete    bool   `json:"complete"`
	BaseVersion int    `json:"base_version"`
}

type BoardPresence struct {
	SessionID string        `json:"session_id"`
	Seq       uint64        `json:"seq"`
	Cursors   []BoardCursor `json:"cursors"`
}

type cursorRequest struct {
	seat       string
	round      int
	base       map[string]int
	noteTitles map[int]string
	cursor     *BoardCursor
	expires    time.Time
}

type presenceRoom struct {
	seq        uint64
	changed    chan struct{}
	waiters    int
	requests   map[string]*cursorRequest
	current    map[string]int
	noteIDs    map[string]string
	allowNotes bool
}

type boardPresenceHub struct {
	mu    sync.Mutex
	seq   uint64
	rooms map[string]*presenceRoom
	last  map[string]uint64 // Only empty-room revisions, never candidate text.
}

func (p *boardPresenceHub) room(id string) *presenceRoom {
	r := p.rooms[id]
	if r == nil {
		if p.rooms == nil {
			p.rooms = make(map[string]*presenceRoom)
		}
		r = &presenceRoom{seq: p.last[id], changed: make(chan struct{}), requests: make(map[string]*cursorRequest)}
		p.rooms[id] = r
	}
	return r
}

func (p *boardPresenceHub) release(id string, r *presenceRoom) {
	if r.waiters != 0 || len(r.requests) != 0 {
		return
	}
	delete(p.rooms, id)
	// Keep the final empty revision across polls. Edits to a different
	// meeting must never trigger an immediate response on an idle page.
	if r.seq == 0 || p.last[id] == r.seq {
		return
	}
	if p.last == nil {
		p.last = map[string]uint64{}
	}
	if len(p.last) >= 64 && p.last[id] == 0 {
		oldest := ""
		for key, seq := range p.last {
			if oldest == "" || seq < p.last[oldest] {
				oldest = key
			}
		}
		delete(p.last, oldest)
	}
	p.last[id] = r.seq
}

func (p *boardPresenceHub) notify(r *presenceRoom) {
	p.seq++
	r.seq = p.seq
	close(r.changed)
	r.changed = make(chan struct{})
}

func (p *boardPresenceHub) withdraw(r *presenceRoom, req *cursorRequest) {
	if req.cursor != nil {
		req.cursor = nil
		p.notify(r)
	}
}

func (r *presenceRoom) accepts(c BoardCursor) bool {
	if c.Op == "add_note" {
		if !r.allowNotes {
			return false
		}
	} else if current, exists := r.current[c.TargetID]; !exists || current != c.BaseVersion {
		return false
	}
	if title := c.Title; title != "" {
		if owner := r.noteIDs[strings.ToLower(title)]; owner != "" && owner != c.TargetID {
			return false
		}
	}
	return true
}

// Called with the session's storage lock held. A local host save and the
// scheduler's existing cross-process revision watcher both invalidate stale
// previews. Presence itself never takes the storage lock or writes a record.
func (p *boardPresenceHub) sync(s *Session) {
	p.mu.Lock()
	defer p.mu.Unlock()
	r := p.rooms[s.ID]
	if r == nil || len(r.requests) == 0 {
		return
	}
	if s.CancelRequested || s.Status != "running" || s.Board.State != boardPublished || s.Report != nil {
		for seat, req := range r.requests {
			p.withdraw(r, req)
			delete(r.requests, seat)
		}
		p.release(s.ID, r)
		return
	}
	r.updateTargets(s.Board)
	for _, req := range r.requests {
		if req.cursor != nil && !r.accepts(*req.cursor) {
			p.withdraw(r, req)
		}
	}
}

func (r *presenceRoom) updateTargets(b MeetingBoard) {
	r.current = map[string]int{"board": b.Version}
	r.noteIDs = map[string]string{}
	for _, m := range b.Modules {
		r.current[m.ID] = m.Version
		if m.Kind == "note" {
			r.noteIDs[strings.ToLower(m.Title)] = m.ID
		}
	}
	r.allowNotes = canAddBoardNote(b.Modules)
}

func (p *boardPresenceHub) stream(ctx context.Context, s *Session, seat string, round int) (context.Context, func()) {
	if s.Board.State != boardPublished || s.Status != "running" || s.CancelRequested || s.Report != nil {
		return ctx, func() {}
	}
	p.mu.Lock()
	r := p.room(s.ID)
	r.updateTargets(s.Board)
	req := &cursorRequest{seat: seat, round: round, base: r.current, noteTitles: map[int]string{}}
	if old := r.requests[seat]; old != nil {
		p.withdraw(r, old)
	}
	r.requests[seat] = req
	p.mu.Unlock()
	emit := func(edit boardStreamEdit) {
		p.mu.Lock()
		defer p.mu.Unlock()
		if r.requests[seat] != req || ctx.Err() != nil {
			return
		}
		c, valid := cursorForEdit(req, s.Board, edit)
		if !valid || !r.accepts(c) {
			p.withdraw(r, req)
			return
		}
		req.expires = time.Now().Add(boardCursorTTL)
		if req.cursor != nil {
			c.Seq = req.cursor.Seq
			if c == *req.cursor {
				return
			}
		}
		p.notify(r)
		c.Seq = r.seq
		req.cursor = &c
	}
	var feedMu sync.Mutex
	parser := newBoardStream(s, emit)
	delta := func(text string) {
		feedMu.Lock()
		defer feedMu.Unlock()
		if ctx.Err() != nil {
			return
		}
		if text == "" {
			emit(boardStreamEdit{})
			p.mu.Lock()
			clear(req.noteTitles)
			p.mu.Unlock()
			parser = newBoardStream(s, emit)
			return
		}
		parser.Write(text)
	}
	closeRequest := func() {
		p.mu.Lock()
		defer p.mu.Unlock()
		if r.requests[seat] == req {
			p.withdraw(r, req)
			delete(r.requests, seat)
			p.release(s.ID, r)
		}
	}
	stop := context.AfterFunc(ctx, closeRequest)
	return context.WithValue(ctx, textDeltaKey{}, delta), func() {
		stop()
		closeRequest()
	}
}

func cursorForEdit(req *cursorRequest, b MeetingBoard, edit boardStreamEdit) (BoardCursor, bool) {
	c := BoardCursor{Seat: req.seat, Round: req.round, Op: edit.Op, Field: edit.Field, Text: edit.Text, Complete: edit.Complete}
	c.Offset = utf8.RuneCountInString(c.Text)
	if (c.Field != "title" && c.Field != "body") || c.Offset > maxBoardBody || (c.Field == "title" && c.Offset > maxBoardTitle) || strings.Contains(strings.ToLower(c.Text), "data:image") {
		return c, false
	}
	isNote := false
	switch c.Op {
	case "rename_board":
		if c.Field != "title" {
			return c, false
		}
		c.TargetID = "board"
	case "revise_module":
		m := b.module(edit.ModuleID)
		if m == nil || (c.Field == "body" && m.Kind != "note" && m.Kind != "materials") {
			return c, false
		}
		c.TargetID, isNote = m.ID, m.Kind == "note"
	case "add_note":
		if edit.Index < 0 || edit.Index >= maxBoardUpdates {
			return c, false
		}
		c.TargetID = fmt.Sprintf("pending-note:%d:%s:%d", req.round, req.seat, edit.Index)
		isNote = true
	default:
		return c, false
	}
	if isNote && c.Field == "title" && c.Complete {
		req.noteTitles[edit.Index] = strings.TrimSpace(c.Text)
	}
	if isNote {
		c.Title = req.noteTitles[edit.Index]
	}
	c.BaseVersion = req.base[c.TargetID]
	return c, true
}

// BoardPresence returns a replaceable snapshot. Calls with a matching revision
// wait for this meeting's next change or expiry, for at most four seconds.
func (e *Engine) BoardPresence(ctx context.Context, id string, after *uint64) (BoardPresence, error) {
	if err := ctx.Err(); err != nil {
		return BoardPresence{}, err
	}
	if _, err := e.diskRevision(id); err != nil {
		return BoardPresence{}, err
	}
	p := &e.presence
	p.mu.Lock()
	r := p.room(id)
	r.waiters++
	deadline := time.Now().Add(boardWaitLimit)
	defer func() {
		r.waiters--
		p.release(id, r)
		p.mu.Unlock()
	}()
	for {
		now := time.Now()
		wake := deadline
		out := BoardPresence{SessionID: id, Cursors: []BoardCursor{}}
		for _, req := range r.requests {
			if req.cursor == nil {
				continue
			}
			if !now.Before(req.expires) {
				p.withdraw(r, req)
				continue
			}
			out.Cursors = append(out.Cursors, *req.cursor)
			if req.expires.Before(wake) {
				wake = req.expires
			}
		}
		out.Seq = r.seq
		if after == nil || *after != out.Seq || !now.Before(deadline) {
			sort.Slice(out.Cursors, func(i, j int) bool { return out.Cursors[i].Seat < out.Cursors[j].Seat })
			return out, nil
		}
		changed := r.changed
		timer := time.NewTimer(time.Until(wake))
		p.mu.Unlock()
		select {
		case <-ctx.Done():
		case <-changed:
		case <-timer.C:
		}
		timer.Stop()
		p.mu.Lock()
		if err := ctx.Err(); err != nil {
			return BoardPresence{}, err
		}
	}
}
