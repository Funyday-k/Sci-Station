package meeting

import (
	"context"
	"errors"
	"strings"
	"testing"

	"scistation.local/desktop/internal/credentials"
)

func TestSecretPromptRejectedBeforePersistence(t *testing.T) {
	e, dir := engine(t, func(context.Context, string, string, string, string) (string, error) {
		t.Error("sensitive prompt reached a model")
		return "", nil
	})
	defer e.Shutdown(context.Background())
	key := "sk-" + strings.Repeat("example", 4)
	if _, err := e.Create(key, dir, []string{"codex"}); !errors.Is(err, credentials.ErrSecretInPrompt) {
		t.Fatal("expected secret topic to be rejected")
	}
	session, err := e.Create("Review a reading task-"+strings.Repeat("a", 20), dir, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.Start(session.ID, "use "+key, "", 0); !errors.Is(err, credentials.ErrSecretInPrompt) {
		t.Fatal("expected secret follow-up to be rejected")
	}
	saved, err := e.Get(session.ID)
	if err != nil || len(saved.Rounds) != 0 {
		t.Fatal("rejected prompt changed meeting history")
	}
}
