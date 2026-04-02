#!/usr/bin/env python3
"""Scenario-driven MCP visual harness for VideoEditor.

This is intentionally not production infrastructure. It is a repeatable QA
runner for high-volume editor checks:

- drive the app through MCP tools
- assert deterministic tool/resource expectations
- capture screenshots
- compare screenshots against approved baselines
- emit machine-readable artifacts so regressions can be triaged later
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import shutil
import sys
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib import request

from eval_system.config import load_config
from eval_system.runner import EvaluationRunner
from eval_system.service import EvalHTTPServer
from eval_system.storage import EvalStore


DEFAULT_MCP_URL = "http://127.0.0.1:8420"
SCENARIO_COMMAND = "scenario"


class HarnessError(RuntimeError):
    pass


def _load_image_stack():
    try:
        from PIL import Image, ImageChops
        import cv2
        import numpy as np
    except ImportError:
        return None
    return Image, ImageChops, cv2, np


def utc_timestamp() -> str:
    return dt.datetime.utcnow().strftime("%Y%m%d-%H%M%S")


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def parse_screenshot_path(output: str) -> Path:
    match = re.search(r"Screenshot saved to:\s*(.+)", output)
    if not match:
        raise HarnessError(f"Could not parse screenshot path from output:\n{output}")
    return Path(match.group(1).strip())


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


def hamming_distance(lhs: int, rhs: int) -> int:
    return bin(int(lhs) ^ int(rhs)).count("1")


def mean_absolute_difference(lhs_path: Path, rhs_path: Path) -> float:
    image_stack = _load_image_stack()
    if image_stack is None:
        return 0.0 if lhs_path.read_bytes() == rhs_path.read_bytes() else 255.0
    Image, _, _, np = image_stack
    lhs = Image.open(lhs_path).convert("RGBA")
    rhs = Image.open(rhs_path).convert("RGBA")
    if lhs.size != rhs.size:
        rhs = rhs.resize(lhs.size, Image.Resampling.LANCZOS)
    lhs_arr = np.array(lhs, dtype=np.float32)
    rhs_arr = np.array(rhs, dtype=np.float32)
    return float(np.abs(lhs_arr - rhs_arr).mean())


def write_diff_image(lhs_path: Path, rhs_path: Path, destination: Path) -> None:
    image_stack = _load_image_stack()
    if image_stack is None:
        shutil.copy2(lhs_path, destination)
        return
    Image, ImageChops, _, _ = image_stack
    lhs = Image.open(lhs_path).convert("RGBA")
    rhs = Image.open(rhs_path).convert("RGBA")
    if lhs.size != rhs.size:
        rhs = rhs.resize(lhs.size, Image.Resampling.LANCZOS)
    diff = ImageChops.difference(lhs, rhs)
    diff.save(destination)


class MCPClient:
    def __init__(self, url: str) -> None:
        self.url = url
        self._initialize()

    def _post(self, payload: dict[str, Any], timeout: int = 120) -> dict[str, Any]:
        data = json.dumps(payload).encode("utf-8")
        req = request.Request(
            self.url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with request.urlopen(req, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))

    def _initialize(self) -> None:
        self._post(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "clientInfo": {"name": "mcp-visual-harness", "version": "0.1"},
                    "capabilities": {},
                },
            }
        )
        self._post({"jsonrpc": "2.0", "id": 2, "method": "notifications/initialized"})

    def call_tool(self, name: str, arguments: dict[str, Any] | None = None, timeout: int = 180) -> str:
        response = self._post(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": name, "arguments": arguments or {}},
            },
            timeout=timeout,
        )
        return "".join(
            item.get("text", "")
            for item in response.get("result", {}).get("content", [])
            if item.get("type") == "text"
        )

    def read_resource(self, uri: str, timeout: int = 60) -> Any:
        response = self._post(
            {
                "jsonrpc": "2.0",
                "id": 4,
                "method": "resources/read",
                "params": {"uri": uri},
            },
            timeout=timeout,
        )
        contents = response.get("result", {}).get("contents", [])
        if not contents:
            raise HarnessError(f"Resource {uri} returned no contents")
        return json.loads(contents[0]["text"])


@dataclass
class StepResult:
    label: str
    passed: bool
    output: str | None = None
    details: list[str] = field(default_factory=list)
    artifact_paths: list[str] = field(default_factory=list)


@dataclass
class ScenarioResult:
    name: str
    passed: bool
    step_results: list[StepResult]
    artifact_dir: str


class ScenarioRunner:
    def __init__(
        self,
        client: MCPClient,
        baseline_root: Path,
        artifact_root: Path,
        accept_new: bool,
    ) -> None:
        self.client = client
        self.baseline_root = baseline_root
        self.artifact_root = artifact_root
        self.accept_new = accept_new
        self.context: dict[str, Any] = {"vars": {}, "assets_by_alias": {}, "assets_by_name": {}}

    def run_file(self, path: Path) -> ScenarioResult:
        scenario = json.loads(path.read_text())
        scenario_name = scenario["name"]
        scenario_slug = slugify(scenario_name)
        artifact_dir = self.artifact_root / f"{utc_timestamp()}-{scenario_slug}"
        artifact_dir.mkdir(parents=True, exist_ok=True)

        timeline = self.client.read_resource("editor://timeline")
        assets = timeline.get("assets", [])
        self.context["assets_by_name"] = {asset["name"]: asset["id"] for asset in assets}
        self.context["assets_by_alias"] = {}
        for alias, name in scenario.get("assets", {}).items():
            asset_id = self.context["assets_by_name"].get(name)
            if not asset_id:
                raise HarnessError(f"Scenario asset alias '{alias}' references missing asset '{name}'")
            self.context["assets_by_alias"][alias] = asset_id

        step_results: list[StepResult] = []
        for index, step in enumerate(scenario.get("steps", []), start=1):
            label = step.get("name") or step.get("tool") or step.get("capture") or f"step-{index}"
            result = self._run_step(step, label, artifact_dir, scenario_slug)
            step_results.append(result)
            if not result.passed:
                break

        scenario_passed = all(step.passed for step in step_results)
        report = ScenarioResult(
            name=scenario_name,
            passed=scenario_passed,
            step_results=step_results,
            artifact_dir=str(artifact_dir),
        )
        report_path = artifact_dir / "report.json"
        report_path.write_text(json.dumps(report, default=lambda o: o.__dict__, indent=2))
        return report

    def _run_step(self, step: dict[str, Any], label: str, artifact_dir: Path, scenario_slug: str) -> StepResult:
        details: list[str] = []
        artifact_paths: list[str] = []
        output = ""

        try:
            if "tool" in step:
                args = self._resolve_value(step.get("args", {}))
                timeout = int(step.get("timeout_seconds", 180))
                output = self.client.call_tool(step["tool"], args, timeout=timeout)
                self.context["last_output"] = output
                details.append(f"tool={step['tool']}")

            if "capture" in step:
                if zoom := step.get("zoom"):
                    self.client.call_tool("set_zoom", {"level": zoom}, timeout=60)
                screenshot_output = self.client.call_tool("take_screenshot", {}, timeout=60)
                screenshot_path = parse_screenshot_path(screenshot_output)
                capture_name = slugify(step["capture"])
                captured_artifact = artifact_dir / f"{capture_name}.png"
                shutil.copy2(screenshot_path, captured_artifact)
                artifact_paths.append(str(captured_artifact))
                output = f"{output}\n{screenshot_output}".strip()
                self.context["last_capture"] = captured_artifact
                details.append(f"capture={capture_name}")

            expectation_failures = self._evaluate_expectations(
                step.get("expect", {}),
                output=output,
                artifact_dir=artifact_dir,
                scenario_slug=scenario_slug,
            )
            passed = not expectation_failures
            details.extend(expectation_failures if expectation_failures else ["expectations passed"])
            return StepResult(
                label=label,
                passed=passed,
                output=output,
                details=details,
                artifact_paths=artifact_paths,
            )
        except Exception as exc:  # noqa: BLE001
            details.append(f"exception: {exc}")
            return StepResult(
                label=label,
                passed=False,
                output=output,
                details=details,
                artifact_paths=artifact_paths,
            )

    def _evaluate_expectations(
        self,
        expect: dict[str, Any],
        output: str,
        artifact_dir: Path,
        scenario_slug: str,
    ) -> list[str]:
        failures: list[str] = []

        for needle in expect.get("output_contains", []):
            if needle not in output:
                failures.append(f"missing output text: {needle}")

        for needle in expect.get("output_not_contains", []):
            if needle in output:
                failures.append(f"unexpected output text: {needle}")

        if expect.get("verify_no_failures"):
            if "[FAIL]" in output:
                failures.append("verify_playback output contains [FAIL]")

        timeline_expect = expect.get("timeline")
        if timeline_expect:
            timeline_resource = self.client.read_resource("editor://timeline")
            timeline = timeline_resource["timeline"]
            actual = {
                "trackCount": timeline["trackCount"],
                "markerCount": timeline["markerCount"],
                "clipCount": sum(track["clipCount"] for track in timeline["tracks"]),
                "duration": timeline["duration"],
            }
            for key, expected_value in timeline_expect.items():
                actual_value = actual.get(key)
                if isinstance(expected_value, float):
                    if actual_value is None or abs(actual_value - expected_value) > 0.1:
                        failures.append(f"timeline {key} expected {expected_value}, got {actual_value}")
                elif actual_value != expected_value:
                    failures.append(f"timeline {key} expected {expected_value}, got {actual_value}")

        baseline_rel = expect.get("baseline")
        if baseline_rel:
            capture_path: Path | None = self.context.get("last_capture")
            if not capture_path:
                failures.append("baseline comparison requested without a capture step")
            else:
                baseline_path = self.baseline_root / baseline_rel
                baseline_path.parent.mkdir(parents=True, exist_ok=True)
                if not baseline_path.exists():
                    if self.accept_new:
                        shutil.copy2(capture_path, baseline_path)
                    else:
                        failures.append(f"missing baseline: {baseline_path}")
                        return failures

                phash_distance = hamming_distance(compute_phash(capture_path), compute_phash(baseline_path))
                mad = mean_absolute_difference(capture_path, baseline_path)
                max_phash = int(expect.get("phash_max_distance", 8))
                max_mad = float(expect.get("mean_abs_diff_max", 8.0))

                if phash_distance > max_phash:
                    failures.append(f"pHash distance {phash_distance} > {max_phash}")
                if mad > max_mad:
                    failures.append(f"mean absolute diff {mad:.2f} > {max_mad:.2f}")
                if failures:
                    diff_path = artifact_dir / f"{scenario_slug}-{capture_path.stem}-diff.png"
                    write_diff_image(capture_path, baseline_path, diff_path)

        return failures

    def _resolve_value(self, value: Any) -> Any:
        if isinstance(value, dict):
            if "$asset" in value:
                alias = value["$asset"]
                asset_id = self.context["assets_by_alias"].get(alias)
                if not asset_id:
                    raise HarnessError(f"Unknown asset alias: {alias}")
                return asset_id
            if "$asset_name" in value:
                name = value["$asset_name"]
                asset_id = self.context["assets_by_name"].get(name)
                if not asset_id:
                    raise HarnessError(f"Unknown asset name: {name}")
                return asset_id
            if "$uuid" in value:
                key = value["$uuid"]
                existing = self.context["vars"].get(key)
                if existing is None:
                    existing = str(uuid.uuid4()).upper()
                    self.context["vars"][key] = existing
                return existing
            if "$var" in value:
                key = value["$var"]
                if key not in self.context["vars"]:
                    raise HarnessError(f"Unknown variable reference: {key}")
                return self.context["vars"][key]
            return {key: self._resolve_value(inner) for key, inner in value.items()}
        if isinstance(value, list):
            return [self._resolve_value(item) for item in value]
        return value


def load_scenario_paths(path: Path) -> list[Path]:
    if path.is_dir():
        return sorted(path.glob("*.json"))
    return [path]


def print_summary(results: list[ScenarioResult]) -> None:
    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"{status} {result.name} -> {result.artifact_dir}")
        for step in result.step_results:
            step_status = "PASS" if step.passed else "FAIL"
            print(f"  {step_status} {step.label}")
            for detail in step.details:
                print(f"    - {detail}")


def build_eval_runner() -> tuple[EvaluationRunner, EvalStore]:
    config = load_config()
    config.ensure_directories()
    store = EvalStore(config.db_path)
    runner = EvaluationRunner(config, store)
    return runner, store


def sync_declared_workflows(runner: EvaluationRunner) -> list[str]:
    workflow_ids: list[str] = []
    for path in sorted(runner.config.workflow_root.glob("*.json")):
        workflow = runner.load_workflow(path.stem)
        runner.store.sync_declared_coverage(workflow)
        workflow_ids.append(workflow.id)
    return workflow_ids


def run_scenarios(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Run MCP-driven visual harness scenarios.")
    parser.add_argument("scenario_path", help="Scenario JSON file or directory of JSON files")
    parser.add_argument("--mcp-url", default=DEFAULT_MCP_URL, help="MCP server URL")
    parser.add_argument(
        "--baseline-dir",
        default=str(Path(__file__).resolve().parent / "baselines"),
        help="Directory containing approved baseline screenshots",
    )
    parser.add_argument(
        "--artifacts-dir",
        default=str(Path(__file__).resolve().parent / "artifacts"),
        help="Directory for reports, screenshots, and diffs",
    )
    parser.add_argument(
        "--accept-new",
        action="store_true",
        help="Accept missing baselines by copying the captured screenshot into the baseline directory",
    )
    args = parser.parse_args(argv)

    scenario_paths = load_scenario_paths(Path(args.scenario_path).resolve())
    if not scenario_paths:
        raise SystemExit("No scenario JSON files found")

    client = MCPClient(args.mcp_url)
    runner = ScenarioRunner(
        client=client,
        baseline_root=Path(args.baseline_dir).resolve(),
        artifact_root=Path(args.artifacts_dir).resolve(),
        accept_new=args.accept_new,
    )

    results = [runner.run_file(path) for path in scenario_paths]
    print_summary(results)
    return 0 if all(result.passed for result in results) else 1


def cmd_sync_corpus(args: argparse.Namespace) -> int:
    runner, _ = build_eval_runner()
    manifest, report = runner.sync_corpus(repair=args.repair)
    print(f"Manifest: {runner.corpus.manifest_path}")
    print(f"Items: {len(manifest.items)}")
    print(f"Status: {'OK' if report.ok else 'ERROR'}")
    if report.errors:
        print("Errors:")
        for error in report.errors:
            print(f"  - {error}")
    if report.warnings:
        print("Warnings:")
        for warning in report.warnings:
            print(f"  - {warning}")
    if report.orphans:
        print(f"Orphans: {len(report.orphans)}")
    return 0 if report.ok else 1


def cmd_inventory_tools(args: argparse.Namespace) -> int:
    runner, _ = build_eval_runner()
    tools = runner.sync_tool_inventory()
    if args.json:
        print(json.dumps([tool.__dict__ for tool in tools], indent=2))
    else:
        print(f"Discovered {len(tools)} MCP tools from {runner.config.mcp_url}")
        for tool in tools:
            print(f"- {tool.name} [{tool.family}]")
    return 0


def cmd_coverage_report(args: argparse.Namespace) -> int:
    runner, store = build_eval_runner()
    runner.sync_tool_inventory()
    sync_declared_workflows(runner)
    report = store.coverage_report(runner.config.stale_coverage_days)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        for entry in report:
            print(f"{entry['tool_name']} [{entry['family']}] -> {entry['status']}")
            for workflow in entry.get("workflows", []):
                print(f"  - {workflow['workflow_id']}: {workflow['status']}")
    return 0


def cmd_enqueue(args: argparse.Namespace) -> int:
    runner, _ = build_eval_runner()
    sync_declared_workflows(runner)
    run_ids = runner.enqueue(
        args.workflow_id,
        split=args.split,
        source_family=args.source_family,
        limit=args.limit,
    )
    print(json.dumps({"queued_run_ids": run_ids}, indent=2))
    return 0


def cmd_run_queued(args: argparse.Namespace) -> int:
    runner, _ = build_eval_runner()
    runner.sync_corpus(validate=False)
    runner.sync_tool_inventory()
    sync_declared_workflows(runner)
    completed = runner.run_queued(limit=args.limit)
    print(json.dumps({"completed_run_ids": completed}, indent=2))
    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    runner, store = build_eval_runner()
    manifest, report = runner.sync_corpus(repair=args.repair_corpus)
    runner.sync_tool_inventory()
    sync_declared_workflows(runner)
    print(f"Corpus items: {len(manifest.items)}")
    print(f"Corpus validation: {'OK' if report.ok else 'ERROR'}")
    print(f"Dashboard: http://{runner.config.dashboard_host}:{runner.config.dashboard_port}")
    server = EvalHTTPServer(runner.config, store, runner)
    server.start()
    return 0


def build_command_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="VideoEditor MCP scenario harness and automated eval runner.")
    subparsers = parser.add_subparsers(dest="command")

    p_scenario = subparsers.add_parser(SCENARIO_COMMAND, help="Run legacy screenshot/baseline scenarios")
    p_scenario.add_argument("scenario_path")
    p_scenario.add_argument("--mcp-url", default=DEFAULT_MCP_URL)
    p_scenario.add_argument("--baseline-dir", default=str(Path(__file__).resolve().parent / "baselines"))
    p_scenario.add_argument("--artifacts-dir", default=str(Path(__file__).resolve().parent / "artifacts"))
    p_scenario.add_argument("--accept-new", action="store_true")

    p_sync = subparsers.add_parser("sync-corpus", help="Validate and sync the eval corpus into the local metadata store")
    p_sync.add_argument("--repair", action="store_true", help="Rebuild manifest.json from disk before validating")
    p_sync.set_defaults(func=cmd_sync_corpus)

    p_inventory = subparsers.add_parser("inventory-tools", help="Discover MCP tools from the running app and sync inventory")
    p_inventory.add_argument("--json", action="store_true")
    p_inventory.set_defaults(func=cmd_inventory_tools)

    p_coverage = subparsers.add_parser("coverage-report", help="Show MCP tool coverage across workflows")
    p_coverage.add_argument("--json", action="store_true")
    p_coverage.set_defaults(func=cmd_coverage_report)

    p_enqueue = subparsers.add_parser("enqueue", help="Queue corpus items for a workflow")
    p_enqueue.add_argument("workflow_id")
    p_enqueue.add_argument("--split", choices=["development", "calibration", "holdout"])
    p_enqueue.add_argument("--source-family")
    p_enqueue.add_argument("--limit", type=int)
    p_enqueue.set_defaults(func=cmd_enqueue)

    p_run = subparsers.add_parser("run-queued", help="Run queued eval jobs")
    p_run.add_argument("--limit", type=int)
    p_run.set_defaults(func=cmd_run_queued)

    p_serve = subparsers.add_parser("serve", help="Start the local eval dashboard and worker")
    p_serve.add_argument("--repair-corpus", action="store_true")
    p_serve.set_defaults(func=cmd_serve)

    return parser


def main(argv: list[str]) -> int:
    known_commands = {
        SCENARIO_COMMAND,
        "sync-corpus",
        "inventory-tools",
        "coverage-report",
        "enqueue",
        "run-queued",
        "serve",
    }
    if argv and not argv[0].startswith("-") and argv[0] not in known_commands:
        return run_scenarios(argv)

    parser = build_command_parser()
    args = parser.parse_args(argv)
    if args.command is None:
        parser.print_help()
        return 1
    if args.command == SCENARIO_COMMAND:
        return run_scenarios(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
