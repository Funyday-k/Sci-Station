package meeting

import (
	"context"
	"crypto/sha256"
	"fmt"
	"unicode/utf8"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/deliberation"
)

// LabRunRecord adds metadata to the existing round record. Settings, host
// instructions, citations and decisions keep their existing owners.
type LabRunRecord struct {
	Version      int    `json:"version"`
	RetryOfRound int    `json:"retry_of_round,omitempty"`
	PromptDigest string `json:"prompt_digest,omitempty"`
}

func validateRoundNote(note string) error {
	if credentials.ContainsSecret(note) {
		return credentials.ErrSecretInPrompt
	}
	if utf8.RuneCountInString(note) > maxInputCharacters {
		return fmt.Errorf("本轮消息最多 %d 个字符", maxInputCharacters)
	}
	return nil
}

func (s *Session) CanRetryLabRun() bool {
	if len(s.Seats) != 1 || s.Continuous.active() || s.Report != nil || s.AgendaDraftStatus == "drafting" ||
		(s.LabThread != nil && s.LabThread.ArchivedAt != "") {
		return false
	}
	if len(s.Rounds) == 0 {
		return s.Status == "ready"
	}
	last := s.Rounds[len(s.Rounds)-1]
	return s.Status == "partial" && last.Number == len(s.Rounds) && !last.Auto && len(last.Turns) == 1 && terminal(&last) == "partial"
}

func (e *Engine) LabRunSession(scope LabScope, id string) (*Session, error) {
	var room *Session
	err := e.locked(func() error {
		var err error
		room, err = e.scopedLabThread(scope, id)
		if err == nil {
			err = e.recover(room)
		}
		return err
	})
	return room, err
}

// RetryLabRun creates a round from the same user input, using current settings
// and the existing scheduler. The expected round prevents duplicate requests.
func (e *Engine) RetryLabRun(scope LabScope, id string, expectedRound int) (*Session, error) {
	return e.StartRound(id, "", "", expectedRound, RoundOptions{labRecovery: &scope})
}

func latestLabRetry(rounds []Round) int {
	for i := len(rounds) - 1; i >= 0; i-- {
		if record := rounds[i].LabRun; record != nil && record.RetryOfRound > 0 {
			return rounds[i].Number
		}
	}
	return 0
}

func (e *Engine) recordLabPromptDigest(id string, index int, ctx context.Context) error {
	digest := fmt.Sprintf("%x", sha256.Sum256([]byte(deliberation.InstructionsFrom(ctx))))
	return e.mutate(id, index, func(s *Session, _ *Turn) error {
		s.Rounds[len(s.Rounds)-1].LabRun.PromptDigest = digest
		return nil
	})
}
