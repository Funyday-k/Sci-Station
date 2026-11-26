package plugins

import (
	"bytes"
	"encoding/json"
	"slices"
	"strings"
	"testing"
)

func packageFixture() Manifest {
	return Manifest{
		SchemaVersion: 1,
		ID:            "org.roundtable.digest",
		Version:       "1.2.3",
		Name:          "讨论摘要",
		Author:        "Roundtable",
		Description:   "Summarize shared contributions.",
		Contributions: Contributions{RoundGuidance: "Keep assumptions and conclusions separate."},
	}
}

func encodePackageFixture(t *testing.T, manifest Manifest) []byte {
	t.Helper()
	data, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestParsePackageDerivesCapabilitiesFromEachContribution(t *testing.T) {
	manifest := packageFixture()
	manifest.Contributions.ReportGuidance = "Trace every claim to the discussion."
	manifest.Contributions.Actions = []Action{
		{ID: "notes", Label: "Notes", Input: "public_turns", Format: "markdown"},
		{ID: "minutes", Label: "Minutes", Input: "public_turns", Format: "text"},
		{ID: "check-report", Label: "Check report", Input: "report", Format: "text"},
	}
	manifest.Module = makeWasmFixture(wasmFixtureOptions{})
	parsed, err := ParsePackage(encodePackageFixture(t, manifest))
	if err != nil || !bytes.Equal(parsed.Module, manifest.Module) {
		t.Fatalf("ParsePackage() = %+v, %v", parsed, err)
	}
	want := []string{CapCodeExecute, CapPublicTurns, CapReport, CapReportGuidance, CapRoundGuidance}
	if got := parsed.Capabilities(); !slices.Equal(got, want) {
		t.Fatalf("capabilities = %v, want %v", got, want)
	}
}

func TestParsePackageRejectsAmbiguousAndUnsupportedFields(t *testing.T) {
	manifest := packageFixture()
	valid := string(encodePackageFixture(t, manifest))
	tests := []struct {
		name string
		data string
	}{
		{"schema version", strings.Replace(valid, `"schema_version":1`, `"schema_version":2`, 1)},
		{"unknown field", `{"script":"/usr/bin/env",` + valid[1:]},
		{"duplicate field", `{"id":"org.roundtable.duplicate",` + valid[1:]},
		{"duplicate escaped field", `{"i\u0064":"org.roundtable.duplicate",` + valid[1:]},
		{"different casing", strings.Replace(valid, `"description"`, `"Description"`, 1)},
		{"multiple values", valid + `{}`},
		{"null optional field", `{"module":null,` + valid[1:]},
		{"duplicate nested field", strings.Replace(valid, `{"round_guidance":`, `{"round_guidance":"duplicate","round_guidance":`, 1)},
		{"invalid UTF-8", strings.Replace(valid, "Roundtable", "\xff", 1)},
		{"invalid base64", `{"module":"not base64",` + valid[1:]},
		{"empty contributions", strings.Replace(valid, `{"round_guidance":"Keep assumptions and conclusions separate."}`, `{}`, 1)},
		{"invalid id", strings.Replace(valid, manifest.ID, "../digest", 1)},
		{"invalid version", strings.Replace(valid, manifest.Version, "1.02.3", 1)},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := ParsePackage([]byte(test.data)); err == nil {
				t.Fatal("ParsePackage accepted invalid input")
			}
		})
	}
	if _, err := ParsePackage(make([]byte, MaxPackageBytes+1)); err == nil || !strings.Contains(err.Error(), "package exceeds") {
		t.Fatalf("oversized package: %v", err)
	}
}

func TestParsePackageChecksActionABIAndRejectsDuplicateActions(t *testing.T) {
	manifest := packageFixture()
	manifest.Module = makeWasmFixture(wasmFixtureOptions{})
	if _, err := ParsePackage(encodePackageFixture(t, manifest)); err == nil || !strings.Contains(err.Error(), "module requires an action") {
		t.Fatalf("module without action: %v", err)
	}
	action := Action{ID: "output", Label: "Output", Input: "report", Format: "text"}
	manifest.Contributions.Actions = []Action{action, action}
	if _, err := ParsePackage(encodePackageFixture(t, manifest)); err == nil || !strings.Contains(err.Error(), "duplicate action") {
		t.Fatalf("duplicate action: %v", err)
	}
	manifest.Contributions.Actions = []Action{action}
	manifest.Module = nil
	if _, err := ParsePackage(encodePackageFixture(t, manifest)); err == nil || !strings.Contains(err.Error(), "actions require a WebAssembly module") {
		t.Fatalf("action without module: %v", err)
	}
	manifest.Module = makeWasmFixture(wasmFixtureOptions{withoutMemoryExport: true})
	if _, err := ParsePackage(encodePackageFixture(t, manifest)); err == nil || !strings.Contains(err.Error(), "must export linear memory") {
		t.Fatalf("action with invalid ABI: %v", err)
	}
}

func TestPackageGuidanceFitsEncodedMeetingBudget(t *testing.T) {
	for _, stage := range []string{"round_guidance", "report_guidance"} {
		t.Run(stage, func(t *testing.T) {
			manifest := packageFixture()
			manifest.Contributions = Contributions{}
			manifest.Name = "a < b"
			size := maxGuidanceBytes - 2 - guidanceSize(manifest.ID, manifest.Version, manifest.Name, stage, "")
			text := &manifest.Contributions.RoundGuidance
			if stage == "report_guidance" {
				text = &manifest.Contributions.ReportGuidance
			}
			*text = strings.Repeat("x", size)
			if _, err := ParsePackage(encodePackageFixture(t, manifest)); err != nil {
				t.Fatalf("guidance at encoded boundary: %v", err)
			}
			*text = (*text)[1:] + "<" // Same text byte count, six encoded bytes for '<'.
			if _, err := ParsePackage(encodePackageFixture(t, manifest)); err == nil || !strings.Contains(err.Error(), "meeting guidance limit") {
				t.Fatalf("guidance outside encoded boundary: %v", err)
			}
		})
	}
}

func TestCompareVersionsUsesNumericComponents(t *testing.T) {
	if CompareVersions("1.9.9", "1.10.0") >= 0 || CompareVersions("10.0.1", "9.99.99") <= 0 || CompareVersions("1.2.3", "1.2.3") != 0 {
		t.Fatal("incorrect semantic version ordering")
	}
}
