import json
from zipfile import ZipFile

import pytest

from sci_station_agent.server import SidecarServer
from sci_station_agent.graph.paper_reading import draft_paper_reading_note
from sci_station_agent.graph.related_work import draft_related_work_production
from sci_station_agent.graph.gap_planning import draft_gap_planning_production
from sci_station_agent.graph.citation_critic import critic_check_evidence
from sci_station_agent.graph.router import route_intent
from sci_station_agent.rag.fts_index import ResourceDocument, FTSIndex, content_hash
from sci_station_agent.rag.evidence import is_stale, stable_evidence_id
from sci_station_agent.rag.embedding_store import DeterministicFallbackEmbeddingStore, EmbeddingModelIdentity, chunks_from_resource_document, open_preferred_embedding_store
from sci_station_agent.rag.retriever import EmbeddingConfig, FTSRetriever, HybridRetriever, InMemoryEmbeddingIndex
from sci_station_agent.storage.events import append_event, read_replay, write_debug_bundle, write_replay


def test_router_selects_scientific_workflows() -> None:
    assert route_intent({"user_goal": "Please create a paper note", "selected_paper_id": "p1"}) == "paper_reading"
    assert route_intent({"user_goal": "related work draft", "project_id": "proj"}) == "related_work"
    assert route_intent({"user_goal": "research gaps and next steps", "project_id": "proj"}) == "gap_planning"
    assert route_intent({"user_goal": "hello"}) == "general"


@pytest.mark.parametrize(
    ("goal", "selected_paper_id", "project_id", "workflow", "artifact_kind", "target_path"),
    [
        ("请精读这篇论文", "p1", None, "paper_reading", "paper_reading_note", "wiki/papers/p1.md"),
        ("draft related work", None, "project-alpha", "related_work", "related_work", "projects/project-alpha/wiki/related_work.md"),
        ("research gaps and next steps", None, "project-alpha", "gap_planning", "research_plan", "projects/project-alpha/wiki/research_plan.md"),
    ],
)
def test_agent_start_routes_to_production_workflows(tmp_path, goal, selected_paper_id, project_id, workflow, artifact_kind, target_path) -> None:
    server = SidecarServer()
    init_response = server.handle({
        "jsonrpc": "2.0",
        "id": "init",
        "method": "sidecar.initialize",
        "params": {"protocolVersion": "1.0", "schemaVersion": 1, "workspaceRoot": str(tmp_path)},
    })
    assert init_response and init_response["result"]["workspaceAccepted"]

    run_id = f"run-{workflow}"
    response = server.handle({
        "jsonrpc": "2.0",
        "id": "start",
        "method": "agent.start",
        "params": {
            "runID": run_id,
            "goal": goal,
            "selectedPaperID": selected_paper_id,
            "projectID": project_id,
            "workspaceRoot": str(tmp_path),
        },
    })

    assert response and response["result"]["accepted"]
    events = [action["envelope"] for action in server.pending_actions if action.get("kind") == "event"]
    event_types = [event["event"]["type"] for event in events]
    artifact = next(event["event"]["payload"] for event in events if event["event"]["type"] == "artifact_draft")
    run_directory = tmp_path / ".sci-station" / "agent" / "runs" / run_id
    trace = json.loads((run_directory / "retrieval_trace.json").read_text(encoding="utf-8"))

    assert event_types == ["run_started", "node_started", "artifact_draft", "final_response"]
    assert artifact["kind"] == artifact_kind
    assert artifact["proposed_path"] == target_path
    assert trace["workflow"] == workflow
    assert trace["schema_version"] == 2
    assert trace["query"]["redacted"] is True
    assert "hash" in trace["query"]
    assert "candidates" in trace
    assert (run_directory / "critic_report.json").exists()
    assert (run_directory / "evidence.json").exists()
    assert not (tmp_path / target_path).exists()


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
    assert draft.critic_report and draft.critic_report["can_request_approval"]
    assert "## TL;DR" in draft.artifact["content"]
    assert "## Contributions" in draft.artifact["content"]
    assert "## Method" in draft.artifact["content"]
    assert "## Experiments" in draft.artifact["content"]
    assert "## Limitations" in draft.artifact["content"]
    assert "## Open Questions" in draft.artifact["content"]


def test_paper_reading_degrades_when_markdown_is_missing() -> None:
    draft = draft_paper_reading_note("run-test", "p1", "too short", "library/papers/p1/paper.md", "sha256:short")
    assert draft.needs_conversion
    assert draft.artifact["evidence_refs"] == []
    assert "Convert or OCR" in draft.artifact["content"]


def test_paper_reading_graph_evidence_minimums() -> None:
    text = "\n".join([f"Line {line} retrieval workflow method experiment limitation evidence." for line in range(1, 90)])
    draft = draft_paper_reading_note("run-p35", "p35-paper", text, "library/papers/p35-paper/paper.md", "sha256:p35")
    content = draft.artifact["content"]
    assert content.count("## ") >= 9
    assert content.count("[evidence:") >= 10
    assert len(draft.evidence) >= 9
    assert not draft.critic_report["unsupported_claims"]


def test_related_work_theme_clustering() -> None:
    evidence = sample_evidence_table()
    draft = draft_related_work_production("run-related", "project-alpha", evidence)
    content = draft.artifact["content"]
    assert draft.artifact["proposed_path"] == "projects/project-alpha/wiki/related_work.md"
    assert "## Theme 1" in content
    assert "## Theme 2" in content
    assert "## Theme 3" in content
    assert "## Evidence Matrix" in content
    assert len({row["theme"] for row in draft.evidence_matrix}) == 3
    assert draft.critic_report["can_request_approval"]


def test_gap_planning_todo_schema() -> None:
    evidence = sample_evidence_table()
    existing = [{"id": "todo-existing", "title": "Investigate gap-1 for project-alpha"}]
    draft = draft_gap_planning_production("run-gap", "project-alpha", evidence, existing_tasks=existing)
    assert draft.artifact["proposed_path"] == "projects/project-alpha/wiki/research_plan.md"
    assert "evidence-backed gap" in draft.artifact["content"]
    assert "inferred gap" in draft.artifact["content"]
    assert "user-assumption" in draft.artifact["content"]
    assert draft.todo_drafts
    first = draft.todo_drafts[0]
    assert {"priority", "related_paper_or_project", "reason", "optional_due_date"}.issubset(first)
    assert first["possible_duplicate_task_id"] == "todo-existing"
    assert draft.critic_report["can_request_approval"]


def test_citation_critic_blocks_unsupported_claim() -> None:
    report = critic_check_evidence(
        {
            "content": "# Related Work\n\n## Theme 1\n- This is the best and most significant claim without support.\n",
        },
        sample_evidence_table(),
    )
    assert not report.can_request_approval
    assert report.unsupported_claims
    assert "Core scientific claims" in report.required_revisions[-1]


def test_hybrid_retriever_dedupes_chunk_ids(tmp_path) -> None:
    database = tmp_path / "chunks.sqlite"
    document = ResourceDocument(
        resource_id="paper:p1:paper.md",
        relative_path="library/papers/p1/paper.md",
        source_type="paper",
        source_id="p1",
        content="# Retrieval\nHybrid retrieval evidence for RAG and workflow search.",
        content_hash=content_hash("# Retrieval\nHybrid retrieval evidence for RAG and workflow search."),
    )
    index = FTSIndex(database)
    index.index_documents([document])
    fts = FTSRetriever(index)
    fts_result = fts.retrieve("retrieval", limit=1)[0]
    embedding_index = InMemoryEmbeddingIndex()
    embedding_index.upsert(fts_result["chunk_id"], [1.0, 0.0], {**fts_result, "confidence": 0.95})
    hybrid = HybridRetriever(fts, embedding_index, EmbeddingConfig(enabled=True, provider="swift-proxy", model="test", dimension=2, store="sqlite-vec"))
    results = hybrid.retrieve("retrieval", limit=5, query_vector=[1.0, 0.0])
    assert [result["chunk_id"] for result in results].count(fts_result["chunk_id"]) == 1
    assert results[0]["confidence"] == 0.95


def test_embedding_fallback_uses_fts_when_disabled(tmp_path) -> None:
    database = tmp_path / "chunks.sqlite"
    document = ResourceDocument(
        resource_id="paper:p2:paper.md",
        relative_path="library/papers/p2/paper.md",
        source_type="paper",
        source_id="p2",
        content="# Workflow\nWorkflow orchestration search evidence.",
        content_hash=content_hash("# Workflow\nWorkflow orchestration search evidence."),
    )
    index = FTSIndex(database)
    index.index_documents([document])
    hybrid = HybridRetriever(FTSRetriever(index), InMemoryEmbeddingIndex(), EmbeddingConfig(enabled=False))
    results = hybrid.retrieve("workflow", limit=2, query_vector=[0.0, 1.0])
    assert len(results) == 1
    assert results[0]["source_id"] == "p2"


def test_deterministic_embedding_store_persists_and_marks_model_mismatch(tmp_path) -> None:
    content = "# Retrieval\nPersistent embedding retrieval evidence."
    document = ResourceDocument(
        resource_id="paper:p37:paper.md",
        relative_path="library/papers/p37/paper.md",
        source_type="paper",
        source_id="p37",
        content=content,
        content_hash=content_hash(content),
    )
    store = DeterministicFallbackEmbeddingStore(tmp_path / ".sci-station/index/embeddings", fallback_reason="test fallback")
    store.open()
    store.begin_transaction()
    store.upsert_chunks(chunks_from_resource_document(document, EmbeddingModelIdentity(model_id="model-a", dimension=32)))
    store.commit()
    results = store.query("embedding retrieval", limit=3, current_source_hashes={document.relative_path: document.content_hash})
    mismatch = store.health_check(EmbeddingModelIdentity(model_id="model-b", dimension=32))

    assert results
    assert results[0].source_hash_status == "fresh"
    assert mismatch.status == "stale"
    assert mismatch.stale_count == 1
    assert (tmp_path / ".sci-station/index/embeddings/deterministic_fallback_chunks.json").exists()


def test_preferred_embedding_store_falls_back_when_sqlite_vec_unavailable(tmp_path) -> None:
    store = open_preferred_embedding_store(tmp_path, prefer_sqlite_vec=True)
    stats = store.stats()

    assert stats.store in {"sqlite_vec", "deterministic_fallback"}
    if stats.store == "deterministic_fallback":
        assert stats.fallback_reason


def test_hybrid_retriever_trace_records_scores_and_redacts_query(tmp_path) -> None:
    content = "# Retrieval\nHybrid retrieval trace evidence."
    database = tmp_path / "chunks.sqlite"
    document = ResourceDocument(
        resource_id="paper:p37:paper.md",
        relative_path="library/papers/p37/paper.md",
        source_type="paper",
        source_id="p37",
        content=content,
        content_hash=content_hash(content),
    )
    index = FTSIndex(database)
    index.index_documents([document])
    store = DeterministicFallbackEmbeddingStore(tmp_path / ".sci-station/index/embeddings", fallback_reason="sqlite-vec unavailable in test")
    store.open()
    store.upsert_chunks(chunks_from_resource_document(document))
    hybrid = HybridRetriever(FTSRetriever(index), store, EmbeddingConfig(enabled=True, store="sqlite-vec"))
    results, trace = hybrid.retrieve_with_trace("Hybrid retrieval trace evidence", limit=5, current_source_hashes={document.relative_path: document.content_hash})

    assert results
    assert trace["schema_version"] == 2
    assert trace["query"]["redacted"] is True
    assert "Hybrid retrieval" not in json.dumps(trace)
    assert trace["embedding_store"] == "deterministic_fallback"
    assert trace["fallback_reason"]
    assert trace["candidates"][0]["fts_score"] is not None
    assert trace["candidates"][0]["rerank_reason"]


def test_stale_evidence_detection() -> None:
    evidence = sample_evidence_table()[0]
    report = critic_check_evidence(
        {"content": f"# Paper Note\n\n## Contributions\n- Claim. [evidence:{evidence['id']}]\n"},
        [evidence],
        current_source_hashes={evidence["relative_path"]: "sha256:changed"},
    )
    assert report.can_request_approval
    assert report.stale_evidence[0]["evidence_id"] == evidence["id"]


def test_run_replay_redaction(tmp_path) -> None:
    run_directory = tmp_path / "run-1"
    append_event(run_directory, {"id": "evt-1", "event": {"type": "run_started"}})
    replay = write_replay(run_directory, include_debug_text=True, prompt_response={"api_key": "sk-secret", "prompt": f"read {tmp_path}/paper.md"})
    loaded = read_replay(run_directory)
    assert replay["debug"]["api_key"] == "[REDACTED]"
    assert str(tmp_path) not in replay["debug"]["prompt"]
    assert loaded["events"][0]["id"] == "evt-1"


def test_debug_bundle_zip_redacts_sensitive_content(tmp_path) -> None:
    run_directory = tmp_path / "run-zip"
    append_event(run_directory, {"id": "evt-1", "event": {"type": "final_response", "payload": {"markdown": "token sk-secret"}}})
    (run_directory / "critic_report.json").write_text(json.dumps({"api_key": "sk-secret"}), encoding="utf-8")
    (run_directory / "retrieval_trace.json").write_text(json.dumps({"path": f"{tmp_path}/paper.md"}), encoding="utf-8")
    write_replay(run_directory, include_debug_text=True, prompt_response={"token": "sk-secret", "prompt": f"read {tmp_path}/paper.md"})
    bundle = write_debug_bundle(run_directory)

    with ZipFile(bundle) as archive:
        names = set(archive.namelist())
        contents = "\n".join(archive.read(name).decode("utf-8", errors="ignore") for name in names)

    assert "debug_bundle_manifest.json" in names
    assert "critic_report.json" in names
    assert "sk-secret" not in contents
    assert str(tmp_path) not in contents
    assert "prompt response plaintext" not in contents
    assert ".env" not in names


def sample_evidence_table() -> list[dict]:
    rows = []
    themes = [
        ("retrieval", "retrieval RAG index search evidence"),
        ("retrieval", "retrieval search ranking evidence"),
        ("workflow", "agent workflow orchestration planning evidence"),
        ("workflow", "workflow planning checkpoint evidence"),
        ("evaluation", "evaluation benchmark experiment metric evidence"),
        ("evaluation", "experiment metric comparison evidence"),
    ]
    for index, (heading, quote) in enumerate(themes, start=1):
        relative_path = f"library/papers/p{index}/paper.md"
        evidence_id = stable_evidence_id("paper", f"p{index}", relative_path, 1, 8, f"sha256:{index}")
        rows.append({
            "id": evidence_id,
            "source_type": "paper",
            "source_id": f"p{index}",
            "relative_path": relative_path,
            "lines": [1, 8],
            "source_hash": f"sha256:{index}",
            "chunk_id": f"paper:p{index}:1-8",
            "retrieved_at": "2026-05-05T00:00:00Z",
            "heading": heading,
            "quote": quote,
            "confidence": 0.74,
        })
    return rows
