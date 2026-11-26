package plugins

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"strings"
	"testing"
	"time"
)

const wasmEchoFixture = "\x20\x00\xad\x42\x20\x86\x20\x01\xad\x84"

type wasmFixtureOptions struct {
	imports, memory, data, start []byte
	alloc, run                   string
	resultType                   byte
	withoutMemoryExport          bool
}

func makeWasmFixture(options wasmFixtureOptions) []byte {
	const i32, i64 = 0x7f, 0x7e
	module := []byte("\x00asm\x01\x00\x00\x00")
	appendSection := func(id byte, bytes []byte) {
		module = append(module, id)
		module = binary.AppendUvarint(module, uint64(len(bytes)))
		module = append(module, bytes...)
	}
	if options.resultType == 0 {
		options.resultType = i64
	}
	appendSection(typeSection, []byte{2, 0x60, 1, i32, 1, i32, 0x60, 2, i32, i32, 1, options.resultType})
	if options.imports != nil {
		appendSection(importSection, options.imports)
	}
	appendSection(functionSection, []byte{2, 0, 1})
	if options.memory == nil {
		options.memory = []byte{1, 0, 1} // one memory initialized with one page
	}
	appendSection(memorySection, options.memory)
	exports := []byte("\x02\x05alloc\x00\x00\x03run\x00\x01")
	if !options.withoutMemoryExport {
		exports[0]++
		exports = append(exports, "\x06memory\x02\x00"...)
	}
	appendSection(exportSection, exports)
	if options.start != nil {
		appendSection(startSection, options.start)
	}
	if options.alloc == "" {
		options.alloc = "\x41\x10" // i32.const 16
	}
	if options.run == "" {
		options.run = wasmEchoFixture
	}
	code := []byte{2}
	for _, instructions := range []string{options.alloc, options.run} {
		code = binary.AppendUvarint(code, uint64(len(instructions)+2))
		code = append(code, 0) // no extra locals
		code = append(code, instructions...)
		code = append(code, 0x0b) // end
	}
	appendSection(codeSection, code)
	if options.data != nil {
		appendSection(dataSection, options.data)
	}
	return module
}

func TestRunWebAssemblyEcho(t *testing.T) {
	input := []byte(`{"action":"echo","topic":"圆桌"}`)
	got, err := Run(context.Background(), makeWasmFixture(wasmFixtureOptions{}), input)
	if err != nil || got != string(input) {
		t.Fatalf("Run() = %q, %v", got, err)
	}
	if _, err := Run(context.Background(), nil, bytes.Repeat([]byte{'x'}, MaxInputBytes+1)); err == nil || !strings.Contains(err.Error(), "input exceeds") {
		t.Fatalf("oversized input: %v", err)
	}
}

func TestRunRejectsUnsafeResultsAndKeepsWorking(t *testing.T) {
	tests := []struct {
		name    string
		options wasmFixtureOptions
		want    string
	}{
		{"bad alloc pointer", wasmFixtureOptions{alloc: "\x41\x7f"}, "input points outside"},
		{"bad output pointer", wasmFixtureOptions{run: "\x42\x81\x80\x80\x80\x70"}, "output points outside"},
		{"oversized result", wasmFixtureOptions{run: "\x42\x81\x80\x08"}, "output exceeds"},
		{"invalid UTF-8", wasmFixtureOptions{run: wasmEchoFixture}, "valid UTF-8"},
		{"binary control character", wasmFixtureOptions{run: "\x42\x01"}, "valid UTF-8"},
		{"memory limit", wasmFixtureOptions{run: "\x41\x80\x02\x40\x00\x41\x7f\x46\x04\x40\x00\x0b" + wasmEchoFixture}, "unreachable"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			input := []byte("{}")
			if test.name == "invalid UTF-8" {
				input = []byte{0xff}
			}
			_, err := Run(context.Background(), makeWasmFixture(test.options), input)
			if err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("expected %q, got %v", test.want, err)
			}
			got, err := Run(context.Background(), makeWasmFixture(wasmFixtureOptions{}), []byte("{}"))
			if err != nil || got != "{}" {
				t.Fatalf("healthy module after %s: %q, %v", test.name, got, err)
			}
		})
	}
}

func TestRunStopsLoopAtItsDeadline(t *testing.T) {
	loop := makeWasmFixture(wasmFixtureOptions{run: "\x03\x40\x0c\x00\x0b\x42\x00"})
	start := time.Now()
	_, err := Run(context.Background(), loop, []byte("{}"))
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("expected a deadline error, got %v", err)
	}
	if elapsed := time.Since(start); elapsed > moduleTimeout+time.Second {
		t.Fatalf("loop took %s", elapsed)
	}
	got, err := Run(context.Background(), makeWasmFixture(wasmFixtureOptions{}), []byte("{}"))
	if err != nil || got != "{}" {
		t.Fatalf("healthy module after loop: %q, %v", got, err)
	}
}

func TestRunEnforcesConcurrentLimitAndReleasesSlots(t *testing.T) {
	waitForSlots := func(want int) {
		t.Helper()
		deadline := time.Now().Add(moduleTimeout / 2)
		for len(moduleSlots) != want {
			if time.Now().After(deadline) {
				t.Fatalf("%d active plugin workers, want %d", len(moduleSlots), want)
			}
			time.Sleep(time.Millisecond)
		}
	}
	waitForSlots(0)
	loop := makeWasmFixture(wasmFixtureOptions{run: "\x03\x40\x0c\x00\x0b\x42\x00"})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, MaxConcurrentExecutions)
	for range MaxConcurrentExecutions {
		go func() {
			_, err := Run(ctx, loop, nil)
			done <- err
		}()
	}
	waitForSlots(MaxConcurrentExecutions)
	healthy := makeWasmFixture(wasmFixtureOptions{})
	if _, err := Run(context.Background(), healthy, nil); err == nil || !strings.Contains(err.Error(), "runtime is busy") {
		t.Fatalf("expected concurrency limit, got %v", err)
	}
	cancel()
	for range MaxConcurrentExecutions {
		if err := <-done; !errors.Is(err, context.Canceled) {
			t.Fatalf("expected cancellation, got %v", err)
		}
	}
	waitForSlots(0)
	if _, err := Run(context.Background(), healthy, nil); err != nil {
		t.Fatalf("instance after workers closed: %v", err)
	}
}

func TestWebAssemblyValidationRejectsImportsAndInvalidABI(t *testing.T) {
	tests := []struct {
		name    string
		options wasmFixtureOptions
		want    string
	}{
		{"function import", wasmFixtureOptions{imports: []byte("\x01\x16wasi_snapshot_preview1\x01x\x00\x00")}, "cannot import"},
		{"memory import", wasmFixtureOptions{imports: []byte("\x01\x03env\x01m\x02\x00\x01")}, "cannot import"},
		{"global import", wasmFixtureOptions{imports: []byte("\x01\x03env\x01g\x03\x7f\x00")}, "cannot import"},
		{"table import", wasmFixtureOptions{imports: []byte("\x01\x03env\x01t\x01\x70\x00\x01")}, "cannot import"},
		{"start section", wasmFixtureOptions{start: []byte{0}}, "cannot have a WebAssembly start"},
		{"missing memory export", wasmFixtureOptions{withoutMemoryExport: true}, "must export linear memory"},
		{"wrong result type", wasmFixtureOptions{resultType: 0x7f, run: "\x41\x00"}, "must export run(i32, i32) -> i64"},
		{"initial memory too large", wasmFixtureOptions{memory: []byte{1, 0, 0x81, 0x02}}, "section 5"},
		{"declared max memory too large", wasmFixtureOptions{memory: []byte{1, 1, 1, 0x81, 0x02}}, "section 5"},
		{"shared memory", wasmFixtureOptions{memory: []byte{1, 3, 1, 2}}, "section 5"},
		{"out-of-bounds data initializer", wasmFixtureOptions{data: []byte{1, 0, 0x41, 0x80, 0x80, 0x04, 0x0b, 1, 'x'}}, "section 11"},
		{"truncated data vector with oversized claim", wasmFixtureOptions{data: []byte{1, 0, 0x41, 0, 0x0b, 0xff, 0xff, 0xff, 0xff, 0x0f}}, "section 11"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := executeModule(context.Background(), makeWasmFixture(test.options), nil, true)
			if err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("expected %q, got %v", test.want, err)
			}
		})
	}
	if _, err := executeModule(context.Background(), make([]byte, MaxModuleBytes+1), nil, true); err == nil || !strings.Contains(err.Error(), "module exceeds") {
		t.Fatalf("oversized module: %v", err)
	}
}

func TestRunLoadsStaticDataAtValidOffset(t *testing.T) {
	options := wasmFixtureOptions{
		data: []byte{1, 0, 0x41, 0xc0, 0, 0x0b, 3, 'o', 'k', '\n'}, // Offset 64 needs a second signed LEB128 byte.
		run:  "\x42\x83\x80\x80\x80\x80\x08",                       // Packed pointer 64 and length 3.
	}
	got, err := Run(context.Background(), makeWasmFixture(options), nil)
	if err != nil || got != "ok\n" {
		t.Fatalf("Run() = %q, %v", got, err)
	}
}
