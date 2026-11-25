package plugins

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"slices"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
)

const (
	MaxInputBytes           = 256 << 10
	MaxOutputBytes          = 128 << 10
	MaxConcurrentExecutions = 2
	maxMemoryPages          = 256 // A WebAssembly page is 64 KiB.
	moduleTimeout           = time.Second

	maxDefinitions   = 4096
	maxExports       = 64
	maxTableEntries  = 1024
	maxParameters    = 32
	maxFunctionBody  = 16 << 10
	maxFunctionLocal = 256
)

var moduleSlots = make(chan struct{}, MaxConcurrentExecutions)

// Run executes one action in a fresh, import-free WebAssembly instance.
func Run(ctx context.Context, module []byte, input []byte) (string, error) {
	return executeModule(ctx, module, input, false)
}

func executeModule(ctx context.Context, module, input []byte, validateOnly bool) (string, error) {
	if len(module) > MaxModuleBytes {
		return "", fmt.Errorf("plugin module exceeds %d bytes", MaxModuleBytes)
	}
	if len(input) > MaxInputBytes {
		return "", fmt.Errorf("plugin input exceeds %d bytes", MaxInputBytes)
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	select {
	case moduleSlots <- struct{}{}:
	default:
		return "", errors.New("plugin runtime is busy")
	}

	ctx, cancel := context.WithTimeout(ctx, moduleTimeout)
	defer cancel()
	// Preserve ownership if the caller returns while compilation finishes.
	module, input = bytes.Clone(module), bytes.Clone(input)
	type result struct {
		output string
		err    error
	}
	done := make(chan result, 1)
	go func() {
		output, err := compileAndRun(ctx, module, input, validateOnly)
		<-moduleSlots
		done <- result{output, err}
	}()
	select {
	case completed := <-done:
		if err := ctx.Err(); err != nil {
			return "", fmt.Errorf("plugin time budget: %w", err)
		}
		return completed.output, completed.err
	case <-ctx.Done():
		// Compilation itself is synchronous in wazero. Leave its bounded worker
		// slot occupied until it finishes and releases the runtime resources.
		return "", fmt.Errorf("plugin time budget: %w", ctx.Err())
	}
}

func compileAndRun(ctx context.Context, module, input []byte, validateOnly bool) (string, error) {
	core, err := checkModuleSections(module)
	if err != nil {
		return "", err
	}
	features := api.CoreFeaturesV1 | api.CoreFeatureSignExtensionOps | api.CoreFeatureNonTrappingFloatToIntConversion
	config := wazero.NewRuntimeConfigInterpreter().
		WithCoreFeatures(features).
		WithMemoryLimitPages(maxMemoryPages).
		WithCloseOnContextDone(true).
		WithDebugInfoEnabled(false)
	runtime := wazero.NewRuntimeWithConfig(ctx, config)
	defer runtime.Close(context.Background())
	compiled, err := runtime.CompileModule(ctx, core)
	if err != nil {
		return "", fmt.Errorf("invalid WebAssembly module: %w", err)
	}
	memory := compiled.ExportedMemories()["memory"]
	if memory == nil {
		return "", errors.New("plugin module must export linear memory as memory")
	}
	functions := compiled.ExportedFunctions()
	if !hasSignature(functions["alloc"], []api.ValueType{api.ValueTypeI32}, api.ValueTypeI32) {
		return "", errors.New("plugin module must export alloc(i32) -> i32")
	}
	if !hasSignature(functions["run"], []api.ValueType{api.ValueTypeI32, api.ValueTypeI32}, api.ValueTypeI64) {
		return "", errors.New("plugin module must export run(i32, i32) -> i64")
	}
	if validateOnly {
		return "", nil
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	instance, err := runtime.InstantiateModule(ctx, compiled, wazero.NewModuleConfig().WithStartFunctions())
	if err != nil {
		return "", fmt.Errorf("could not initialize plugin module: %w", err)
	}
	linearMemory := instance.ExportedMemory("memory")
	allocation, err := instance.ExportedFunction("alloc").Call(ctx, uint64(len(input)))
	if err != nil {
		return "", fmt.Errorf("plugin alloc failed: %w", err)
	}
	inputPointer := uint32(allocation[0])
	if !linearMemory.Write(inputPointer, input) {
		return "", errors.New("plugin input points outside WebAssembly memory")
	}
	returned, err := instance.ExportedFunction("run").Call(ctx, uint64(inputPointer), uint64(len(input)))
	if err != nil {
		return "", fmt.Errorf("plugin run failed: %w", err)
	}
	outputPointer, outputLength := uint32(returned[0]>>32), uint32(returned[0])
	if outputLength > MaxOutputBytes {
		return "", fmt.Errorf("plugin output exceeds %d bytes", MaxOutputBytes)
	}
	output, ok := linearMemory.Read(outputPointer, outputLength)
	if !ok {
		return "", errors.New("plugin output points outside WebAssembly memory")
	}
	if !isPlainText(output) {
		return "", errors.New("plugin output must be valid UTF-8 text")
	}
	return string(output), nil
}

func hasSignature(function api.FunctionDefinition, parameters []api.ValueType, result api.ValueType) bool {
	return function != nil && slices.Equal(function.ParamTypes(), parameters) &&
		slices.Equal(function.ResultTypes(), []api.ValueType{result})
}

func isPlainText(text []byte) bool {
	if !utf8.Valid(text) {
		return false
	}
	for len(text) > 0 {
		char, size := utf8.DecodeRune(text)
		if unicode.IsControl(char) && char != '\n' && char != '\r' && char != '\t' {
			return false
		}
		text = text[size:]
	}
	return true
}

const (
	customSection   = 0
	typeSection     = 1
	importSection   = 2
	functionSection = 3
	tableSection    = 4
	memorySection   = 5
	globalSection   = 6
	exportSection   = 7
	startSection    = 8
	elementSection  = 9
	codeSection     = 10
	dataSection     = 11
)

// Bound length-prefixed allocations that the engine's decoder would otherwise
// make before checking whether they fit in the binary. The engine validates
// instructions, signatures, typing, and section semantics after this pass.
func checkModuleSections(module []byte) ([]byte, error) {
	const header = "\x00asm\x01\x00\x00\x00"
	if !bytes.HasPrefix(module, []byte(header)) {
		return nil, errors.New("invalid WebAssembly header")
	}
	core := make([]byte, len(header), len(module))
	copy(core, header)
	remaining := wasmBytes(module[len(header):])
	var bounds wasmBounds
	var previous byte
	for len(remaining) > 0 {
		sectionStart := remaining
		id := remaining[0]
		remaining = remaining[1:]
		section, ok := remaining.sized()
		if !ok {
			return nil, errors.New("invalid WebAssembly section length")
		}
		if id == customSection {
			name, ok := section.sized()
			if !ok || !utf8.Valid(name) {
				return nil, errors.New("invalid WebAssembly custom section name")
			}
			continue
		}
		if id <= previous || id > dataSection {
			return nil, errors.New("unsupported or out-of-order WebAssembly section")
		}
		previous = id
		switch id {
		case importSection:
			count, ok := section.uint32()
			if !ok || count != 0 || len(section) != 0 {
				return nil, errors.New("plugin module cannot import host functions, memory, tables, or globals")
			}
		case startSection:
			return nil, errors.New("plugin module cannot have a WebAssembly start function")
		default:
			if !bounds.checkSection(id, section) {
				return nil, fmt.Errorf("WebAssembly section %d is malformed or exceeds plugin limits", id)
			}
		}
		core = append(core, sectionStart[:len(sectionStart)-len(remaining)]...)
	}
	return core, nil
}

type wasmBounds struct {
	memoryBytes  uint32
	tableEntries uint32
}

func (bounds *wasmBounds) checkSection(id byte, section wasmBytes) bool {
	limit := uint32(maxDefinitions)
	switch id {
	case tableSection, memorySection:
		limit = 1
	case exportSection:
		limit = maxExports
	}
	count, ok := section.vector(limit)
	if !ok {
		return false
	}
	// These entries have no unbounded nested allocations.
	if id == functionSection || id == globalSection {
		return true
	}
	for range count {
		switch id {
		case typeSection:
			if !section.consume(0x60) || !section.valueTypes(maxParameters) || !section.valueTypes(1) {
				return false
			}
		case tableSection:
			if !section.consume(0x70) {
				return false
			}
			minimum, ok := section.limits(maxTableEntries, false)
			if !ok {
				return false
			}
			bounds.tableEntries = minimum
		case memorySection:
			minimum, ok := section.limits(maxMemoryPages, true)
			if !ok {
				return false
			}
			bounds.memoryBytes = minimum << 16
		case exportSection:
			if _, ok := section.sized(); !ok || !section.skip(1) {
				return false
			}
			if _, ok := section.uint32(); !ok {
				return false
			}
		case elementSection, dataSection:
			index, ok := section.uint32()
			if !ok || index != 0 {
				return false
			}
			offset, ok := section.offset()
			if !ok {
				return false
			}
			if id == elementSection {
				indexes, ok := section.vector(maxTableEntries)
				if !ok || offset+indexes > bounds.tableEntries {
					return false
				}
				for range indexes {
					if _, ok := section.uint32(); !ok {
						return false
					}
				}
			} else if data, ok := section.sized(); !ok || offset+uint32(len(data)) > bounds.memoryBytes {
				return false
			}
		case codeSection:
			body, ok := section.sized()
			if !ok || len(body) > maxFunctionBody || !body.locals() {
				return false
			}
		}
	}
	return len(section) == 0
}

type wasmBytes []byte

func (b *wasmBytes) uint32() (uint32, bool) {
	value, size := binary.Uvarint(*b)
	if size <= 0 || size > 5 || value > uint64(^uint32(0)) {
		return 0, false
	}
	*b = (*b)[size:]
	return uint32(value), true
}

func (b *wasmBytes) vector(max uint32) (uint32, bool) {
	count, ok := b.uint32()
	return count, ok && count <= max && count <= uint32(len(*b))
}

func (b *wasmBytes) sized() (wasmBytes, bool) {
	size, ok := b.uint32()
	if !ok || size > uint32(len(*b)) {
		return nil, false
	}
	value := (*b)[:size]
	*b = (*b)[size:]
	return value, true
}

func (b *wasmBytes) skip(size uint32) bool {
	if size > uint32(len(*b)) {
		return false
	}
	*b = (*b)[size:]
	return true
}

func (b *wasmBytes) consume(value byte) bool {
	if len(*b) == 0 || (*b)[0] != value {
		return false
	}
	return b.skip(1)
}

func (b *wasmBytes) valueType() bool {
	// Core 1.0 numeric types i32, i64, f32 and f64.
	return len(*b) > 0 && (*b)[0] >= 0x7c && (*b)[0] <= 0x7f && b.skip(1)
}

func (b *wasmBytes) valueTypes(limit uint32) bool {
	count, ok := b.vector(limit)
	if !ok {
		return false
	}
	for range count {
		if !b.valueType() {
			return false
		}
	}
	return true
}

func (b *wasmBytes) limits(limit uint32, memory bool) (uint32, bool) {
	if len(*b) == 0 || (*b)[0] > 1 {
		return 0, false
	}
	hasMax := (*b)[0] == 1
	b.skip(1)
	minimum, ok := b.uint32()
	if !ok || minimum > limit {
		return 0, false
	}
	if !hasMax {
		return minimum, true
	}
	maximum, ok := b.uint32()
	return minimum, ok && minimum <= maximum && maximum <= limit && (!memory || maximum > 0)
}

func (b *wasmBytes) offset() (uint32, bool) {
	if !b.consume(0x41) { // i32.const
		return 0, false
	}
	var value uint32
	for index := range 5 {
		if len(*b) == 0 {
			return 0, false
		}
		part := (*b)[0]
		b.skip(1)
		if index == 4 && part > 7 {
			return 0, false // An offset must be a nonnegative i32.
		}
		value |= uint32(part&0x7f) << (index * 7)
		if part&0x80 == 0 {
			return value, part&0x40 == 0 && b.consume(0x0b) // end
		}
	}
	return 0, false
}

func (b *wasmBytes) locals() bool {
	groups, ok := b.vector(maxFunctionLocal)
	if !ok {
		return false
	}
	var total uint32
	for range groups {
		count, ok := b.uint32()
		if !ok || count > maxFunctionLocal-total || !b.valueType() {
			return false
		}
		total += count
	}
	return true
}
