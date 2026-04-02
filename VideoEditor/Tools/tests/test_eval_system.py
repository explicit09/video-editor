from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS_ROOT = Path(__file__).resolve().parents[1]
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

from eval_system.corpus import CorpusManager, SandboxStager, infer_tasks
from eval_system.config import EvalConfig
from eval_system.judges import JudgeGateway, MockJudgeAdapter
from eval_system.models import CorpusManifest, FinalDecision, JudgeResult, JudgeTask, WorkflowSpec
from eval_system.reporting import (
    FAILURE_CATEGORY_EXPECTED,
    FAILURE_CATEGORY_INFRASTRUCTURE,
    FAILURE_CATEGORY_PRODUCT,
    workflow_policy_summary,
)
from eval_system.runner import EvaluationRunner, validate_tool_output
from eval_system.storage import EvalStore
from eval_system.utils import parse_broll_suggestions, parse_editor_state, parse_snapshot_list, resolve_template, stable_split
from eval_system.validators import (
    audio_present,
    broll_inserted,
    hook_structure_changed,
    verify_playback_post_edit_integrity,
    verify_playback_clean,
)


class CorpusManagerTests(unittest.TestCase):
    def test_stable_split_is_deterministic(self) -> None:
        self.assertEqual(stable_split("example.mov"), stable_split("example.mov"))

    def test_rescan_picks_up_media_and_failure_tags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            (root / "failure_pack").mkdir()
            media = root / "failure_pack" / "failure_black_insert.mp4"
            media.write_bytes(b"fake")
            manager = CorpusManager(root)
            manifest = manager.rescan_manifest()
            self.assertEqual(len(manifest.items), 1)
            self.assertEqual(manifest.items[0].source_family, "failure")
            self.assertIn("failure-case", manifest.items[0].content_tags)

    def test_rescan_picks_up_audio_capability_tags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            (root / "pexels").mkdir()
            media = root / "pexels" / "clip.mp4"
            media.write_bytes(b"fake")
            manager = CorpusManager(root)
            with mock.patch("eval_system.corpus.probe_media", return_value={"duration_seconds": 5, "resolution": "640x360", "fps": 30, "has_audio": False, "mime_type": "video/mp4", "size_bytes": 4}):
                manifest = manager.rescan_manifest()
            self.assertIn("no-audio", manifest.items[0].content_tags)
            self.assertIn("visual-only", manifest.items[0].content_tags)

    def test_sandbox_stager_normalizes_mkv_to_mp4(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            source = root / "source.mkv"
            source.write_bytes(b"mkv")
            stager = SandboxStager(root / "staging")
            item = mock.Mock(id="ava-sample", relative_path="source.mkv", filename="source.mkv")

            def fake_ffmpeg(args, **kwargs):
                Path(args[-1]).write_bytes(b"mp4")
                return mock.Mock()

            with mock.patch("eval_system.corpus.subprocess.run", side_effect=fake_ffmpeg) as patched_run:
                staged = stager.stage(item, root)

            self.assertEqual(staged.suffix, ".mp4")
            self.assertTrue(staged.exists())
            self.assertEqual(patched_run.call_count, 1)

    def test_sandbox_stager_stage_path_copies_non_mkv(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            source = root / "seed.mp4"
            source.write_bytes(b"mp4")
            stager = SandboxStager(root / "staging")

            staged = stager.stage_path("item-1", source)

            self.assertEqual(staged.name, "seed.mp4")
            self.assertTrue(staged.exists())
            self.assertEqual(staged.read_bytes(), b"mp4")


class EvalStoreTests(unittest.TestCase):
    def test_sync_declared_coverage_and_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            store = EvalStore(Path(tmp_dir) / "index.sqlite")
            store.sync_tool_inventory([])
            workflow = WorkflowSpec(
                id="wf",
                description="",
                eligibility_tags=[],
                allowed_source_families=[],
                max_duration_seconds=None,
                max_duration_by_source_family={},
                declared_tools=["set_clip_keyframes"],
                steps=[],
                validators=[],
                judges=[],
            )
            store.sync_declared_coverage(workflow)
            with store._connect() as connection:  # noqa: SLF001
                connection.execute(
                    "INSERT INTO mcp_tools(tool_name, family, description, input_schema_json, discovered_at) VALUES (?, ?, ?, ?, ?)",
                    ("set_clip_keyframes", "clip", "", "{}", "2026-03-31T00:00:00Z"),
                )
            report = store.coverage_report(stale_days=30)
            self.assertEqual(report[0]["tool_name"], "set_clip_keyframes")
            self.assertEqual(report[0]["status"], "declared_not_observed")

    def test_coverage_report_flags_observed_undeclared_tool(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            store = EvalStore(Path(tmp_dir) / "index.sqlite")
            with store._connect() as connection:  # noqa: SLF001
                connection.execute(
                    "INSERT INTO mcp_tools(tool_name, family, description, input_schema_json, discovered_at) VALUES (?, ?, ?, ?, ?)",
                    ("set_clip_keyframes", "clip", "", "{}", "2026-03-31T00:00:00Z"),
                )
            store.record_observed_tool("wf", "set_clip_keyframes", "run-1", "fail")
            report = store.coverage_report(stale_days=30)
            self.assertEqual(report[0]["status"], "observed_undeclared")

    def test_run_storage_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            store = EvalStore(Path(tmp_dir) / "index.sqlite")
            store.create_run("run-1", "wf", "item-1", status="queued")
            run = store.claim_next_queued_run()
            self.assertEqual(run["run_id"], "run-1")

    def test_summarize_nonpass_runs_classifies_categories(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            store = EvalStore(Path(tmp_dir) / "index.sqlite")
            manifest = CorpusManifest.from_dict(
                {
                    "name": "eval",
                    "version": "2.0",
                    "created": "2026-04-02T00:00:00Z",
                    "description": "test",
                    "splits": {"calibration": 2},
                    "items": [
                        {
                            "id": "tvsum-1",
                            "source_family": "tvsum",
                            "relative_path": "tvsum/video/a.mp4",
                            "media_type": "video",
                            "split": "calibration",
                            "content_tags": ["has-audio"],
                            "tasks": ["import_and_verify"],
                            "annotations": {},
                            "expected": {},
                            "probe": {"duration_seconds": 10, "has_audio": True},
                        },
                        {
                            "id": "failure-1",
                            "source_family": "failure",
                            "relative_path": "failure_pack/b.mp4",
                            "media_type": "video",
                            "split": "calibration",
                            "content_tags": ["failure-case", "has-audio"],
                            "tasks": ["clip_editing_suite"],
                            "annotations": {},
                            "expected": {},
                            "probe": {"duration_seconds": 10, "has_audio": True},
                        },
                    ],
                }
            )
            store.sync_corpus_items(manifest)

            store.create_run("run-infra", "import_and_verify", "tvsum-1", status="queued")
            store.record_validator_result("run-infra", verify_playback_clean("verify_playback output was missing a result line"))
            store.finalize_run("run-infra", FinalDecision(status="fail", reasons=["timed out"]))

            store.create_run("run-expected", "clip_editing_suite", "failure-1", status="queued")
            store.record_validator_result(
                "run-expected",
                verify_playback_post_edit_integrity(
                    "=== CONTENT VERIFICATION ===\nMode: quick | Checkpoints: 1 | Duration: expected 10.0s, actual 10.0s ✓\n\n[FAIL] Clip start @ 0.2s: audio NCC=1.00 video pHash=0 RMS=0.0100 — black frame\n\nResult: 0/1 PASS, 1 FAIL\n"
                ),
            )
            store.finalize_run("run-expected", FinalDecision(status="fail", reasons=["expected failure case"]))

            summary = store.summarize_nonpass_runs()
            self.assertEqual(summary["by_category"][FAILURE_CATEGORY_INFRASTRUCTURE], 1)
            self.assertEqual(summary["by_category"][FAILURE_CATEGORY_EXPECTED], 1)
            categories = {row["run_id"]: row["failure_category"] for row in summary["runs"]}
            self.assertEqual(categories["run-infra"], FAILURE_CATEGORY_INFRASTRUCTURE)
            self.assertEqual(categories["run-expected"], FAILURE_CATEGORY_EXPECTED)

    def test_workflow_policy_summary_reports_guardrails(self) -> None:
        workflow = WorkflowSpec(
            id="broll_hook_suite",
            description="",
            eligibility_tags=["has-audio"],
            allowed_source_families=["tvsum", "ava"],
            max_duration_seconds=None,
            max_duration_by_source_family={"ava": 1200},
            declared_tools=[],
            steps=[],
            validators=[{"id": "verify_playback_post_edit_integrity"}],
            judges=[],
        )
        summary = workflow_policy_summary(workflow)
        self.assertEqual(summary["allowed_source_families"], ["tvsum", "ava"])
        self.assertEqual(summary["validator_policies"]["post_edit_integrity"], 1)
        self.assertEqual(summary["long_form_guardrails"]["max_duration_by_source_family"]["ava"], 1200)



class JudgeAdapterTests(unittest.TestCase):
    def test_mock_judge_adapter_returns_expected_status(self) -> None:
        adapter = MockJudgeAdapter({"visual": {"status": "quarantine", "score": 0.2, "confidence": 0.3, "explanation": "uncertain"}})
        result = adapter.evaluate(JudgeTask("visual", "rubric", "prompt", []), [])
        self.assertEqual(result.status, "quarantine")

    def test_gateway_caches_results_and_respects_split_policy(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_root = Path(tmp_dir)
            config = _make_config(tmp_root, primary_judges=("mock",), optional_judges=(), required_splits=("calibration",))
            store = EvalStore(tmp_root / "index.sqlite")
            gateway = JudgeGateway(config, store, extra_adapters=[MockJudgeAdapter({"visual": {"status": "pass", "score": 1.0, "confidence": 0.95, "explanation": "ok"}})])
            evidence = tmp_root / "frame.png"
            evidence.write_bytes(b"frame")
            task = JudgeTask("visual", "rubric", "prompt", [])

            first = [result for result in gateway.evaluate(task, [evidence], split="calibration") if result.provider == "mock"][0]
            second = [result for result in gateway.evaluate(task, [evidence], split="calibration") if result.provider == "mock"][0]
            skipped = [result for result in gateway.evaluate(task, [evidence], split="development") if result.provider == "mock"][0]

            self.assertEqual(first.status, "pass")
            self.assertTrue(second.metadata.get("cached"))
            self.assertEqual(skipped.status, "skipped")
            self.assertEqual(skipped.metadata.get("skip_reason"), "split_policy")


class ManifestCompatibilityTests(unittest.TestCase):
    def test_manifest_from_dict_accepts_v2_shape(self) -> None:
        payload = {
            "name": "eval",
            "version": "2.0",
            "created": "2026-03-31T00:00:00Z",
            "description": "test",
            "splits": {"development": 1},
            "items": [
                {
                    "id": "item-1",
                    "source_family": "synthetic",
                    "relative_path": "synthetic/test.mp4",
                    "media_type": "video",
                    "split": "development",
                    "content_tags": [],
                    "tasks": ["import_and_verify"],
                    "annotations": {"holdout": False},
                    "expected": {},
                    "probe": {"duration_seconds": 10},
                }
            ],
        }
        manifest = CorpusManifest.from_dict(payload)
        self.assertEqual(manifest.items[0].source_family, "synthetic")

    def test_infer_tasks_includes_new_workflow_families(self) -> None:
        synthetic_tasks = infer_tasks("synthetic", "video", ["synthetic"])
        ava_tasks = infer_tasks("ava", "video", ["speaker-alignment"])
        tvsum_tasks = infer_tasks("tvsum", "video", ["highlight"])
        self.assertIn("clip_editing_suite", synthetic_tasks)
        self.assertIn("track_management_suite", synthetic_tasks)
        self.assertIn("snapshot_platform_export_suite", synthetic_tasks)
        self.assertIn("transcript_editing_suite", synthetic_tasks)
        self.assertIn("audio_cleanup_suite", synthetic_tasks)
        self.assertIn("video_processing_suite", synthetic_tasks)
        self.assertIn("content_analysis_suite", synthetic_tasks)
        self.assertIn("asset_management_suite", synthetic_tasks)
        self.assertIn("transcript_editing_suite", ava_tasks)
        self.assertIn("audio_cleanup_suite", ava_tasks)
        self.assertIn("video_processing_suite", ava_tasks)
        self.assertIn("broll_hook_suite", ava_tasks)
        self.assertIn("shorts_deep_suite", ava_tasks)
        self.assertIn("broll_hook_suite", tvsum_tasks)


class ParserTests(unittest.TestCase):
    def test_resolve_template_preserves_native_type_for_single_placeholder(self) -> None:
        resolved = resolve_template("${context.start_time}", {"context": {"start_time": 12.5}})
        self.assertEqual(resolved, 12.5)

    def test_parse_editor_state_extracts_tracks_clips_markers_and_assets(self) -> None:
        output = """=== Editor State ===\nTracks (2):\n  Video (video, id=11111111-1111-1111-1111-111111111111): Clip One [id=22222222-2222-2222-2222-222222222222, 0.0s-8.0s] (link=ABCD), Clip Two [id=33333333-3333-3333-3333-333333333333, 8.0s-18.0s]\n  Audio (audio, id=44444444-4444-4444-4444-444444444444) [muted]: empty\n\nMarkers (1):\n  1.0s: Marker A [id=55555555-5555-5555-5555-555555555555]\n\nAssets (1):\n  sample (ID: 66666666-6666-6666-6666-666666666666, 60.0s)\n\nPlayhead: 3.0s\nDuration: 18.0s\n"""
        parsed = parse_editor_state(output)
        self.assertEqual(len(parsed["tracks"]), 2)
        self.assertEqual(parsed["tracks"][0]["clips"][0]["id"], "22222222-2222-2222-2222-222222222222")
        self.assertEqual(parsed["tracks"][0]["clips"][0]["link_group"], "ABCD")
        self.assertEqual(parsed["markers"][0]["id"], "55555555-5555-5555-5555-555555555555")
        self.assertEqual(parsed["assets"][0]["id"], "66666666-6666-6666-6666-666666666666")
        self.assertEqual(parsed["playhead"], 3.0)
        self.assertEqual(parsed["duration"], 18.0)

    def test_parse_snapshot_list_extracts_snapshot_ids(self) -> None:
        snapshots = parse_snapshot_list(
            "Codex Workflow Snapshot (ID: 4532AEDA-2CE8-4BD7-A2CC-750429139AFE, 2026-04-01 07:57:58 +0000)\n"
            "Another Snapshot (ID: 4F3025EB-2B9A-42E8-95C1-7BE3A42376E3, 2026-03-30 22:27:51 +0000)\n"
        )
        self.assertEqual(snapshots[0]["name"], "Codex Workflow Snapshot")
        self.assertEqual(snapshots[0]["id"], "4532AEDA-2CE8-4BD7-A2CC-750429139AFE")

    def test_parse_broll_suggestions_extracts_start_times(self) -> None:
        suggestions = parse_broll_suggestions(
            "=== B-ROLL INSERTION SUGGESTIONS ===\n"
            "Available B-roll: public_testsrc_45s\n\n"
            "  #1 Insert 'public_testsrc_45s' at 72.7s (2.5s duration)\n"
            "  #2 Insert 'fallback' at 91.0s (1.5s duration)\n"
        )
        self.assertEqual(suggestions[0]["asset"], "public_testsrc_45s")
        self.assertEqual(suggestions[0]["start_time"], 72.7)
        self.assertEqual(suggestions[1]["duration"], 1.5)


class ValidatorTests(unittest.TestCase):
    def test_audio_present_uses_expected_has_audio_override(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            media_path = Path(tmp_dir) / "clip.mp4"
            media_path.write_bytes(b"fake")
            mocked = mock.Mock()
            mocked.stdout = json.dumps({"streams": [{"codec_type": "video"}]})
            with mock.patch("eval_system.validators.subprocess.run", return_value=mocked):
                result = audio_present(media_path, required=True, expected_has_audio=False)
            self.assertEqual(result.status, "pass")
            self.assertEqual(result.metadata["expected_has_audio"], False)
            self.assertEqual(result.metadata["validator_policy"], "audio_stream_presence")

    def test_verify_playback_clean_records_source_match_policy(self) -> None:
        result = verify_playback_clean("Result: 4/4 PASS")
        self.assertEqual(result.status, "pass")
        self.assertEqual(result.metadata["validator_policy"], "source_content_match")

    def test_verify_playback_post_edit_integrity_tolerates_content_mismatch_only(self) -> None:
        output = """=== CONTENT VERIFICATION ===
Mode: quick | Checkpoints: 4 | Duration: expected 10.0s, actual 10.0s ✓

[PASS] Clip start @ 0.2s: audio NCC=1.00 RMS=0.0100 — OK
[FAIL] Clip mid @ 5.0s: audio NCC=0.00 RMS=0.0100 — audio content mismatch (NCC=0.00<0.7)
[FAIL] Clip mid @ 5.0s: audio NCC=1.00 video pHash=16 RMS=0.0100 — video content mismatch (pHash dist=16>15)

Result: 1/3 PASS, 2 FAIL
"""
        result = verify_playback_post_edit_integrity(output)
        self.assertEqual(result.status, "pass")
        self.assertEqual(result.metadata["tolerated_failure_count"], 2)
        self.assertEqual(result.metadata["validator_policy"], "post_edit_integrity")

    def test_verify_playback_post_edit_integrity_fails_on_black_frame(self) -> None:
        output = """=== CONTENT VERIFICATION ===
Mode: quick | Checkpoints: 2 | Duration: expected 10.0s, actual 10.0s ✓

[FAIL] Clip start @ 0.2s: audio NCC=1.00 video pHash=0 RMS=0.0100 — black frame

Result: 0/1 PASS, 1 FAIL
"""
        result = verify_playback_post_edit_integrity(output)
        self.assertEqual(result.status, "fail")

    def test_broll_inserted_passes_when_video_clip_count_increases(self) -> None:
        before = """=== Editor State ===\nTracks (2):\n  Video (video, id=11111111-1111-1111-1111-111111111111): Source [id=22222222-2222-2222-2222-222222222222, 0.0s-20.0s]\n  Audio (audio, id=33333333-3333-3333-3333-333333333333): Source [id=44444444-4444-4444-4444-444444444444, 0.0s-20.0s]\n"""
        after = """=== Editor State ===\nTracks (3):\n  Video (video, id=11111111-1111-1111-1111-111111111111): Source [id=22222222-2222-2222-2222-222222222222, 0.0s-20.0s], public_testsrc_45s [id=55555555-5555-5555-5555-555555555555, 7.0s-9.5s]\n  Audio (audio, id=33333333-3333-3333-3333-333333333333): Source [id=44444444-4444-4444-4444-444444444444, 0.0s-20.0s]\n  Video 2 (video, id=66666666-6666-6666-6666-666666666666): empty\n"""
        result = broll_inserted(before, after, expected_clip_label="public_testsrc_45s")
        self.assertEqual(result.status, "pass")
        self.assertTrue(result.metadata["expected_clip_present"])

    def test_hook_structure_changed_fails_when_optimized_but_timeline_unchanged(self) -> None:
        state = """=== Editor State ===\nTracks (2):\n  Video (video, id=11111111-1111-1111-1111-111111111111): Source [id=22222222-2222-2222-2222-222222222222, 0.0s-20.0s]\n  Audio (audio, id=33333333-3333-3333-3333-333333333333): Source [id=44444444-4444-4444-4444-444444444444, 0.0s-20.0s]\n"""
        result = hook_structure_changed(state, state, "Hook optimized: moved 'Hello' to clip start.")
        self.assertEqual(result.status, "fail")

    def test_hook_structure_changed_passes_for_already_at_start(self) -> None:
        result = hook_structure_changed("", "", "Hook is already at the start (only 1 sentence in clip)")
        self.assertEqual(result.status, "pass")


class AggregationTests(unittest.TestCase):
    def test_optional_skipped_judge_does_not_block_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            config = _make_config(Path(tmp_dir))
            runner = EvaluationRunner(config, EvalStore(Path(tmp_dir) / "index.sqlite"))
            decision = runner._aggregate(  # noqa: SLF001
                [],
                [
                    JudgeResult("visual", "gemini", "rubric", "pass", 1.0, 0.95, "ok", metadata={"required": True}),
                    JudgeResult("visual", "twelvelabs", "rubric", "skipped", None, None, "rate limited", metadata={"required": False, "skip_reason": "rate_limited"}),
                ],
            )
            self.assertEqual(decision.status, "pass")


class ToolOutputValidationTests(unittest.TestCase):
    def test_default_error_detection_rejects_error_prefix(self) -> None:
        failure = validate_tool_output({"tool": "search_broll"}, "Error: PEXELS_API_KEY not configured.")
        self.assertEqual(failure, "Error: PEXELS_API_KEY not configured.")

    def test_default_error_detection_rejects_error_variant_prefix(self) -> None:
        failure = validate_tool_output({"tool": "import_media"}, "Error importing: Could not open media file sample.mkv.")
        self.assertEqual(failure, "Error importing: Could not open media file sample.mkv.")

    def test_expect_any_regex_accepts_alternative_success_shapes(self) -> None:
        failure = validate_tool_output(
            {"tool": "transcribe_asset", "expect_any_regex": [r"Transcribed:", r"Already transcribed\."]},
            "Already transcribed. Use get_transcript to read.",
        )
        self.assertIsNone(failure)


class WorkflowSelectionTests(unittest.TestCase):
    def test_select_items_respects_workflow_eligibility_tags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            manifest = {
                "name": "eval",
                "version": "2.0",
                "created": "2026-04-01T00:00:00Z",
                "description": "test",
                "splits": {"calibration": 2},
                "items": [
                    {
                        "id": "with-audio",
                        "source_family": "ava",
                        "relative_path": "ava_videos/a.mp4",
                        "media_type": "video",
                        "split": "calibration",
                        "content_tags": ["has-audio"],
                        "tasks": ["caption_overlay_suite"],
                        "annotations": {},
                        "expected": {},
                        "probe": {"has_audio": True},
                    },
                    {
                        "id": "silent",
                        "source_family": "pexels",
                        "relative_path": "pexels/b.mp4",
                        "media_type": "video",
                        "split": "calibration",
                        "content_tags": ["visual-only", "no-audio"],
                        "tasks": ["caption_overlay_suite"],
                        "annotations": {},
                        "expected": {},
                        "probe": {"has_audio": False},
                    },
                ],
            }
            (root / "manifest.json").write_text(json.dumps(manifest))
            manager = CorpusManager(root)
            workflow = WorkflowSpec(
                id="caption_overlay_suite",
                description="",
                eligibility_tags=["has-audio"],
                allowed_source_families=[],
                max_duration_seconds=None,
                max_duration_by_source_family={},
                declared_tools=[],
                steps=[],
                validators=[],
                judges=[],
            )
            items = manager.select_items(split="calibration", workflow_id="caption_overlay_suite", workflow=workflow)
            self.assertEqual([item.id for item in items], ["with-audio"])

    def test_select_items_respects_allowed_source_families(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            manifest = {
                "name": "eval",
                "version": "2.0",
                "created": "2026-04-01T00:00:00Z",
                "description": "test",
                "splits": {"calibration": 2},
                "items": [
                    {
                        "id": "ava-item",
                        "source_family": "ava",
                        "relative_path": "ava_videos/a.mp4",
                        "media_type": "video",
                        "split": "calibration",
                        "content_tags": ["has-audio"],
                        "tasks": ["broll_hook_suite"],
                        "annotations": {},
                        "expected": {},
                        "probe": {"has_audio": True, "duration_seconds": 500},
                    },
                    {
                        "id": "synthetic-item",
                        "source_family": "synthetic",
                        "relative_path": "synthetic/b.mp4",
                        "media_type": "video",
                        "split": "calibration",
                        "content_tags": ["has-audio"],
                        "tasks": ["broll_hook_suite"],
                        "annotations": {},
                        "expected": {},
                        "probe": {"has_audio": True, "duration_seconds": 60},
                    },
                ],
            }
            (root / "manifest.json").write_text(json.dumps(manifest))
            manager = CorpusManager(root)
            workflow = WorkflowSpec(
                id="broll_hook_suite",
                description="",
                eligibility_tags=["has-audio"],
                allowed_source_families=["ava", "tvsum"],
                max_duration_seconds=None,
                max_duration_by_source_family={"ava": 1200},
                declared_tools=[],
                steps=[],
                validators=[],
                judges=[],
            )
            items = manager.select_items(split="calibration", workflow_id="broll_hook_suite", workflow=workflow)
            self.assertEqual([item.id for item in items], ["ava-item"])

    def test_select_items_respects_source_family_duration_guardrail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            manifest = {
                "name": "eval",
                "version": "2.0",
                "created": "2026-04-02T00:00:00Z",
                "description": "test",
                "splits": {"calibration": 3},
                "items": [
                    {
                        "id": "ava-short",
                        "source_family": "ava",
                        "relative_path": "ava_videos/a.mp4",
                        "media_type": "video",
                        "split": "calibration",
                        "content_tags": ["has-audio"],
                        "tasks": ["caption_overlay_suite"],
                        "annotations": {},
                        "expected": {},
                        "probe": {"has_audio": True, "duration_seconds": 600},
                    },
                    {
                        "id": "ava-long",
                        "source_family": "ava",
                        "relative_path": "ava_videos/b.mp4",
                        "media_type": "video",
                        "split": "calibration",
                        "content_tags": ["has-audio"],
                        "tasks": ["caption_overlay_suite"],
                        "annotations": {},
                        "expected": {},
                        "probe": {"has_audio": True, "duration_seconds": 2400},
                    },
                    {
                        "id": "tvsum-short",
                        "source_family": "tvsum",
                        "relative_path": "tvsum/video/c.mp4",
                        "media_type": "video",
                        "split": "calibration",
                        "content_tags": ["has-audio"],
                        "tasks": ["caption_overlay_suite"],
                        "annotations": {},
                        "expected": {},
                        "probe": {"has_audio": True, "duration_seconds": 300},
                    },
                ],
            }
            (root / "manifest.json").write_text(json.dumps(manifest))
            manager = CorpusManager(root)
            workflow = WorkflowSpec(
                id="caption_overlay_suite",
                description="",
                eligibility_tags=["has-audio"],
                allowed_source_families=[],
                max_duration_seconds=None,
                max_duration_by_source_family={"ava": 1200},
                declared_tools=[],
                steps=[],
                validators=[],
                judges=[],
            )
            items = manager.select_items(split="calibration", workflow_id="caption_overlay_suite", workflow=workflow)
            self.assertEqual([item.id for item in items], ["ava-short", "tvsum-short"])


def _make_config(
    tmp_root: Path,
    *,
    primary_judges: tuple[str, ...] = ("gemini",),
    optional_judges: tuple[str, ...] = ("twelvelabs",),
    required_splits: tuple[str, ...] = ("calibration", "holdout"),
    optional_splits: tuple[str, ...] = ("holdout",),
) -> EvalConfig:
    return EvalConfig(
        repo_root=tmp_root,
        tools_root=tmp_root,
        corpus_root=tmp_root,
        eval_root=tmp_root,
        runs_root=tmp_root / "runs",
        baseline_root=tmp_root / "baselines",
        artifact_root=tmp_root / "artifacts",
        db_path=tmp_root / "index.sqlite",
        workflow_root=tmp_root / "workflows",
        sandbox_root=tmp_root / "sandbox",
        staging_root=tmp_root / "staging",
        mcp_url="http://127.0.0.1:8420",
        stale_coverage_days=30,
        gemini_api_key=None,
        gemini_model="gemini-3-pro-preview",
        twelvelabs_api_key=None,
        twelvelabs_index_id=None,
        judge_required_splits=required_splits,
        judge_optional_splits=optional_splits,
        primary_judge_providers=primary_judges,
        optional_judge_providers=optional_judges,
        dashboard_host="127.0.0.1",
        dashboard_port=8765,
    )


if __name__ == "__main__":
    unittest.main()
