from __future__ import annotations

import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Any

from .models import ArtifactRecord, CorpusManifest, FinalDecision, JudgeResult, ToolDescriptor, ValidatorResult, WorkflowSpec
from .reporting import classify_run_failure
from .utils import iso_now


SCHEMA = """
CREATE TABLE IF NOT EXISTS corpus_items (
    item_id TEXT PRIMARY KEY,
    source_family TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    split TEXT NOT NULL,
    media_type TEXT NOT NULL,
    tasks_json TEXT NOT NULL,
    tags_json TEXT NOT NULL,
    probe_json TEXT NOT NULL,
    annotations_json TEXT NOT NULL,
    expected_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS runs (
    run_id TEXT PRIMARY KEY,
    workflow_id TEXT NOT NULL,
    corpus_item_id TEXT NOT NULL,
    status TEXT NOT NULL,
    final_status TEXT,
    started_at TEXT,
    finished_at TEXT,
    reasons_json TEXT DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS run_steps (
    run_id TEXT NOT NULL,
    step_index INTEGER NOT NULL,
    step_name TEXT NOT NULL,
    tool_name TEXT,
    status TEXT NOT NULL,
    output_text TEXT,
    metadata_json TEXT DEFAULT '{}',
    PRIMARY KEY (run_id, step_index)
);

CREATE TABLE IF NOT EXISTS artifacts (
    run_id TEXT NOT NULL,
    label TEXT NOT NULL,
    kind TEXT NOT NULL,
    path TEXT NOT NULL,
    metadata_json TEXT DEFAULT '{}',
    PRIMARY KEY (run_id, label)
);

CREATE TABLE IF NOT EXISTS validator_results (
    run_id TEXT NOT NULL,
    validator_id TEXT NOT NULL,
    status TEXT NOT NULL,
    score REAL,
    details TEXT NOT NULL,
    evidence_json TEXT DEFAULT '[]',
    metadata_json TEXT DEFAULT '{}',
    PRIMARY KEY (run_id, validator_id)
);

CREATE TABLE IF NOT EXISTS judge_results (
    run_id TEXT NOT NULL,
    judge_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    rubric_id TEXT NOT NULL,
    status TEXT NOT NULL,
    score REAL,
    confidence REAL,
    explanation TEXT NOT NULL,
    evidence_json TEXT DEFAULT '[]',
    metadata_json TEXT DEFAULT '{}',
    PRIMARY KEY (run_id, judge_id, provider)
);

CREATE TABLE IF NOT EXISTS judge_cache (
    provider TEXT NOT NULL,
    cache_key TEXT NOT NULL,
    result_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (provider, cache_key)
);

CREATE TABLE IF NOT EXISTS decision_records (
    run_id TEXT PRIMARY KEY,
    status TEXT NOT NULL,
    reasons_json TEXT DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS mcp_tools (
    tool_name TEXT PRIMARY KEY,
    family TEXT NOT NULL,
    description TEXT NOT NULL,
    input_schema_json TEXT NOT NULL,
    discovered_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS workflow_tool_declared_coverage (
    workflow_id TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    PRIMARY KEY (workflow_id, tool_name)
);

CREATE TABLE IF NOT EXISTS workflow_tool_observed_coverage (
    workflow_id TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    run_id TEXT NOT NULL,
    observed_at TEXT NOT NULL,
    final_status TEXT NOT NULL,
    PRIMARY KEY (workflow_id, tool_name, run_id)
);
"""


class EvalStore:
    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.executescript(SCHEMA)

    def sync_corpus_items(self, manifest: CorpusManifest) -> None:
        with self._connect() as connection:
            connection.execute("DELETE FROM corpus_items")
            for item in manifest.items:
                connection.execute(
                    """
                    INSERT INTO corpus_items (
                        item_id, source_family, relative_path, split, media_type,
                        tasks_json, tags_json, probe_json, annotations_json, expected_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        item.id,
                        item.source_family,
                        item.relative_path,
                        item.split,
                        item.media_type,
                        json.dumps(item.tasks),
                        json.dumps(item.content_tags),
                        json.dumps(item.probe),
                        json.dumps(item.annotations),
                        json.dumps(item.expected),
                    ),
                )

    def sync_tool_inventory(self, tools: list[ToolDescriptor]) -> None:
        with self._connect() as connection:
            for tool in tools:
                connection.execute(
                    """
                    INSERT INTO mcp_tools(tool_name, family, description, input_schema_json, discovered_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(tool_name) DO UPDATE SET
                        family=excluded.family,
                        description=excluded.description,
                        input_schema_json=excluded.input_schema_json,
                        discovered_at=excluded.discovered_at
                    """,
                    (
                        tool.name,
                        tool.family,
                        tool.description,
                        json.dumps(tool.input_schema),
                        iso_now(),
                    ),
                )

    def sync_declared_coverage(self, workflow: WorkflowSpec) -> None:
        with self._connect() as connection:
            connection.execute("DELETE FROM workflow_tool_declared_coverage WHERE workflow_id = ?", (workflow.id,))
            for tool_name in workflow.declared_tools:
                connection.execute(
                    "INSERT INTO workflow_tool_declared_coverage(workflow_id, tool_name) VALUES (?, ?)",
                    (workflow.id, tool_name),
                )

    def create_run(self, run_id: str, workflow_id: str, corpus_item_id: str, status: str = "queued") -> None:
        with self._connect() as connection:
            connection.execute(
                "INSERT INTO runs(run_id, workflow_id, corpus_item_id, status) VALUES (?, ?, ?, ?)",
                (run_id, workflow_id, corpus_item_id, status),
            )

    def mark_run_started(self, run_id: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "UPDATE runs SET status = 'running', started_at = ? WHERE run_id = ?",
                (iso_now(), run_id),
            )

    def record_step(
        self,
        run_id: str,
        step_index: int,
        step_name: str,
        status: str,
        output_text: str = "",
        tool_name: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO run_steps(
                    run_id, step_index, step_name, tool_name, status, output_text, metadata_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    run_id,
                    step_index,
                    step_name,
                    tool_name,
                    status,
                    output_text,
                    json.dumps(metadata or {}),
                ),
            )

    def record_artifact(self, run_id: str, artifact: ArtifactRecord) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO artifacts(run_id, label, kind, path, metadata_json)
                VALUES (?, ?, ?, ?, ?)
                """,
                (run_id, artifact.label, artifact.kind, artifact.path, json.dumps(artifact.metadata)),
            )

    def record_validator_result(self, run_id: str, result: ValidatorResult) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO validator_results(
                    run_id, validator_id, status, score, details, evidence_json, metadata_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    run_id,
                    result.validator_id,
                    result.status,
                    result.score,
                    result.details,
                    json.dumps(result.evidence_paths),
                    json.dumps(result.metadata),
                ),
            )

    def record_judge_result(self, run_id: str, result: JudgeResult) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO judge_results(
                    run_id, judge_id, provider, rubric_id, status, score, confidence,
                    explanation, evidence_json, metadata_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    run_id,
                    result.judge_id,
                    result.provider,
                    result.rubric_id,
                    result.status,
                    result.score,
                    result.confidence,
                    result.explanation,
                    json.dumps(result.evidence_paths),
                    json.dumps(result.metadata),
                ),
            )

    def get_cached_judge_result(self, provider: str, cache_key: str) -> JudgeResult | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT result_json FROM judge_cache WHERE provider = ? AND cache_key = ?",
                (provider, cache_key),
            ).fetchone()
        if row is None:
            return None
        payload = json.loads(row["result_json"])
        return JudgeResult(
            judge_id=payload["judge_id"],
            provider=payload["provider"],
            rubric_id=payload["rubric_id"],
            status=payload["status"],
            score=payload.get("score"),
            confidence=payload.get("confidence"),
            explanation=payload["explanation"],
            evidence_paths=list(payload.get("evidence_paths", [])),
            metadata=dict(payload.get("metadata", {})),
        )

    def cache_judge_result(self, provider: str, cache_key: str, result: JudgeResult) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO judge_cache(provider, cache_key, result_json, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (provider, cache_key, json.dumps(result.to_dict()), iso_now()),
            )

    def record_observed_tool(self, workflow_id: str, tool_name: str, run_id: str, final_status: str) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO workflow_tool_observed_coverage(
                    workflow_id, tool_name, run_id, observed_at, final_status
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (workflow_id, tool_name, run_id, iso_now(), final_status),
            )

    def finalize_run(self, run_id: str, decision: FinalDecision) -> None:
        with self._connect() as connection:
            connection.execute(
                "UPDATE runs SET status = 'completed', final_status = ?, finished_at = ?, reasons_json = ? WHERE run_id = ?",
                (decision.status, iso_now(), json.dumps(decision.reasons), run_id),
            )
            connection.execute(
                """
                INSERT OR REPLACE INTO decision_records(run_id, status, reasons_json)
                VALUES (?, ?, ?)
                """,
                (run_id, decision.status, json.dumps(decision.reasons)),
            )

    def claim_next_queued_run(self) -> sqlite3.Row | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT run_id, workflow_id, corpus_item_id FROM runs WHERE status = 'queued' ORDER BY rowid LIMIT 1"
            ).fetchone()
            if row is None:
                return None
            connection.execute(
                "UPDATE runs SET status = 'running', started_at = ? WHERE run_id = ?",
                (iso_now(), row["run_id"]),
            )
            return row

    def list_runs(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM runs ORDER BY COALESCE(started_at, finished_at, run_id) DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_run(self, run_id: str) -> dict[str, Any]:
        with self._connect() as connection:
            run = connection.execute("SELECT * FROM runs WHERE run_id = ?", (run_id,)).fetchone()
            if run is None:
                raise KeyError(run_id)
            steps = connection.execute("SELECT * FROM run_steps WHERE run_id = ? ORDER BY step_index", (run_id,)).fetchall()
            artifacts = connection.execute("SELECT * FROM artifacts WHERE run_id = ? ORDER BY label", (run_id,)).fetchall()
            validators = connection.execute("SELECT * FROM validator_results WHERE run_id = ?", (run_id,)).fetchall()
            judges = connection.execute("SELECT * FROM judge_results WHERE run_id = ?", (run_id,)).fetchall()
        return {
            "run": dict(run),
            "steps": [dict(row) for row in steps],
            "artifacts": [dict(row) for row in artifacts],
            "validators": [dict(row) for row in validators],
            "judges": [dict(row) for row in judges],
        }

    def summary(self) -> dict[str, Any]:
        with self._connect() as connection:
            corpus_count = connection.execute("SELECT COUNT(*) FROM corpus_items").fetchone()[0]
            run_count = connection.execute("SELECT COUNT(*) FROM runs").fetchone()[0]
            quarantined = connection.execute("SELECT COUNT(*) FROM runs WHERE final_status = 'quarantine'").fetchone()[0]
            failed = connection.execute("SELECT COUNT(*) FROM runs WHERE final_status = 'fail'").fetchone()[0]
            passed = connection.execute("SELECT COUNT(*) FROM runs WHERE final_status = 'pass'").fetchone()[0]
        return {
            "corpus_items": corpus_count,
            "runs": run_count,
            "pass": passed,
            "fail": failed,
            "quarantine": quarantined,
        }

    def coverage_report(self, stale_days: int) -> list[dict[str, Any]]:
        query = """
        WITH observed AS (
            SELECT
                tool_name,
                workflow_id,
                MAX(observed_at) AS last_observed_at,
                MAX(CASE WHEN final_status = 'pass' THEN observed_at END) AS last_success_at,
                SUM(CASE WHEN final_status = 'pass' THEN 1 ELSE 0 END) AS pass_count,
                COUNT(*) AS observed_count
            FROM workflow_tool_observed_coverage
            GROUP BY tool_name, workflow_id
        ),
        declared AS (
            SELECT workflow_id, tool_name
            FROM workflow_tool_declared_coverage
        ),
        relationships AS (
            SELECT workflow_id, tool_name, 1 AS declared, 0 AS observed
            FROM declared
            UNION
            SELECT workflow_id, tool_name, 0 AS declared, 1 AS observed
            FROM observed
        )
        SELECT
            tools.tool_name,
            tools.family,
            relationships.workflow_id AS workflow_id,
            MAX(relationships.declared) AS is_declared,
            MAX(relationships.observed) AS is_observed,
            observed.workflow_id AS observed_workflow_id,
            observed.last_observed_at,
            observed.last_success_at,
            observed.observed_count,
            observed.pass_count
        FROM mcp_tools AS tools
        LEFT JOIN relationships ON relationships.tool_name = tools.tool_name
        LEFT JOIN observed ON observed.tool_name = tools.tool_name AND observed.workflow_id = relationships.workflow_id
        GROUP BY
            tools.tool_name,
            tools.family,
            relationships.workflow_id,
            observed.workflow_id,
            observed.last_observed_at,
            observed.last_success_at,
            observed.observed_count,
            observed.pass_count
        ORDER BY tools.family, tools.tool_name, relationships.workflow_id
        """
        with self._connect() as connection:
            rows = [dict(row) for row in connection.execute(query)]
        now = dt.datetime.now(dt.timezone.utc)
        report: dict[str, dict[str, Any]] = {}
        for row in rows:
            entry = report.setdefault(
                row["tool_name"],
                {
                    "tool_name": row["tool_name"],
                    "family": row["family"],
                    "workflows": [],
                    "status": "uncovered",
                },
            )
            workflow_id = row["workflow_id"]
            if workflow_id is not None:
                workflow_status = "declared_not_observed"
                if row["is_declared"] and row["observed_count"]:
                    workflow_status = "covered"
                    if row["pass_count"] == 0:
                        workflow_status = "observed_without_pass"
                elif row["is_observed"] and not row["is_declared"]:
                    workflow_status = "observed_undeclared"
                last_success_at = row["last_success_at"]
                if workflow_status == "covered" and last_success_at:
                    try:
                        last_success = dt.datetime.fromisoformat(last_success_at.replace("Z", "+00:00"))
                    except ValueError:
                        last_success = None
                    if last_success is not None and (now - last_success).days > stale_days:
                        workflow_status = "stale"
                entry["workflows"].append(
                    {
                        "workflow_id": workflow_id,
                        "status": workflow_status,
                        "last_observed_at": row["last_observed_at"],
                        "last_success_at": row["last_success_at"],
                    }
                )
            if entry["workflows"]:
                statuses = {workflow["status"] for workflow in entry["workflows"]}
                if "stale" in statuses:
                    entry["status"] = "stale"
                elif "covered" in statuses:
                    entry["status"] = "covered"
                elif "observed_without_pass" in statuses:
                    entry["status"] = "observed_without_pass"
                elif "observed_undeclared" in statuses:
                    entry["status"] = "observed_undeclared"
                else:
                    entry["status"] = "declared_not_observed"
        return list(report.values())

    def classify_nonpass_runs(self, workflow_ids: list[str] | None = None) -> list[dict[str, Any]]:
        query = """
        SELECT
            runs.run_id,
            runs.workflow_id,
            runs.corpus_item_id,
            runs.status,
            runs.final_status,
            runs.started_at,
            runs.finished_at,
            runs.reasons_json,
            corpus_items.source_family,
            corpus_items.tags_json,
            corpus_items.annotations_json,
            corpus_items.expected_json
        FROM runs
        JOIN corpus_items ON corpus_items.item_id = runs.corpus_item_id
        WHERE runs.final_status IS NOT NULL AND runs.final_status != 'pass'
        """
        params: list[Any] = []
        if workflow_ids:
            placeholders = ",".join("?" for _ in workflow_ids)
            query += f" AND runs.workflow_id IN ({placeholders})"
            params.extend(workflow_ids)
        query += " ORDER BY runs.workflow_id, runs.corpus_item_id, runs.run_id"

        with self._connect() as connection:
            run_rows = [dict(row) for row in connection.execute(query, params)]
            results: list[dict[str, Any]] = []
            for run in run_rows:
                validators = [
                    dict(row)
                    for row in connection.execute(
                        "SELECT * FROM validator_results WHERE run_id = ? AND status != 'pass'",
                        (run["run_id"],),
                    )
                ]
                judges = [
                    dict(row)
                    for row in connection.execute(
                        "SELECT * FROM judge_results WHERE run_id = ? AND status != 'pass'",
                        (run["run_id"],),
                    )
                ]
                classification = classify_run_failure(run, run, validators, judges)
                results.append(
                    {
                        "run_id": run["run_id"],
                        "workflow_id": run["workflow_id"],
                        "corpus_item_id": run["corpus_item_id"],
                        "final_status": run["final_status"],
                        "failure_category": classification.category,
                        "classification_reasons": classification.reasons,
                        "signals": classification.signals,
                    }
                )
        return results

    def summarize_nonpass_runs(self, workflow_ids: list[str] | None = None) -> dict[str, Any]:
        classified = self.classify_nonpass_runs(workflow_ids=workflow_ids)
        by_category: dict[str, int] = {}
        by_workflow: dict[str, dict[str, int]] = {}
        for row in classified:
            category = row["failure_category"]
            workflow_id = row["workflow_id"]
            by_category[category] = by_category.get(category, 0) + 1
            workflow_entry = by_workflow.setdefault(workflow_id, {})
            workflow_entry[category] = workflow_entry.get(category, 0) + 1
        return {
            "total_nonpass_runs": len(classified),
            "by_category": by_category,
            "by_workflow": by_workflow,
            "runs": classified,
        }
