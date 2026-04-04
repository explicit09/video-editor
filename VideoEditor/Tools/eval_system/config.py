from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


DEFAULT_CORPUS_ROOT = Path("/Volumes/Explicit's Hard Drive/eval_corpus")
DEFAULT_EVAL_ROOT = Path("/Volumes/Explicit's Hard Drive/videoeditor_eval_system")
DEFAULT_MCP_URL = "http://127.0.0.1:8420"
DEFAULT_SANDBOX_ROOT = Path("/Users/explicit/Library/Containers/com.videoeditor.app/Data/Documents")
DEFAULT_LEARNX_ROOT = Path("/Users/explicit/Projects/LEARN-X")


@dataclass(frozen=True)
class EvalConfig:
    repo_root: Path
    tools_root: Path
    corpus_root: Path
    eval_root: Path
    runs_root: Path
    baseline_root: Path
    artifact_root: Path
    db_path: Path
    workflow_root: Path
    sandbox_root: Path
    staging_root: Path
    mcp_url: str
    stale_coverage_days: int
    gemini_api_key: str | None
    gemini_model: str
    twelvelabs_api_key: str | None
    twelvelabs_index_id: str | None
    judge_required_splits: tuple[str, ...]
    judge_optional_splits: tuple[str, ...]
    primary_judge_providers: tuple[str, ...]
    optional_judge_providers: tuple[str, ...]
    dashboard_host: str
    dashboard_port: int

    def ensure_directories(self) -> None:
        for path in [
            self.eval_root,
            self.runs_root,
            self.artifact_root,
            self.staging_root,
        ]:
            path.mkdir(parents=True, exist_ok=True)


def _parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'").strip('"')
        values[key] = value
    return values


def _load_learnx_env() -> dict[str, str]:
    learnx_root = Path(os.getenv("VIDEOEDITOR_EVAL_LEARNX_ROOT", DEFAULT_LEARNX_ROOT)).expanduser()
    candidates = [
        learnx_root / "apps/backend/backend/.env",
        learnx_root / ".env",
        learnx_root / "apps/web/.env.local",
    ]
    merged: dict[str, str] = {}
    for candidate in candidates:
        merged.update(_parse_env_file(candidate))
    return merged


def _load_local_env(repo_root: Path) -> dict[str, str]:
    candidates = [
        repo_root / "VideoEditor/.env",
        repo_root / ".env",
    ]
    merged: dict[str, str] = {}
    for candidate in candidates:
        merged.update(_parse_env_file(candidate))
    return merged


def _parse_csv_setting(value: str | None, default: tuple[str, ...]) -> tuple[str, ...]:
    if value is None:
        return default
    parts = tuple(item.strip() for item in value.split(",") if item.strip())
    return parts or default


def load_config() -> EvalConfig:
    tools_root = Path(__file__).resolve().parents[1]
    repo_root = tools_root.parents[1]
    corpus_root = Path(os.getenv("VIDEOEDITOR_EVAL_CORPUS_ROOT", DEFAULT_CORPUS_ROOT)).expanduser()
    eval_root = Path(os.getenv("VIDEOEDITOR_EVAL_ROOT", DEFAULT_EVAL_ROOT)).expanduser()
    sandbox_root = Path(os.getenv("VIDEOEDITOR_EVAL_SANDBOX_ROOT", DEFAULT_SANDBOX_ROOT)).expanduser()
    local_env = _load_local_env(repo_root)
    learnx_env = _load_learnx_env()
    gemini_api_key = (
        os.getenv("GEMINI_API_KEY")
        or os.getenv("GOOGLE_AI_API_KEY")
        or local_env.get("GEMINI_API_KEY")
        or local_env.get("GOOGLE_AI_API_KEY")
        or local_env.get("GOOGLE_API_KEY")
        or learnx_env.get("GEMINI_API_KEY")
        or learnx_env.get("GOOGLE_AI_API_KEY")
        or learnx_env.get("GOOGLE_API_KEY")
    )
    gemini_model = (
        os.getenv("GEMINI_MODEL")
        or local_env.get("GEMINI_MODEL")
        or local_env.get("GOOGLE_AI_MODEL")
        or learnx_env.get("GEMINI_MODEL")
        or learnx_env.get("GOOGLE_AI_MODEL")
        or "gemini-3-pro-preview"
    )
    twelvelabs_api_key = (
        os.getenv("TWELVELABS_API_KEY")
        or local_env.get("TWELVELABS_API_KEY")
    )
    twelvelabs_index_id = (
        os.getenv("TWELVELABS_INDEX_ID")
        or local_env.get("TWELVELABS_INDEX_ID")
    )
    return EvalConfig(
        repo_root=repo_root,
        tools_root=tools_root,
        corpus_root=corpus_root,
        eval_root=eval_root,
        runs_root=eval_root / "runs",
        baseline_root=tools_root / "baselines",
        artifact_root=eval_root / "artifacts",
        db_path=Path(os.getenv("VIDEOEDITOR_EVAL_DB", eval_root / "index.sqlite")).expanduser(),
        workflow_root=tools_root / "eval_system" / "workflows",
        sandbox_root=sandbox_root,
        staging_root=sandbox_root / "eval_staging",
        mcp_url=os.getenv("VIDEOEDITOR_EVAL_MCP_URL", DEFAULT_MCP_URL),
        stale_coverage_days=int(os.getenv("VIDEOEDITOR_EVAL_STALE_DAYS", "30")),
        gemini_api_key=gemini_api_key,
        gemini_model=gemini_model,
        twelvelabs_api_key=twelvelabs_api_key,
        twelvelabs_index_id=twelvelabs_index_id,
        judge_required_splits=_parse_csv_setting(
            os.getenv("VIDEOEDITOR_EVAL_JUDGE_REQUIRED_SPLITS")
            or local_env.get("VIDEOEDITOR_EVAL_JUDGE_REQUIRED_SPLITS"),
            ("calibration", "holdout"),
        ),
        judge_optional_splits=_parse_csv_setting(
            os.getenv("VIDEOEDITOR_EVAL_JUDGE_OPTIONAL_SPLITS")
            or local_env.get("VIDEOEDITOR_EVAL_JUDGE_OPTIONAL_SPLITS"),
            ("holdout",),
        ),
        primary_judge_providers=_parse_csv_setting(
            os.getenv("VIDEOEDITOR_EVAL_PRIMARY_JUDGES")
            or local_env.get("VIDEOEDITOR_EVAL_PRIMARY_JUDGES"),
            ("gemini",),
        ),
        optional_judge_providers=_parse_csv_setting(
            os.getenv("VIDEOEDITOR_EVAL_OPTIONAL_JUDGES")
            or local_env.get("VIDEOEDITOR_EVAL_OPTIONAL_JUDGES"),
            ("twelvelabs",),
        ),
        dashboard_host=os.getenv("VIDEOEDITOR_EVAL_HOST", "127.0.0.1"),
        dashboard_port=int(os.getenv("VIDEOEDITOR_EVAL_PORT", "8765")),
    )
