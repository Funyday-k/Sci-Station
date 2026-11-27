package research

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestMinerReceiptTransitionsAndUnknownRecords(t *testing.T) {
	dir := t.TempDir()
	lab, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}
	const source = "0123456789abcdef0123456789abcdef"
	path := filepath.Join(dir, "library", "mineru", source+".json")
	open := func() *MinerReceipt {
		t.Helper()
		r, err := lab.OpenMinerReceipt(source)
		if err != nil {
			t.Fatal(err)
		}
		return r
	}
	r := open()
	if r.State != "" {
		t.Fatal(r.State)
	}
	if _, err := lab.OpenMinerReceipt(source); !errors.Is(err, syscall.EWOULDBLOCK) {
		t.Fatal(err)
	}
	if err := r.Begin(); err != nil {
		t.Fatal(err)
	}
	first := r.Attempt
	if err := r.Reject(); err != nil {
		t.Fatal(err)
	}
	r.Close()
	r = open()
	if r.State != "rejected" || r.Attempt != first {
		t.Fatal("lost definitive rejection")
	}
	if err := r.Begin(); err != nil {
		t.Fatal(err)
	}
	if err := r.RecordBatch("invalid batch"); err == nil {
		t.Fatal("invalid update accepted")
	}
	r.Close()
	r = open()
	if r.State != "creating" || r.Attempt == first {
		t.Fatal("previous intent damaged")
	}
	if err := r.RecordBatch("receipt-2"); err != nil {
		t.Fatal(err)
	}
	r.Close()
	r = open()
	if r.Batch != "receipt-2" || r.State != "batch" {
		t.Fatal("lost receipt")
	}
	r.Close()
	prior, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, data := range []string{
		"{", strings.Replace(string(prior), `"version":1`, `"version":2`, 1),
		strings.Replace(string(prior), "{", `{"future":true,`, 1), string(prior) + "{}",
	} {
		if err := os.WriteFile(path, []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := lab.OpenMinerReceipt(source); err == nil {
			t.Fatal("unrecognized state accepted")
		}
		saved, err := os.ReadFile(path)
		if err != nil || string(saved) != data {
			t.Fatal("bad state overwritten", err)
		}
	}
}

func TestRecoveredMinerBatchInvalidatesPriorConfirmation(t *testing.T) {
	lab, err := New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	const source = "0123456789abcdef0123456789abcdef"
	r, err := lab.OpenMinerReceipt(source)
	if err != nil {
		t.Fatal(err)
	}
	if err := r.Begin(); err != nil {
		t.Fatal(err)
	}
	uncertain := r.Attempt
	r.Close()

	if err := lab.RememberMinerBatch(source, "found"); err != nil {
		t.Fatal(err)
	}
	if err := lab.RememberMinerBatch(source, "older"); err != nil {
		t.Fatal(err)
	}
	r, err = lab.OpenMinerReceipt(source)
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	if r.Batch != "found" || r.Attempt == uncertain {
		t.Fatal("recovery changed a known batch or kept stale confirmation")
	}
}
