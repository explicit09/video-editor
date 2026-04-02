from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Any

from .models import ArtifactRecord, ValidatorResult
from .utils import parse_editor_state


def _result(validator_id: str, status: str, details: str, score: float | None = None, evidence: list[str] | None = None, metadata: dict[str, Any] | None = None) -> ValidatorResult:
    return ValidatorResult(
        validator_id=validator_id,
        status=status,
        score=score,
        details=details,
        evidence_paths=evidence or [],
        metadata=metadata or {},
    )


def _metadata_with_policy(
    policy: str,
    *,
    failure_class: str | None = None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {"validator_policy": policy}
    if failure_class is not None:
        payload["failure_class"] = failure_class
    if extra:
        payload.update(extra)
    return payload


def verify_playback_clean(output: str) -> ValidatorResult:
    if "[FAIL]" in output:
        return _result(
            "verify_playback_clean",
            "fail",
            "verify_playback reported failures",
            score=0.0,
            metadata=_metadata_with_policy("source_content_match"),
        )
    if "Result:" not in output:
        return _result(
            "verify_playback_clean",
            "quarantine",
            "verify_playback output was missing a result line",
            metadata=_metadata_with_policy("source_content_match", failure_class="infrastructure"),
        )
    return _result(
        "verify_playback_clean",
        "pass",
        "verify_playback completed without failures",
        score=1.0,
        metadata=_metadata_with_policy("source_content_match"),
    )


_VERIFY_LINE_PATTERN = re.compile(
    r"^\[(?P<status>PASS|FAIL)\]\s+(?P<label>.+?)\s+@\s+(?P<time>[0-9.]+)s:(?P<body>.*)$",
    flags=re.MULTILINE,
)


def _parse_verify_playback(output: str) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for match in _VERIFY_LINE_PATTERN.finditer(output):
        body = match.group("body").strip()
        detail = body
        if "—" in body:
            detail = body.split("—", 1)[1].strip()
        entries.append(
            {
                "status": match.group("status").lower(),
                "label": match.group("label").strip(),
                "time": float(match.group("time")),
                "body": body,
                "detail": detail,
            }
        )
    return entries


def verify_playback_post_edit_integrity(output: str) -> ValidatorResult:
    if "Result:" not in output:
        return _result(
            "verify_playback_post_edit_integrity",
            "quarantine",
            "verify_playback output was missing a result line",
            metadata=_metadata_with_policy("post_edit_integrity", failure_class="infrastructure"),
        )

    entries = _parse_verify_playback(output)
    if not entries:
        return _result(
            "verify_playback_post_edit_integrity",
            "quarantine",
            "verify_playback produced no checkpoint lines",
            metadata=_metadata_with_policy("post_edit_integrity", failure_class="infrastructure"),
        )

    failures = [entry for entry in entries if entry["status"] == "fail"]
    if not failures:
        return _result(
            "verify_playback_post_edit_integrity",
            "pass",
            "verify_playback completed without structural failures",
            score=1.0,
            metadata=_metadata_with_policy("post_edit_integrity"),
        )

    tolerated_failures: list[dict[str, Any]] = []
    blocking_failures: list[dict[str, Any]] = []
    for entry in failures:
        detail = entry["detail"]
        if "audio content mismatch" in detail or "video content mismatch" in detail:
            tolerated_failures.append(entry)
            continue
        blocking_failures.append(entry)

    if blocking_failures:
        detail = "; ".join(failure["detail"] for failure in blocking_failures[:3])
        return _result(
            "verify_playback_post_edit_integrity",
            "fail",
            f"verify_playback found structural failures: {detail}",
            score=0.0,
            metadata=_metadata_with_policy(
                "post_edit_integrity",
                failure_class="product",
                extra={
                    "blocking_failure_count": len(blocking_failures),
                    "tolerated_failure_count": len(tolerated_failures),
                },
            ),
        )

    return _result(
        "verify_playback_post_edit_integrity",
        "pass",
        f"Tolerated {len(tolerated_failures)} expected post-edit content mismatches; no structural failures detected",
        score=1.0,
        metadata=_metadata_with_policy(
            "post_edit_integrity",
            extra={
                "blocking_failure_count": 0,
                "tolerated_failure_count": len(tolerated_failures),
            },
        ),
    )


def transcript_present(output: str) -> ValidatorResult:
    normalized = output.strip().lower()
    if not normalized or "no transcript" in normalized:
        return _result(
            "transcript_present",
            "fail",
            "Transcript was empty or missing",
            score=0.0,
            metadata=_metadata_with_policy("transcript_presence", failure_class="product"),
        )
    return _result(
        "transcript_present",
        "pass",
        "Transcript text was returned",
        score=1.0,
        metadata=_metadata_with_policy("transcript_presence"),
    )


def export_exists(path: Path | None) -> ValidatorResult:
    if path is None:
        return _result(
            "export_exists",
            "fail",
            "Export path was not detected",
            score=0.0,
            metadata=_metadata_with_policy("artifact_presence", failure_class="infrastructure"),
        )
    if not path.exists():
        return _result(
            "export_exists",
            "fail",
            f"Export file does not exist: {path}",
            score=0.0,
            metadata=_metadata_with_policy("artifact_presence", failure_class="infrastructure"),
        )
    return _result(
        "export_exists",
        "pass",
        f"Export exists: {path}",
        score=1.0,
        evidence=[str(path)],
        metadata=_metadata_with_policy("artifact_presence"),
    )


def duration_sanity(path: Path | None, minimum_seconds: float = 1.0) -> ValidatorResult:
    if path is None or not path.exists():
        return _result(
            "duration_sanity",
            "quarantine",
            "Duration sanity skipped because file is missing",
            metadata=_metadata_with_policy("media_probe", failure_class="infrastructure"),
        )
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
            capture_output=True,
            text=True,
            timeout=20,
            check=True,
        )
        duration = float(result.stdout.strip())
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError):
        return _result(
            "duration_sanity",
            "fail",
            f"Unable to probe duration for {path}",
            score=0.0,
            metadata=_metadata_with_policy("media_probe", failure_class="infrastructure"),
        )
    if duration < minimum_seconds:
        return _result(
            "duration_sanity",
            "fail",
            f"Duration {duration:.2f}s < {minimum_seconds:.2f}s",
            score=0.0,
            evidence=[str(path)],
            metadata=_metadata_with_policy("media_probe", failure_class="product"),
        )
    return _result(
        "duration_sanity",
        "pass",
        f"Duration {duration:.2f}s is sane",
        score=1.0,
        evidence=[str(path)],
        metadata=_metadata_with_policy("media_probe", extra={"duration_seconds": duration}),
    )


def audio_present(path: Path | None, required: bool = True, expected_has_audio: bool | None = None) -> ValidatorResult:
    if path is None or not path.exists():
        return _result(
            "audio_present",
            "quarantine",
            "Audio validation skipped because file is missing",
            metadata=_metadata_with_policy("audio_stream_presence", failure_class="infrastructure"),
        )
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(path)],
            capture_output=True,
            text=True,
            timeout=20,
            check=True,
        )
        streams = json.loads(result.stdout).get("streams", [])
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return _result(
            "audio_present",
            "fail",
            f"Unable to inspect streams for {path}",
            score=0.0,
            metadata=_metadata_with_policy("audio_stream_presence", failure_class="infrastructure"),
        )
    has_audio = any(stream.get("codec_type") == "audio" for stream in streams)
    if expected_has_audio is not None:
        required = expected_has_audio
    if required and not has_audio:
        return _result(
            "audio_present",
            "fail",
            "Audio stream was expected but missing",
            score=0.0,
            evidence=[str(path)],
            metadata=_metadata_with_policy(
                "audio_stream_presence",
                failure_class="product",
                extra={"has_audio": has_audio, "expected_has_audio": required},
            ),
        )
    if not required and has_audio:
        return _result(
            "audio_present",
            "fail",
            "Audio stream was not expected but exists",
            score=0.0,
            evidence=[str(path)],
            metadata=_metadata_with_policy(
                "audio_stream_presence",
                failure_class="product",
                extra={"has_audio": has_audio, "expected_has_audio": required},
            ),
        )
    return _result(
        "audio_present",
        "pass",
        "Audio expectation matched",
        score=1.0,
        evidence=[str(path)],
        metadata=_metadata_with_policy(
            "audio_stream_presence",
            extra={"has_audio": has_audio, "expected_has_audio": required},
        ),
    )


def no_black_frames(path: Path | None) -> ValidatorResult:
    if path is None or not path.exists():
        return _result(
            "no_black_frames",
            "quarantine",
            "Black frame check skipped because file is missing",
            metadata=_metadata_with_policy("render_quality", failure_class="infrastructure"),
        )
    try:
        result = subprocess.run(
            [
                "ffmpeg",
                "-hide_banner",
                "-nostats",
                "-i",
                str(path),
                "-vf",
                "blackdetect=d=0.25:pic_th=0.98",
                "-an",
                "-f",
                "null",
                "-",
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return _result(
            "no_black_frames",
            "quarantine",
            "ffmpeg not available for black frame check",
            metadata=_metadata_with_policy("render_quality", failure_class="infrastructure"),
        )
    stderr = result.stderr.lower()
    if "black_start" in stderr:
        return _result(
            "no_black_frames",
            "fail",
            "Black frames detected in export",
            score=0.0,
            evidence=[str(path)],
            metadata=_metadata_with_policy("render_quality", failure_class="product"),
        )
    return _result(
        "no_black_frames",
        "pass",
        "No black frames detected",
        score=1.0,
        evidence=[str(path)],
        metadata=_metadata_with_policy("render_quality"),
    )


def screenshot_baseline(
    artifact: ArtifactRecord | None,
    baseline_path: Path,
    comparator,
    accept_new: bool = False,
    phash_max_distance: int = 8,
    mean_abs_diff_max: float = 8.0,
) -> ValidatorResult:
    if artifact is None:
        return _result(
            "screenshot_baseline",
            "quarantine",
            "No screenshot artifact available for baseline comparison",
            metadata=_metadata_with_policy("visual_baseline", failure_class="infrastructure"),
        )
    baseline_path.parent.mkdir(parents=True, exist_ok=True)
    capture_path = Path(artifact.path)
    if not baseline_path.exists():
        if accept_new:
            baseline_path.write_bytes(capture_path.read_bytes())
            return _result(
                "screenshot_baseline",
                "pass",
                f"Accepted new baseline at {baseline_path}",
                score=1.0,
                metadata=_metadata_with_policy("visual_baseline"),
            )
        return _result(
            "screenshot_baseline",
            "quarantine",
            f"Missing baseline: {baseline_path}",
            metadata=_metadata_with_policy("visual_baseline", failure_class="infrastructure"),
        )
    phash_distance, mad, diff_path = comparator(capture_path, baseline_path)
    if phash_distance > phash_max_distance or mad > mean_abs_diff_max:
        return _result(
            "screenshot_baseline",
            "fail",
            f"Screenshot drifted (pHash={phash_distance}, mad={mad:.2f})",
            score=0.0,
            evidence=[str(capture_path), str(baseline_path), str(diff_path)],
            metadata=_metadata_with_policy(
                "visual_baseline",
                failure_class="product",
                extra={"phash_distance": phash_distance, "mean_absolute_difference": mad},
            ),
        )
    return _result(
        "screenshot_baseline",
        "pass",
        f"Screenshot matched baseline (pHash={phash_distance}, mad={mad:.2f})",
        score=1.0,
        evidence=[str(capture_path), str(baseline_path)],
        metadata=_metadata_with_policy(
            "visual_baseline",
            extra={"phash_distance": phash_distance, "mean_absolute_difference": mad},
        ),
    )


def timeline_changed(before_state: str, after_state: str) -> ValidatorResult:
    """Check that the timeline actually changed between two get_state snapshots.
    Compares track count and clip count to detect no-op workflows."""
    def _parse_counts(state: str) -> tuple[int, int]:
        tracks = 0
        clips = 0
        for line in state.split("\n"):
            line = line.strip()
            if line.startswith("Tracks ("):
                try:
                    tracks = int(line.split("(")[1].split(")")[0])
                except (IndexError, ValueError):
                    pass
            if "[id=" in line:
                clips += 1
        return tracks, clips

    before_tracks, before_clips = _parse_counts(before_state)
    after_tracks, after_clips = _parse_counts(after_state)

    if after_tracks > before_tracks or after_clips > before_clips:
        return _result(
            "timeline_changed",
            "pass",
            f"Timeline changed: tracks {before_tracks}->{after_tracks}, clips {before_clips}->{after_clips}",
            score=1.0,
            metadata=_metadata_with_policy("timeline_mutation"),
        )
    if after_tracks == before_tracks and after_clips == before_clips:
        return _result(
            "timeline_changed",
            "fail",
            f"Timeline unchanged: tracks={after_tracks}, clips={after_clips}. Expected visible change from workflow.",
            score=0.0,
            metadata=_metadata_with_policy("timeline_mutation", failure_class="product"),
        )
    return _result(
        "timeline_changed",
        "quarantine",
        f"Timeline tracks/clips decreased: tracks {before_tracks}->{after_tracks}, clips {before_clips}->{after_clips}",
        metadata=_metadata_with_policy("timeline_mutation", failure_class="investigate"),
    )


def _timeline_counts(state_text: str) -> dict[str, Any]:
    parsed = parse_editor_state(state_text)
    video_tracks = [track for track in parsed["tracks"] if track["type"] == "video"]
    audio_tracks = [track for track in parsed["tracks"] if track["type"] == "audio"]
    video_clips = [clip for track in video_tracks for clip in track["clips"]]
    audio_clips = [clip for track in audio_tracks for clip in track["clips"]]
    return {
        "parsed": parsed,
        "track_count": len(parsed["tracks"]),
        "clip_count": len(video_clips) + len(audio_clips),
        "video_track_count": len(video_tracks),
        "audio_track_count": len(audio_tracks),
        "video_clip_count": len(video_clips),
        "audio_clip_count": len(audio_clips),
        "video_labels": [clip["label"] for clip in video_clips],
        "signature": [
            (track["type"], clip["label"], clip["start"], clip["end"])
            for track in parsed["tracks"]
            for clip in track["clips"]
        ],
    }


def broll_inserted(before_state: str, after_state: str, expected_clip_label: str | None = None) -> ValidatorResult:
    if not before_state.strip() or not after_state.strip():
        return _result(
            "broll_inserted",
            "quarantine",
            "Timeline state snapshots were unavailable for B-roll validation",
            metadata=_metadata_with_policy("broll_enrichment", failure_class="infrastructure"),
        )

    before = _timeline_counts(before_state)
    after = _timeline_counts(after_state)
    expected_present = False
    if expected_clip_label:
        needle = expected_clip_label.lower()
        expected_present = any(needle in label.lower() for label in after["video_labels"])

    video_delta = after["video_clip_count"] - before["video_clip_count"]
    track_delta = after["video_track_count"] - before["video_track_count"]
    if expected_present or video_delta > 0 or track_delta > 0:
        detail_bits = [
            f"video clips {before['video_clip_count']}->{after['video_clip_count']}",
            f"video tracks {before['video_track_count']}->{after['video_track_count']}",
        ]
        if expected_clip_label:
            detail_bits.append(f"expected clip present={expected_present}")
        return _result(
            "broll_inserted",
            "pass",
            "B-roll insertion changed the timeline: " + ", ".join(detail_bits),
            score=1.0,
            metadata=_metadata_with_policy(
                "broll_enrichment",
                extra={
                    "before_video_clip_count": before["video_clip_count"],
                    "after_video_clip_count": after["video_clip_count"],
                    "before_video_track_count": before["video_track_count"],
                    "after_video_track_count": after["video_track_count"],
                    "expected_clip_label": expected_clip_label,
                    "expected_clip_present": expected_present,
                },
            ),
        )

    return _result(
        "broll_inserted",
        "fail",
        "No B-roll insertion was visible in timeline state",
        score=0.0,
        metadata=_metadata_with_policy(
            "broll_enrichment",
            failure_class="product",
            extra={
                "before_video_clip_count": before["video_clip_count"],
                "after_video_clip_count": after["video_clip_count"],
                "before_video_track_count": before["video_track_count"],
                "after_video_track_count": after["video_track_count"],
                "expected_clip_label": expected_clip_label,
                "expected_clip_present": expected_present,
            },
        ),
    )


def hook_applied(hook_output: str) -> ValidatorResult:
    """Check that hook_optimize actually rearranged content, or gracefully skipped."""
    if "Hook optimized:" in hook_output:
        return _result(
            "hook_applied",
            "pass",
            "Hook rearrangement applied",
            score=1.0,
            metadata=_metadata_with_policy("hook_optimization"),
        )
    if "Hook is already at the start" in hook_output:
        # Acceptable — the best hook was already first
        return _result(
            "hook_applied",
            "pass",
            "Hook already at start (no rearrangement needed)",
            score=0.8,
            metadata=_metadata_with_policy("hook_optimization"),
        )
    if "Hook skipped:" in hook_output:
        return _result(
            "hook_applied",
            "quarantine",
            f"Hook skipped: {hook_output[:200]}",
            metadata=_metadata_with_policy("hook_optimization", failure_class="content_quality"),
        )
    if "Error:" in hook_output:
        return _result(
            "hook_applied",
            "fail",
            f"Hook optimize failed: {hook_output[:200]}",
            score=0.0,
            metadata=_metadata_with_policy("hook_optimization", failure_class="product"),
        )
    return _result(
        "hook_applied",
        "quarantine",
        f"Unexpected hook_optimize output: {hook_output[:200]}",
        metadata=_metadata_with_policy("hook_optimization", failure_class="investigate"),
    )


def hook_structure_changed(before_state: str, after_state: str, hook_output: str) -> ValidatorResult:
    if "Hook is already at the start" in hook_output:
        return _result(
            "hook_structure_changed",
            "pass",
            "Hook already at start; no structural change required",
            score=0.8,
            metadata=_metadata_with_policy("hook_optimization"),
        )
    if "Hook skipped:" in hook_output:
        return _result(
            "hook_structure_changed",
            "quarantine",
            hook_output[:200],
            metadata=_metadata_with_policy("hook_optimization", failure_class="content_quality"),
        )
    if "Hook optimized:" not in hook_output:
        return _result(
            "hook_structure_changed",
            "quarantine",
            f"Unexpected hook output for structural validation: {hook_output[:200]}",
            metadata=_metadata_with_policy("hook_optimization", failure_class="infrastructure"),
        )
    if not before_state.strip() or not after_state.strip():
        return _result(
            "hook_structure_changed",
            "quarantine",
            "Timeline state snapshots were unavailable for hook validation",
            metadata=_metadata_with_policy("hook_optimization", failure_class="infrastructure"),
        )

    before = _timeline_counts(before_state)
    after = _timeline_counts(after_state)
    if before["signature"] != after["signature"]:
        return _result(
            "hook_structure_changed",
            "pass",
            f"Hook optimization changed timeline structure: clips {before['clip_count']}->{after['clip_count']}",
            score=1.0,
            metadata=_metadata_with_policy(
                "hook_optimization",
                extra={"before_clip_count": before["clip_count"], "after_clip_count": after["clip_count"]},
            ),
        )

    return _result(
        "hook_structure_changed",
        "fail",
        "Hook optimization claimed success but timeline structure was unchanged",
        score=0.0,
        metadata=_metadata_with_policy(
            "hook_optimization",
            failure_class="product",
            extra={"before_clip_count": before["clip_count"], "after_clip_count": after["clip_count"]},
        ),
    )


def transcript_timing_sanity(segments: list[dict[str, Any]] | None) -> ValidatorResult:
    if not segments:
        return _result(
            "transcript_timing_sanity",
            "quarantine",
            "Transcript timing segments unavailable",
            metadata=_metadata_with_policy("transcript_timing", failure_class="infrastructure"),
        )
    last_start = -1.0
    for segment in segments:
        start = float(segment.get("start", -1))
        end = float(segment.get("end", -1))
        if start < last_start or end < start:
            return _result(
                "transcript_timing_sanity",
                "fail",
                "Transcript timing was non-monotonic",
                score=0.0,
                metadata=_metadata_with_policy("transcript_timing", failure_class="product"),
            )
        last_start = start
    return _result(
        "transcript_timing_sanity",
        "pass",
        "Transcript timing was monotonic",
        score=1.0,
        metadata=_metadata_with_policy("transcript_timing"),
    )
