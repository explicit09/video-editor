from __future__ import annotations

import json
import re
import shutil
import uuid
import hashlib
import time
from pathlib import Path
from typing import Any

from .config import EvalConfig
from .corpus import CorpusManager, SandboxStager, ValidationReport, infer_tasks
from .judges import JudgeGateway
from .mcp import MCPClient, RecordingMCPClient
from .models import ArtifactRecord, FinalDecision, JudgeResult, JudgeTask, WorkflowSpec
from .storage import EvalStore
from .utils import load_json, parse_broll_suggestions, parse_editor_state, parse_output_path, parse_snapshot_list, resolve_template, utc_timestamp, write_json
from .validators import (
    audio_present,
    broll_inserted,
    duration_sanity,
    export_exists,
    hook_applied,
    hook_structure_changed,
    no_black_frames,
    screenshot_baseline,
    timeline_changed,
    transcript_present,
    verify_playback_clean,
    verify_playback_post_edit_integrity,
)


def _load_image_stack():
    try:
        from PIL import Image, ImageChops
        import cv2
        import numpy as np
    except ImportError:
        return None
    return Image, ImageChops, cv2, np


def compute_phash(image_path: Path) -> int:
    image_stack = _load_image_stack()
    if image_stack is None:
        return int(hashlib.sha256(image_path.read_bytes()).hexdigest()[:16], 16)
    Image, _, cv2, np = image_stack
    image = Image.open(image_path).convert("L").resize((32, 32), Image.Resampling.LANCZOS)
    matrix = np.array(image, dtype=np.float32)
    dct = cv2.dct(matrix)
    block = dct[:8, :8]
    median = np.median(block[1:, 1:])
    bits = (block > median).astype(np.uint8).flatten()
    value = 0
    for bit in bits:
        value = (value << 1) | int(bit)
    return value


def compare_images(capture_path: Path, baseline_path: Path) -> tuple[int, float, Path]:
    diff_path = capture_path.with_name(f"{capture_path.stem}-diff.png")
    image_stack = _load_image_stack()
    if image_stack is None:
        if capture_path.read_bytes() == baseline_path.read_bytes():
            shutil.copy2(capture_path, diff_path)
            return 0, 0.0, diff_path
        shutil.copy2(capture_path, diff_path)
        return bin(compute_phash(capture_path) ^ compute_phash(baseline_path)).count("1"), 255.0, diff_path
    Image, ImageChops, _, np = image_stack
    lhs = Image.open(capture_path).convert("RGBA")
    rhs = Image.open(baseline_path).convert("RGBA")
    if lhs.size != rhs.size:
        rhs = rhs.resize(lhs.size, Image.Resampling.LANCZOS)
    lhs_arr = np.array(lhs, dtype=np.float32)
    rhs_arr = np.array(rhs, dtype=np.float32)
    mad = float(np.abs(lhs_arr - rhs_arr).mean())
    diff = ImageChops.difference(lhs, rhs)
    diff.save(diff_path)
    return bin(compute_phash(capture_path) ^ compute_phash(baseline_path)).count("1"), mad, diff_path


def validate_tool_output(step: dict[str, Any], output: str) -> str | None:
    text = output.strip()
    if not step.get("allow_error_output", False) and not step.get("disable_default_error_detection", False):
        if re.match(r"^Error\b", text):
            return text

    for needle in step.get("reject_any", []):
        if needle in output:
            return f"Rejected output matched substring '{needle}'"
    for pattern in step.get("reject_any_regex", []):
        if re.search(pattern, output, flags=re.MULTILINE):
            return f"Rejected output matched regex '{pattern}'"

    expect_any = step.get("expect_any", [])
    if expect_any and not any(needle in output for needle in expect_any):
        return f"Output did not contain any expected substring: {expect_any}"
    expect_any_regex = step.get("expect_any_regex", [])
    if expect_any_regex and not any(re.search(pattern, output, flags=re.MULTILINE) for pattern in expect_any_regex):
        return f"Output did not match any expected regex: {expect_any_regex}"

    return None


class EvaluationRunner:
    def __init__(self, config: EvalConfig, store: EvalStore) -> None:
        self.config = config
        self.store = store
        self.corpus = CorpusManager(config.corpus_root)
        self.stager = SandboxStager(config.staging_root)
        self.judges = JudgeGateway(config, store)

    @staticmethod
    def _manifest_needs_repair(manifest) -> bool:
        if manifest.version != "2.0":
            return True
        for item in manifest.items:
            if not item.probe or item.source_family == "unknown":
                return True
            has_audio = item.probe.get("has_audio")
            tag_set = set(item.content_tags)
            if has_audio is True and "has-audio" not in tag_set:
                return True
            if has_audio is False and not {"no-audio", "visual-only"}.issubset(tag_set):
                return True
            inferred = set(infer_tasks(item.source_family, item.media_type, item.content_tags))
            if not inferred.issubset(set(item.tasks)):
                return True
        return False

    def sync_corpus(self, repair: bool = False, validate: bool = True):
        if not self.corpus.manifest_path.exists():
            manifest = self.corpus.repair_manifest()
        else:
            manifest = self.corpus.load_manifest()
            if repair or self._manifest_needs_repair(manifest):
                manifest = self.corpus.repair_manifest()
        report = self.corpus.validate_manifest(manifest) if validate else ValidationReport(ok=True, errors=[], warnings=[], orphans=[])
        if repair and validate and not report.ok:
            manifest = self.corpus.repair_manifest()
            report = self.corpus.validate_manifest(manifest)
        self.store.sync_corpus_items(manifest)
        return manifest, report

    def sync_tool_inventory(self):
        client = MCPClient(self.config.mcp_url, session_name="videoeditor-eval-inventory")
        tools = client.list_tools()
        self.store.sync_tool_inventory(tools)
        return tools

    def load_workflow(self, workflow_id: str) -> WorkflowSpec:
        path = self.config.workflow_root / f"{workflow_id}.json"
        return WorkflowSpec.from_dict(load_json(path))

    def enqueue(self, workflow_id: str, *, split: str | None = None, source_family: str | None = None, limit: int | None = None) -> list[str]:
        self.sync_corpus(validate=False)
        workflow = self.load_workflow(workflow_id)
        self.store.sync_declared_coverage(workflow)
        run_ids: list[str] = []
        for item in self.corpus.select_items(split=split, workflow_id=workflow_id, workflow=workflow, source_family=source_family, limit=limit):
            run_id = f"{workflow_id}-{item.id}-{uuid.uuid4().hex[:8]}"
            self.store.create_run(run_id, workflow_id, item.id, status="queued")
            run_ids.append(run_id)
        return run_ids

    def run_queued(self, limit: int | None = None) -> list[str]:
        completed: list[str] = []
        while True:
            if limit is not None and len(completed) >= limit:
                break
            row = self.store.claim_next_queued_run()
            if row is None:
                break
            self.run_one(row["run_id"], row["workflow_id"], row["corpus_item_id"])
            completed.append(row["run_id"])
        return completed

    def run_one(self, run_id: str, workflow_id: str, corpus_item_id: str) -> FinalDecision:
        manifest = self.corpus.load_manifest()
        items_by_id = {item.id: item for item in manifest.items}
        corpus_item = items_by_id[corpus_item_id]
        workflow = self.load_workflow(workflow_id)
        self.store.mark_run_started(run_id)
        run_dir = self.config.runs_root / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        client = RecordingMCPClient(self.config.mcp_url, session_name=f"eval-{workflow_id}")
        tool_inventory = client.list_tools()
        self.store.sync_tool_inventory(tool_inventory)
        self.store.sync_declared_coverage(workflow)

        context: dict[str, Any] = {
            "corpus": {
                "id": corpus_item.id,
                "filename": corpus_item.filename,
                "relative_path": corpus_item.relative_path,
                "abs_path": str(self.config.corpus_root / corpus_item.relative_path),
                "source_family": corpus_item.source_family,
                "split": corpus_item.split,
            },
            "config": {
                "repo_root": str(self.config.repo_root),
                "tools_root": str(self.config.tools_root),
                "eval_root": str(self.config.eval_root),
                "workflow_root": str(self.config.workflow_root),
                "baseline_root": str(self.config.baseline_root),
            },
            "run": {
                "id": run_id,
                "dir": str(run_dir),
                "workflow_id": workflow_id,
            },
            "context": {},
        }
        outputs: dict[str, str] = {}
        artifacts: dict[str, ArtifactRecord] = {}
        decision = FinalDecision(status="quarantine", reasons=["Run did not complete"])
        try:
            for index, step in enumerate(workflow.steps):
                output = self._execute_step(index, step, client, corpus_item, run_dir, context, outputs, artifacts)
                outputs[step.get("id", f"step_{index}")] = output or ""
            validators = self._run_validators(workflow, corpus_item, outputs, artifacts)
            for result in validators:
                self.store.record_validator_result(run_id, result)
            judge_results = self._run_judges(workflow, corpus_item, artifacts)
            for result in judge_results:
                self.store.record_judge_result(run_id, result)
            decision = self._aggregate(validators, judge_results)
        except Exception as exc:  # noqa: BLE001
            decision = FinalDecision(status="fail", reasons=[f"Run raised exception: {exc}"])
            self.store.record_step(
                run_id=context["run"]["id"],
                step_index=len(workflow.steps),
                step_name="run_exception",
                status="fail",
                output_text=str(exc),
                metadata={"op": "exception"},
            )
        finally:
            self.stager.cleanup(corpus_item.id)
        for tool_name in client.observed_tools:
            self.store.record_observed_tool(workflow_id, tool_name, run_id, decision.status)
        self.store.finalize_run(run_id, decision)
        write_json(run_dir / "final_decision.json", decision.to_dict())
        return decision

    def _execute_step(
        self,
        index: int,
        step: dict[str, Any],
        client: RecordingMCPClient,
        corpus_item,
        run_dir: Path,
        context: dict[str, Any],
        outputs: dict[str, str],
        artifacts: dict[str, ArtifactRecord],
    ) -> str:
        step_id = step.get("id", f"step_{index}")
        op = step["op"]
        when_context = step.get("when_context")
        if when_context:
            keys = when_context if isinstance(when_context, list) else [when_context]
            if any((context["context"].get(key) is None or context["context"].get(key) == "") for key in keys):
                output = f"Skipped {step_id}: missing context dependency"
                self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op, "skipped": True, "when_context": keys})
                return output
        if op == "stage_corpus_asset":
            staged = self.stager.stage(corpus_item, self.config.corpus_root)
            context["context"]["staged_file_path"] = str(staged)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=str(staged), metadata={"op": op})
            return str(staged)
        if op == "stage_local_file":
            source = Path(resolve_template(step["path"], context))
            staged = self.stager.stage_path(corpus_item.id, source, step.get("filename"))
            target_var = step.get("var", "staged_local_file_path")
            context["context"][target_var] = str(staged)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=str(staged), metadata={"op": op, "source": str(source), "var": target_var})
            return str(staged)
        if op == "sleep":
            seconds = float(step.get("seconds", 1))
            time.sleep(seconds)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=f"slept {seconds:.2f}s", metadata={"op": op, "seconds": seconds})
            return f"slept {seconds:.2f}s"
        if op == "snapshot_assets":
            timeline = client.read_resource("editor://timeline")
            context["context"][step["var"]] = {asset["id"]: asset for asset in timeline.get("assets", [])}
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=f"{len(context['context'][step['var']])} assets", metadata={"op": op})
            return ""
        if op == "capture_editor_state":
            output = client.call_tool("get_state", {}, timeout=int(step.get("timeout_seconds", 120)))
            parsed = parse_editor_state(output)
            context["context"][step["var"]] = parsed
            self.store.record_step(
                run_id=context["run"]["id"],
                step_index=index,
                step_name=step_id,
                tool_name="get_state",
                status="pass",
                output_text=output,
                metadata={"op": op, "parsed_tracks": len(parsed["tracks"]), "parsed_markers": len(parsed["markers"])},
            )
            return output
        if op == "select_track":
            state = context["context"][step["state_var"]]
            tracks = list(state.get("tracks", []))
            if "type" in step:
                tracks = [track for track in tracks if track["type"] == step["type"]]
            if "name_contains" in step:
                needle = step["name_contains"].lower()
                tracks = [track for track in tracks if needle in track["name"].lower()]
            if not tracks:
                if step.get("optional"):
                    context["context"][step["var"]] = None
                    output = "{}"
                    self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op, "skipped": True, "optional": True})
                    return output
                raise RuntimeError(f"No matching track found for step {step_id}")
            index_value = int(step.get("index", 0))
            selected = tracks[index_value] if index_value >= 0 else tracks[len(tracks) + index_value]
            context["context"][step["var"]] = selected
            output = json.dumps(selected)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op})
            return output
        if op == "select_clip":
            state = context["context"][step["state_var"]]
            if "track_var" in step:
                track_ref = context["context"].get(step["track_var"])
                if track_ref is None:
                    if step.get("optional"):
                        context["context"][step["var"]] = None
                        output = "{}"
                        self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op, "skipped": True, "optional": True})
                        return output
                    raise RuntimeError(f"No track context found for step {step_id}")
                track_id = track_ref["id"]
                tracks = [track for track in state.get("tracks", []) if track["id"] == track_id]
            elif "track_type" in step:
                tracks = [track for track in state.get("tracks", []) if track["type"] == step["track_type"]]
            else:
                tracks = list(state.get("tracks", []))
            clips: list[dict[str, Any]] = []
            for track in tracks:
                for clip in track.get("clips", []):
                    clips.append(dict(clip, track_id=track["id"], track_name=track["name"], track_type=track["type"]))
            if "label_contains" in step:
                needle = step["label_contains"].lower()
                clips = [clip for clip in clips if needle in clip["label"].lower()]
            if not clips:
                if step.get("optional"):
                    context["context"][step["var"]] = None
                    output = "{}"
                    self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op, "skipped": True, "optional": True})
                    return output
                raise RuntimeError(f"No matching clip found for step {step_id}")
            clips = sorted(clips, key=lambda clip: (clip["start"], clip["end"], clip["id"]))
            index_value = int(step.get("index", 0))
            selected = clips[index_value] if index_value >= 0 else clips[len(clips) + index_value]
            context["context"][step["var"]] = selected
            output = json.dumps(selected)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op})
            return output
        if op == "select_adjacent_clips":
            state = context["context"][step["state_var"]]
            if "track_var" in step:
                track_id = context["context"][step["track_var"]]["id"]
                tracks = [track for track in state.get("tracks", []) if track["id"] == track_id]
            elif "track_type" in step:
                tracks = [track for track in state.get("tracks", []) if track["type"] == step["track_type"]]
            else:
                tracks = list(state.get("tracks", []))
            if not tracks:
                raise RuntimeError(f"No track available for adjacent clip selection in step {step_id}")
            track = tracks[0]
            clips = sorted(track.get("clips", []), key=lambda clip: (clip["start"], clip["end"], clip["id"]))
            if len(clips) < 2:
                raise RuntimeError(f"Need at least two clips on a track for step {step_id}")
            pair_index = int(step.get("index", 0))
            left = dict(clips[pair_index], track_id=track["id"], track_name=track["name"], track_type=track["type"])
            right = dict(clips[pair_index + 1], track_id=track["id"], track_name=track["name"], track_type=track["type"])
            context["context"][step["left_var"]] = left
            context["context"][step["right_var"]] = right
            output = json.dumps({"left": left, "right": right})
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op})
            return output
        if op == "select_marker":
            state = context["context"][step["state_var"]]
            markers = list(state.get("markers", []))
            if "label_contains" in step:
                needle = step["label_contains"].lower()
                markers = [marker for marker in markers if needle in marker["label"].lower()]
            if not markers:
                raise RuntimeError(f"No matching marker found for step {step_id}")
            index_value = int(step.get("index", 0))
            selected = markers[index_value] if index_value >= 0 else markers[len(markers) + index_value]
            context["context"][step["var"]] = selected
            output = json.dumps(selected)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op})
            return output
        if op == "select_snapshot":
            snapshots = parse_snapshot_list(outputs.get(step["source"], ""))
            if "name_contains" in step:
                needle = step["name_contains"].lower()
                snapshots = [snapshot for snapshot in snapshots if needle in snapshot["name"].lower()]
            if not snapshots:
                raise RuntimeError(f"No matching snapshot found for step {step_id}")
            index_value = int(step.get("index", 0))
            selected = snapshots[index_value] if index_value >= 0 else snapshots[len(snapshots) + index_value]
            context["context"][step["var"]] = selected
            output = json.dumps(selected)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op})
            return output
        if op == "select_broll_suggestion":
            suggestions = parse_broll_suggestions(outputs.get(step["source"], ""))
            if not suggestions:
                if step.get("optional"):
                    context["context"][step["var"]] = None
                    output = "{}"
                    self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op, "skipped": True, "optional": True})
                    return output
                raise RuntimeError(f"No B-roll suggestions found for step {step_id}")
            index_value = int(step.get("index", 0))
            selected = suggestions[index_value] if index_value >= 0 else suggestions[len(suggestions) + index_value]
            context["context"][step["var"]] = selected
            output = json.dumps(selected)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op})
            return output
        if op == "resolve_imported_asset":
            before = context["context"].get(step["from"], {})
            asset = None
            filename = corpus_item.filename or Path(corpus_item.relative_path).name
            stem = Path(filename).stem.replace("_", " ").replace("-", " ")
            for _ in range(int(step.get("retries", 6))):
                after = client.read_resource("editor://timeline").get("assets", [])
                diff = [candidate for candidate in after if candidate["id"] not in before]
                if diff:
                    asset = diff[-1]
                    break
                for candidate in after:
                    normalized = candidate["name"].lower().replace("_", " ").replace("-", " ")
                    if normalized in stem.lower() or stem.lower() in normalized:
                        asset = candidate
                        break
                if asset is not None:
                    break
                time.sleep(float(step.get("retry_delay_seconds", 0.5)))
            if asset is None:
                raise RuntimeError(f"Unable to resolve imported asset for {corpus_item.id}")
            context["context"][step.get("var", "asset")] = asset
            output = json.dumps(asset)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, status="pass", output_text=output, metadata={"op": op})
            return output
        if op == "tool":
            args = resolve_template(step.get("args", {}), context)
            output = client.call_tool(step["tool"], args, timeout=int(step.get("timeout_seconds", 180)))
            failure = validate_tool_output(step, output)
            if failure:
                self.store.record_step(
                    run_id=context["run"]["id"],
                    step_index=index,
                    step_name=step_id,
                    tool_name=step["tool"],
                    status="fail",
                    output_text=output,
                    metadata={"op": op, "args": args, "failure": failure},
                )
                raise RuntimeError(f"{step['tool']} failed validation: {failure}")
            save_key = step.get("save_as")
            if save_key:
                context["context"][save_key] = output
            parsed_path = parse_output_path(output)
            if parsed_path is not None:
                artifact = ArtifactRecord(
                    label=save_key or f"{step['tool']}_output",
                    path=str(parsed_path),
                    kind="file",
                    metadata={"tool": step["tool"]},
                )
                artifacts[artifact.label] = artifact
                self.store.record_artifact(context["run"]["id"], artifact)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, tool_name=step["tool"], status="pass", output_text=output, metadata={"op": op, "args": args})
            return output
        if op == "capture":
            if "zoom" in step:
                client.call_tool("set_zoom", {"level": step["zoom"]}, timeout=60)
            output = client.call_tool("take_screenshot", {}, timeout=60)
            screenshot_path = parse_output_path(output)
            if screenshot_path is None:
                raise RuntimeError(f"Could not parse screenshot path from output: {output}")
            label = step["label"]
            destination = run_dir / f"{label}.png"
            shutil.copy2(screenshot_path, destination)
            artifact = ArtifactRecord(label=label, path=str(destination), kind="image", metadata={"source": str(screenshot_path)})
            artifacts[label] = artifact
            self.store.record_artifact(context["run"]["id"], artifact)
            self.store.record_step(run_id=context["run"]["id"], step_index=index, step_name=step_id, tool_name="take_screenshot", status="pass", output_text=output, metadata={"op": op})
            return output
        raise RuntimeError(f"Unknown step op: {op}")

    def _run_validators(self, workflow: WorkflowSpec, corpus_item, outputs: dict[str, str], artifacts: dict[str, ArtifactRecord]):
        results = []
        for validator in workflow.validators:
            validator_id = validator["id"]
            if validator_id == "verify_playback_clean":
                results.append(verify_playback_clean(outputs.get(validator["source"], "")))
            elif validator_id == "verify_playback_post_edit_integrity":
                results.append(verify_playback_post_edit_integrity(outputs.get(validator["source"], "")))
            elif validator_id == "transcript_present":
                results.append(transcript_present(outputs.get(validator["source"], "")))
            elif validator_id == "export_exists":
                artifact = artifacts.get(validator["artifact"])
                results.append(export_exists(Path(artifact.path) if artifact else None))
            elif validator_id == "duration_sanity":
                artifact = artifacts.get(validator["artifact"])
                results.append(duration_sanity(Path(artifact.path) if artifact else None, validator.get("minimum_seconds", 1.0)))
            elif validator_id == "audio_present":
                artifact = artifacts.get(validator["artifact"])
                expected_has_audio = None
                if validator.get("expected_from_probe", False):
                    expected_has_audio = corpus_item.probe.get("has_audio")
                results.append(
                    audio_present(
                        Path(artifact.path) if artifact else None,
                        validator.get("required", True),
                        expected_has_audio=expected_has_audio,
                    )
                )
            elif validator_id == "no_black_frames":
                artifact = artifacts.get(validator["artifact"])
                results.append(no_black_frames(Path(artifact.path) if artifact else None))
            elif validator_id == "timeline_changed":
                before_key = validator.get("before_source", "state_before")
                after_key = validator.get("after_source", "state_after")
                results.append(timeline_changed(outputs.get(before_key, ""), outputs.get(after_key, "")))
            elif validator_id == "broll_inserted":
                results.append(
                    broll_inserted(
                        outputs.get(validator.get("before_source", "state_before_broll"), ""),
                        outputs.get(validator.get("after_source", "state_after_broll"), ""),
                        validator.get("expected_clip_label"),
                    )
                )
            elif validator_id == "hook_applied":
                results.append(hook_applied(outputs.get(validator.get("source", "hook_optimize"), "")))
            elif validator_id == "hook_structure_changed":
                results.append(
                    hook_structure_changed(
                        outputs.get(validator.get("before_source", "state_before_hook"), ""),
                        outputs.get(validator.get("after_source", "state_after_hook"), ""),
                        outputs.get(validator.get("source", "hook_optimize"), ""),
                    )
                )
            elif validator_id == "screenshot_baseline":
                artifact = artifacts.get(validator["artifact"])
                baseline_path = self.config.baseline_root / validator["baseline"]
                results.append(
                    screenshot_baseline(
                        artifact,
                        baseline_path,
                        comparator=compare_images,
                        accept_new=bool(validator.get("accept_new", False)),
                        phash_max_distance=int(validator.get("phash_max_distance", 8)),
                        mean_abs_diff_max=float(validator.get("mean_abs_diff_max", 8.0)),
                    )
                )
        return results

    def _run_judges(self, workflow: WorkflowSpec, corpus_item, artifacts: dict[str, ArtifactRecord]) -> list[JudgeResult]:
        results: list[JudgeResult] = []
        for judge in workflow.judges:
            task = JudgeTask(
                judge_id=judge["id"],
                rubric_id=judge["rubric_id"],
                prompt=judge["prompt"],
                artifact_labels=judge["artifact_labels"],
                metadata=judge.get("metadata", {}),
            )
            evidence_paths = [Path(artifacts[label].path) for label in task.artifact_labels if label in artifacts]
            results.extend(self.judges.evaluate(task, evidence_paths, split=corpus_item.split))
        return results

    def _aggregate(self, validator_results, judge_results) -> FinalDecision:
        reasons: list[str] = []
        if any(result.status == "fail" for result in validator_results):
            reasons.extend(result.details for result in validator_results if result.status == "fail")
            return FinalDecision(status="fail", reasons=reasons)
        if any(result.status == "fail" for result in judge_results):
            reasons.extend(result.explanation for result in judge_results if result.status == "fail")
            return FinalDecision(status="fail", reasons=reasons)
        required_results = [result for result in judge_results if result.metadata.get("required", True)]
        blocking_required = [
            result
            for result in required_results
            if result.status in {"quarantine", "unavailable"}
            or (result.status == "skipped" and result.metadata.get("skip_reason") != "split_policy")
        ]
        if blocking_required:
            reasons.extend(result.explanation for result in blocking_required)
            return FinalDecision(status="quarantine", reasons=reasons or ["Required judge uncertainty"])
        if any((result.confidence is not None and result.confidence < 0.7) for result in required_results):
            reasons.extend(result.explanation for result in required_results if result.confidence is not None and result.confidence < 0.7)
            return FinalDecision(status="quarantine", reasons=reasons or ["Low judge confidence"])
        return FinalDecision(status="pass", reasons=["All validators and judges passed"])
