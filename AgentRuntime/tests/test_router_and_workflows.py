from sci_station_agent.graph.paper_reading import draft_paper_reading_note
from sci_station_agent.graph.router import route_intent
from sci_station_agent.rag.fts_index import ResourceDocument, FTSIndex, content_hash
from sci_station_agent.rag.evidence import is_stale, stable_evidence_id


def test_router_selects_scientific_workflows() -> None:
    assert route_intent({"user_goal": "Please create a paper note", "selected_paper_id": "p1"}) == "paper_reading"
    assert route_intent({"user_goal": "related work draft", "project_id": "proj"}) == "related_work"
    assert route_intent({"user_goal": "research gaps and next steps", "project_id": "proj"}) == "gap_planning"
    assert route_intent({"user_goal": "hello"}) == "general"


def test_evidence_id_is_stable_and_stale_detection_is_hash_based() -> None:
    first = stable_evidence_id("paper", "p1", "library/papers/p1/paper.md", 1, 12, "sha256:a")
    second = stable_evidence_id("paper", "p1", "library/papers/p1/paper.md", 1, 12, "sha256:a")
    changed = stable_evidence_id("paper", "p1", "library/papers/p1/paper.md", 1, 12, "sha256:b")
    assert first == second
    assert first != changed
    assert is_stale({"source_hash": "sha256:a"}, "sha256:b")
    assert not is_stale({"source_hash": "sha256:a"}, "sha256:a")


def test_fts_index_rebuilds_on_schema_mismatch(tmp_path) -> None:
    database = tmp_path / "chunks.sqlite"
    document = ResourceDocument(
        resource_id="paper:p1:paper.md",
        relative_path="library/papers/p1/paper.md",
        source_type="paper",
        source_id="p1",
        content="# Intro\nEvaporation rate evidence.\n\n# Method\nA local thermal model is used.",
        content_hash=content_hash("# Intro\nEvaporation rate evidence.\n\n# Method\nA local thermal model is used."),
    )
    index = FTSIndex(database)
    assert index.rebuild_if_needed()
    index.index_documents([document])
    assert index.search("Evaporation", limit=5)
    incompatible = FTSIndex(database, schema_version=2)
    assert incompatible.rebuild_if_needed()
    assert incompatible.search("Evaporation", limit=5) == []


def test_paper_reading_mvp_outputs_minimum_evidence() -> None:
    text = "\n".join([f"Line {line} method contribution limitation evidence." for line in range(1, 80)])
    draft = draft_paper_reading_note(
        run_id="run-test",
        paper_id="p1",
        paper_text=text,
        relative_path="library/papers/p1/paper.md",
        source_hash="sha256:paper",
    )
    assert not draft.needs_conversion
    assert len(draft.evidence) >= 7
    assert len(draft.artifact["evidence_refs"]) >= 7
    assert "## Contributions" in draft.artifact["content"]
    assert "## Methods" in draft.artifact["content"]
    assert "## Limitations" in draft.artifact["content"]


def test_paper_reading_degrades_when_markdown_is_missing() -> None:
    draft = draft_paper_reading_note("run-test", "p1", "too short", "library/papers/p1/paper.md", "sha256:short")
    assert draft.needs_conversion
    assert draft.artifact["evidence_refs"] == []
    assert "Convert or OCR" in draft.artifact["content"]
