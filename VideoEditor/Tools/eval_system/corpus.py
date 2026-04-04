from __future__ import annotations

import json
import shutil
import subprocess
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

from .models import CorpusItem, CorpusManifest
from .utils import guess_mime_type, iso_now, slugify, stable_split


VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}
MEDIA_EXTENSIONS = VIDEO_EXTENSIONS | {".png", ".jpg", ".jpeg", ".heic", ".wav", ".aiff", ".mp3", ".m4a"}


def probe_media(path: Path) -> dict[str, object]:
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration,size:stream=codec_type,width,height,r_frame_rate",
                "-of",
                "json",
                str(path),
            ],
            capture_output=True,
            text=True,
            timeout=30,
            check=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return {
            "duration_seconds": None,
            "resolution": None,
            "fps": None,
            "has_audio": None,
            "mime_type": guess_mime_type(path),
            "size_bytes": path.stat().st_size,
        }
    data = json.loads(result.stdout)
    streams = data.get("streams", [])
    video_stream = next((stream for stream in streams if stream.get("codec_type") == "video"), {})
    audio_stream = next((stream for stream in streams if stream.get("codec_type") == "audio"), {})
    fps = None
    fps_raw = video_stream.get("r_frame_rate")
    if fps_raw:
        if "/" in fps_raw:
            numerator, denominator = fps_raw.split("/")
            if int(denominator) != 0:
                fps = round(int(numerator) / int(denominator), 3)
        else:
            fps = float(fps_raw)
    width = video_stream.get("width")
    height = video_stream.get("height")
    resolution = f"{width}x{height}" if width and height else None
    return {
        "duration_seconds": round(float(data.get("format", {}).get("duration", 0) or 0), 3),
        "resolution": resolution,
        "fps": fps,
        "has_audio": bool(audio_stream),
        "mime_type": guess_mime_type(path),
        "size_bytes": path.stat().st_size,
    }


def infer_source_family(relative_path: str) -> str:
    if relative_path.startswith("ava_videos/"):
        return "ava"
    if relative_path.startswith("tvsum/video/"):
        return "tvsum"
    if relative_path.startswith("pexels/"):
        return "pexels"
    if relative_path.startswith("synthetic/"):
        return "synthetic"
    if relative_path.startswith("failure_pack/"):
        return "failure"
    return "local"


def infer_content_tags(relative_path: str) -> list[str]:
    tags: set[str] = set()
    source_family = infer_source_family(relative_path)
    if source_family == "ava":
        tags.update({"speaker-alignment", "long-form", "multimodal"})
    elif source_family == "tvsum":
        tags.update({"summarization", "highlight", "long-form"})
    elif source_family == "pexels":
        tags.update({"visual-footage", "short-form"})
    elif source_family == "synthetic":
        tags.update({"synthetic"})
    elif source_family == "failure":
        tags.update({"synthetic", "failure-case"})
    stem = Path(relative_path).stem
    for marker in ["podcast", "speaker", "silence", "crop", "subtitle", "black", "debate", "panel", "vertical"]:
        if marker in stem:
            tags.add(marker)
    return sorted(tags)


def infer_tasks(source_family: str, media_type: str, tags: list[str]) -> list[str]:
    if media_type != "video":
        return ["import_and_verify", "export_verify"]
    tasks = {"import_and_verify", "export_verify"}
    tasks.update({"clip_styling_suite", "caption_overlay_suite"})
    if source_family in {"ava", "tvsum", "synthetic"}:
        tasks.add("transcribe")
        tasks.add("audio_cleanup_suite")
    if source_family in {"tvsum", "synthetic"}:
        tasks.update({"episode_cut", "short_extract"})
    if source_family == "ava":
        tasks.add("speaker_alignment_eval")
        tasks.add("shorts_deep_suite")
    if source_family in {"synthetic", "failure"}:
        tasks.update({"clip_editing_suite", "track_management_suite", "snapshot_platform_export_suite", "asset_management_suite"})
    if source_family in {"ava", "synthetic"}:
        tasks.add("content_analysis_suite")
    if source_family in {"ava", "tvsum"}:
        tasks.add("broll_hook_suite")
    if source_family == "ava":
        tasks.add("shorts_deep_suite")
    if source_family in {"ava", "synthetic"}:
        tasks.add("video_processing_suite")
    if source_family in {"ava", "tvsum", "synthetic"}:
        tasks.add("transcript_editing_suite")
    if "failure-case" in tags:
        tasks.add("export_verify")
    return sorted(tasks)


def media_type_for_path(path: Path) -> str | None:
    suffix = path.suffix.lower()
    if suffix in VIDEO_EXTENSIONS:
        return "video"
    if suffix in {".wav", ".aiff", ".mp3", ".m4a"}:
        return "audio"
    if suffix in {".png", ".jpg", ".jpeg", ".heic"}:
        return "image"
    return None


@dataclass
class ValidationReport:
    ok: bool
    errors: list[str]
    warnings: list[str]
    orphans: list[str]


class CorpusManager:
    def __init__(self, corpus_root: Path) -> None:
        self.corpus_root = corpus_root
        self.manifest_path = corpus_root / "manifest.json"

    def load_manifest(self) -> CorpusManifest:
        if not self.manifest_path.exists():
            raise FileNotFoundError(self.manifest_path)
        return CorpusManifest.from_dict(json.loads(self.manifest_path.read_text()))

    def rescan_manifest(self, existing: CorpusManifest | None = None) -> CorpusManifest:
        existing_by_rel = {}
        if existing is not None:
            existing_by_rel = {item.relative_path: item for item in existing.items}
        items: list[CorpusItem] = []
        for path in sorted(self.corpus_root.rglob("*")):
            if not path.is_file():
                continue
            if path.name.startswith(".") or path.suffix.lower() == ".part":
                continue
            media_type = media_type_for_path(path)
            if media_type is None:
                continue
            relative_path = str(path.relative_to(self.corpus_root))
            source_family = infer_source_family(relative_path)
            inherited = existing_by_rel.get(relative_path)
            tags = inherited.content_tags if inherited else infer_content_tags(relative_path)
            split = inherited.split if inherited else stable_split(relative_path)
            expected = inherited.expected if inherited else {}
            annotations = dict(inherited.annotations) if inherited else {}
            annotations["holdout"] = split == "holdout"
            probe = probe_media(path)
            computed_tags = set(tags)
            has_audio = probe.get("has_audio")
            if has_audio is True:
                computed_tags.add("has-audio")
            elif has_audio is False:
                computed_tags.update({"no-audio", "visual-only"})
            items.append(
                CorpusItem(
                    id=inherited.id if inherited else slugify(f"{source_family}-{path.stem}"),
                    source_family=source_family,
                    relative_path=relative_path,
                    media_type=media_type,
                    split=split,
                    content_tags=sorted(computed_tags),
                    tasks=sorted(set(inherited.tasks).union(infer_tasks(source_family, media_type, tags))) if inherited else infer_tasks(source_family, media_type, tags),
                    annotations=annotations,
                    expected=expected,
                    probe=probe,
                    filename=path.name,
                )
            )
        splits = Counter(item.split for item in items)
        return CorpusManifest(
            name="videoeditor-eval-corpus",
            version="2.0",
            created=iso_now(),
            description="Canonical automated evaluation corpus for VideoEditor.",
            splits=dict(splits),
            items=items,
        )

    def write_manifest(self, manifest: CorpusManifest) -> None:
        self.manifest_path.parent.mkdir(parents=True, exist_ok=True)
        self.manifest_path.write_text(json.dumps(manifest.to_dict(), indent=2))

    def repair_manifest(self) -> CorpusManifest:
        existing = self.load_manifest() if self.manifest_path.exists() else None
        if existing is not None and existing.version != "2.0":
            existing = None
        repaired = self.rescan_manifest(existing)
        self.write_manifest(repaired)
        return repaired

    def validate_manifest(self, manifest: CorpusManifest | None = None) -> ValidationReport:
        manifest = manifest or self.load_manifest()
        errors: list[str] = []
        warnings: list[str] = []
        manifest_paths: set[str] = set()
        item_ids: set[str] = set()
        for item in manifest.items:
            if item.id in item_ids:
                errors.append(f"duplicate item id: {item.id}")
            item_ids.add(item.id)
            manifest_paths.add(item.relative_path)
            full_path = self.corpus_root / item.relative_path
            if not full_path.exists():
                errors.append(f"missing path: {item.relative_path}")
                continue
            if media_type_for_path(full_path) is None:
                errors.append(f"non-media path in manifest: {item.relative_path}")
            probe = probe_media(full_path)
            if probe["duration_seconds"] is None and item.media_type == "video":
                errors.append(f"broken media: {item.relative_path}")
            if item.split not in {"development", "calibration", "holdout"}:
                errors.append(f"invalid split for {item.id}: {item.split}")
        orphans: list[str] = []
        for path in sorted(self.corpus_root.rglob("*")):
            if not path.is_file():
                continue
            if path.name.startswith(".") or path.suffix.lower() == ".part":
                continue
            if media_type_for_path(path) is None:
                continue
            relative_path = str(path.relative_to(self.corpus_root))
            if relative_path not in manifest_paths:
                orphans.append(relative_path)
        if orphans:
            warnings.append(f"orphan media count: {len(orphans)}")
        return ValidationReport(ok=not errors, errors=errors, warnings=warnings, orphans=orphans)

    def select_items(
        self,
        split: str | None = None,
        workflow_id: str | None = None,
        workflow=None,
        source_family: str | None = None,
        limit: int | None = None,
    ) -> list[CorpusItem]:
        manifest = self.load_manifest()
        items = manifest.items
        if split:
            items = [item for item in items if item.split == split]
        if workflow_id:
            items = [item for item in items if workflow_id in item.tasks]
        if workflow and workflow.eligibility_tags:
            required = set(workflow.eligibility_tags)
            items = [item for item in items if required.issubset(set(item.content_tags))]
        if workflow and workflow.allowed_source_families:
            allowed = set(workflow.allowed_source_families)
            items = [item for item in items if item.source_family in allowed]
        if workflow and workflow.max_duration_seconds is not None:
            items = [
                item
                for item in items
                if (item.probe.get("duration_seconds") or 0) <= workflow.max_duration_seconds
            ]
        if workflow and workflow.max_duration_by_source_family:
            filtered: list[CorpusItem] = []
            for item in items:
                limit_seconds = workflow.max_duration_by_source_family.get(item.source_family)
                duration_seconds = item.probe.get("duration_seconds") or 0
                if limit_seconds is not None and duration_seconds > limit_seconds:
                    continue
                filtered.append(item)
            items = filtered
        if source_family:
            items = [item for item in items if item.source_family == source_family]
        return items[:limit] if limit is not None else items


class SandboxStager:
    def __init__(self, staging_root: Path) -> None:
        self.staging_root = staging_root
        self.staging_root.mkdir(parents=True, exist_ok=True)

    def _stage_source(self, item_id: str, source: Path, filename: str | None = None) -> Path:
        target_dir = self.staging_root / item_id
        target_dir.mkdir(parents=True, exist_ok=True)
        if source.suffix.lower() == ".mkv":
            return self._normalize_for_import(source, target_dir)
        target = target_dir / (filename or source.name)
        shutil.copy2(source, target)
        return target

    def _normalize_for_import(self, source: Path, target_dir: Path) -> Path:
        normalized = target_dir / f"{source.stem}.mp4"
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-i",
                str(source),
                "-map",
                "0:v:0",
                "-map",
                "0:a?",
                "-c:v",
                "copy",
                "-c:a",
                "aac",
                "-b:a",
                "192k",
                "-movflags",
                "+faststart",
                str(normalized),
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=3600,
        )
        return normalized

    def stage(self, item: CorpusItem, corpus_root: Path) -> Path:
        source = corpus_root / item.relative_path
        return self._stage_source(item.id, source, item.filename or Path(item.relative_path).name)

    def stage_path(self, item_id: str, source: Path, filename: str | None = None) -> Path:
        return self._stage_source(item_id, source, filename)

    def cleanup(self, item_id: str) -> None:
        staged_dir = self.staging_root / item_id
        if staged_dir.exists():
            shutil.rmtree(staged_dir)
