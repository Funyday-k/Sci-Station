# Manual Test Report

## Basic Info

- Date: 2026-05-06
- Tester: GitHub Copilot
- Task: P37 Embedding Persistent Store and Retrieval Runtime
- Module: AI Lab / Retrieval Index / Sidecar Embedding Proxy / Evidence Trace
- Commit: 4338c70 (working tree not committed)
- macOS: macOS local VS Code environment
- Xcode: Available; App build completed
- Workspace: Repository fixtures and generated temporary Research Roots from automated tests
- AI enabled: Test-mode deterministic provider paths
- Sidecar enabled: Enabled for sidecar contract and workflow fixture paths
- Embedding enabled: Deterministic fallback enabled; sqlite-vec native extension unavailable

## Automated Baseline

- `/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests -q`: PASS, 27 passed
- `swift run SciStationCoreTestRunner`: PASS, All SciStation core checks passed
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`: PASS, `BUILD SUCCEEDED`
- `get_errors` for edited Swift / SwiftUI files: PASS, no errors found
- sqlite dependency check: PASS for fallback expectation, `sqlite3=True`, `sqlite_vec=False`

## Test Scope

- [x] Smoke, automated compile and Problems check
- [x] Happy Path, deterministic fallback retrieval fixture
- [x] Persistence, fallback index JSON under `.sci-station/index/embeddings/`
- [x] Permission / Privacy, sidecar proxy rejects sensitive provider config and debug bundle excludes index files
- [x] Error / Fallback, sqlite-vec unavailable path falls back without blocking workflows
- [x] Integration, Settings / AI Lab retrieval status UI compiles in App target
- [x] Regression, SwiftPM, Python, and Xcode baselines pass

## Test Cases

### MT07 AI Lab Partial

- ID: MT07-P37-01
- Title: AI Lab retrieval status panel compiles and exposes basic index operations
- Preconditions: App build and SwiftPM core runner
- Steps: Build App target; execute core tests covering `AgentEmbeddingIndexController.rebuildSelectedSource`
- Expected: AI Lab runtime/status panel can show retrieval status, fallback reason, rebuild source/project actions, diagnostic copy, and loading state without breaking runtime panel
- Actual: Xcode build passed; CoreTestRunner passed retrieval index controller fixture
- Result: PASS via automated substitute; interactive UI clicks not executed in this environment
- Notes: No S0/S1 issue found by automated checks

### MT09 Evidence / Artifact Retrieval Partial

- ID: MT09-P37-01
- Title: FTS-only fallback run returns evidenceRefs and redacted retrieval_trace
- Preconditions: Python sidecar workflow fixtures
- Steps: Run AgentRuntime pytest workflow route tests
- Expected: `retrieval_trace.json` uses schema version 2, query is redacted/hash-only, evidence candidates preserve path and line metadata
- Actual: Python tests passed; trace assertions confirmed redacted query and candidates
- Result: PASS

- ID: MT09-P37-02
- Title: Deterministic fallback store persists chunks and returns stable search results
- Preconditions: Temporary Research Root fixture
- Steps: Build chunks from `paper.md`, upsert into fallback store, query, inspect persisted file
- Expected: Store writes `.sci-station/index/embeddings/deterministic_fallback_chunks.json`; query result has fresh source hash status
- Actual: Python and Swift fixtures passed
- Result: PASS

- ID: MT09-P37-03
- Title: sqlite-vec unavailable falls back without crashing
- Preconditions: Current Python environment with `sqlite_vec=False`
- Steps: Run preferred store factory and sidecar dependency check
- Expected: Store reports deterministic fallback with explicit fallback reason; workflows remain runnable
- Actual: Python tests passed; dependency check reported `sqlite_vec=False`
- Result: PASS for fallback path; native sqlite-vec extension path SKIPPED

- ID: MT09-P37-04
- Title: source_hash and model mismatch mark stale / migration required
- Preconditions: Temporary Research Root fixture with indexed chunk
- Steps: Query with changed source hash; health-check with changed model id
- Expected: Changed source hash returns stale; model id mismatch returns stale / migration required
- Actual: Python test and Swift CoreTestRunner passed
- Result: PASS

- ID: MT09-P37-05
- Title: Hybrid retrieval trace records FTS, embedding, rerank, dedupe and fallback metadata
- Preconditions: FTS fixture plus deterministic fallback embedding store
- Steps: Run hybrid retriever trace test
- Expected: Trace contains score fields and reasons; query plaintext is absent
- Actual: Python test passed
- Result: PASS

- ID: MT09-P37-06
- Title: Index and debug artifacts do not contain secrets or prompt/response plaintext
- Preconditions: Debug bundle fixture and retrieval artifact scan
- Steps: Execute debug bundle tests and targeted text scans
- Expected: Debug manifest excludes `.sci-station/index/embeddings/**`, `.env`, API keys, Keychain content, private path inventory, prompt/response plaintext
- Actual: Swift and Python tests passed; targeted scans found no secret literals in embedding store files
- Result: PASS

### MT99 Partial Regression

- ID: MT99-P37-01
- Title: Release partial regression for retrieval runtime
- Preconditions: App build, SwiftPM runner, Python tests
- Steps: Run automated baselines and Problems check
- Expected: App compiles, core workflows pass, fallback retrieval does not break AI Lab / Settings / sidecar runtime contracts
- Actual: All automated baselines passed
- Result: PASS for automated baseline; interactive launch/restart checks are SKIPPED

## Skipped / Conditional Items

- sqlite-vec native extension path: SKIPPED because the current environment reports `sqlite_vec=False`; deterministic fallback and preferred-store fallback were verified.
- provider-backed real embedding API call: SKIPPED because P37 acceptance must pass without an API key; Swift proxy contract and redacted metadata were verified.
- Full interactive macOS UI click pass: SKIPPED in this tool environment; Xcode build and SwiftUI wiring were used as substitute coverage.

## Issues Found

| ID | Severity | Module | Description | Repro Steps | Status |
|---|---|---|---|---|---|
| P37-MT-01 | S3 | Manual Testing | Interactive macOS UI clicks were not executed from this environment; coverage is automated substitute plus successful App build. | N/A | Deferred to human/manual pass |
| P37-MT-02 | S4 | Retrieval Native Store | sqlite-vec native extension unavailable in this environment, so native vector path was not manually validated. | Dependency check reports `sqlite_vec=False` | Deferred until sqlite-vec is installed |

## Final Verdict

- Result: CONDITIONAL PASS
- Required fixes before merge: None found by automated validation
- Can defer: Full interactive MT07/MT09/MT99 pass with a real test workspace and sqlite-vec-enabled machine
- Follow-up tasks: P38 artifact lifecycle, Draft Inbox, Evidence Inspector, Permission Dock V2
