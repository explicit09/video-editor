from __future__ import annotations

import datetime as dt
import hashlib
import json
import mimetypes
import re
import uuid
from pathlib import Path
from typing import Any


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def iso_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def utc_timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")


def stable_split(value: str) -> str:
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
    bucket = int(digest[:8], 16) % 10
    if bucket < 6:
        return "development"
    if bucket < 8:
        return "calibration"
    return "holdout"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def guess_mime_type(path: Path) -> str:
    return mimetypes.guess_type(path.name)[0] or "application/octet-stream"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=False))


def nested_get(data: dict[str, Any], dotted_key: str) -> Any:
    current: Any = data
    for segment in dotted_key.split("."):
        if isinstance(current, dict) and segment in current:
            current = current[segment]
            continue
        raise KeyError(dotted_key)
    return current


def resolve_template(value: Any, context: dict[str, Any]) -> Any:
    if isinstance(value, str):
        exact_match = re.fullmatch(r"\$\{([^}]+)\}", value)
        if exact_match:
            return nested_get(context, exact_match.group(1))
        matches = re.findall(r"\$\{([^}]+)\}", value)
        resolved = value
        for match in matches:
            replacement = nested_get(context, match)
            resolved = resolved.replace(f"${{{match}}}", str(replacement))
        return resolved
    if isinstance(value, dict):
        if "$uuid" in value:
            key = value["$uuid"]
            generated = context.setdefault("_uuids", {}).get(key)
            if generated is None:
                generated = str(uuid.uuid4()).upper()
                context["_uuids"][key] = generated
            return generated
        return {key: resolve_template(inner, context) for key, inner in value.items()}
    if isinstance(value, list):
        return [resolve_template(item, context) for item in value]
    return value


def parse_output_path(output: str) -> Path | None:
    patterns = [
        r"saved to:\s*(.+)",
        r"exported to:\s*(.+)",
        r"written to:\s*(.+)",
        r"path:\s*(/.+)",
        r"output:\s*(/.+)",
    ]
    for pattern in patterns:
        match = re.search(pattern, output, flags=re.IGNORECASE)
        if match:
            return Path(match.group(1).strip())
    return None


TRACK_LINE_RE = re.compile(
    r"^\s*(?P<name>.+?) \((?P<type>[^,]+), id=(?P<id>[A-F0-9-]+)\)(?: (?P<flags>\[[^\]]+\]))?: (?P<clips>.*)$"
)
CLIP_RE = re.compile(
    r"(?P<label>.+?) \[id=(?P<id>[A-F0-9-]+), (?P<start>[0-9.]+)s-(?P<end>[0-9.]+)s\](?: \((?P<props>[^)]*)\))?"
)
MARKER_LINE_RE = re.compile(r"^\s*(?P<time>[0-9.]+)s: (?P<label>.+?) \[id=(?P<id>[A-F0-9-]+)\]$")
ASSET_LINE_RE = re.compile(r"^\s*(?P<name>.+) \(ID: (?P<id>[A-F0-9-]+), (?P<duration>[0-9.]+)s\)$")
SNAPSHOT_LINE_RE = re.compile(r"^(?P<name>.+) \(ID: (?P<id>[A-F0-9-]+), (?P<timestamp>.+)\)$")
BROLL_SUGGESTION_RE = re.compile(
    r"#(?P<rank>\d+)\s+Insert\s+'(?P<asset>[^']+)'\s+at\s+(?P<start>[0-9.]+)s\s+\((?P<duration>[0-9.]+)s duration\)",
    flags=re.IGNORECASE,
)


def parse_editor_state(output: str) -> dict[str, Any]:
    parsed: dict[str, Any] = {"tracks": [], "markers": [], "assets": [], "playhead": None, "duration": None}
    section: str | None = None
    for raw_line in output.splitlines():
        line = raw_line.rstrip()
        if line.startswith("Tracks ("):
            section = "tracks"
            continue
        if line.startswith("Markers ("):
            section = "markers"
            continue
        if line.startswith("Assets ("):
            section = "assets"
            continue
        if line.startswith("Playhead:"):
            match = re.search(r"([0-9.]+)s", line)
            parsed["playhead"] = float(match.group(1)) if match else None
            continue
        if line.startswith("Duration:"):
            match = re.search(r"([0-9.]+)s", line)
            parsed["duration"] = float(match.group(1)) if match else None
            continue
        if not line.strip() or line.startswith("==="):
            continue

        if section == "tracks":
            if line.strip() == "(none)":
                continue
            track_match = TRACK_LINE_RE.match(line)
            if not track_match:
                continue
            flags = track_match.group("flags") or ""
            clip_blob = track_match.group("clips")
            clips: list[dict[str, Any]] = []
            if clip_blob != "empty":
                for match in CLIP_RE.finditer(clip_blob):
                    props_blob = match.group("props") or ""
                    props = [part.strip() for part in props_blob.split(",") if part.strip()]
                    link_group = None
                    for prop in props:
                        if prop.startswith("link="):
                            link_group = prop.split("=", 1)[1]
                            break
                    clips.append(
                        {
                            "label": match.group("label").strip(),
                            "id": match.group("id"),
                            "start": float(match.group("start")),
                            "end": float(match.group("end")),
                            "props": props,
                            "link_group": link_group,
                        }
                    )
            parsed["tracks"].append(
                {
                    "name": track_match.group("name"),
                    "type": track_match.group("type"),
                    "id": track_match.group("id"),
                    "flags": [part.strip() for part in flags.strip("[]").split(",") if part.strip()],
                    "clips": clips,
                }
            )
            continue

        if section == "markers":
            match = MARKER_LINE_RE.match(line)
            if match:
                parsed["markers"].append(
                    {
                        "time": float(match.group("time")),
                        "label": match.group("label"),
                        "id": match.group("id"),
                    }
                )
            continue

        if section == "assets":
            if line.strip() == "(none)":
                continue
            match = ASSET_LINE_RE.match(line)
            if match:
                parsed["assets"].append(
                    {
                        "name": match.group("name"),
                        "id": match.group("id"),
                        "duration": float(match.group("duration")),
                    }
                )
    for track in parsed["tracks"]:
        track["clips"] = sorted(track["clips"], key=lambda clip: (clip["start"], clip["end"], clip["id"]))
    return parsed


def parse_snapshot_list(output: str) -> list[dict[str, str]]:
    snapshots: list[dict[str, str]] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        match = SNAPSHOT_LINE_RE.match(line)
        if match:
            snapshots.append(
                {
                    "name": match.group("name"),
                    "id": match.group("id"),
                    "timestamp": match.group("timestamp"),
                }
            )
    return snapshots


def parse_broll_suggestions(output: str) -> list[dict[str, Any]]:
    suggestions: list[dict[str, Any]] = []
    for match in BROLL_SUGGESTION_RE.finditer(output):
        suggestions.append(
            {
                "rank": int(match.group("rank")),
                "asset": match.group("asset"),
                "start_time": float(match.group("start")),
                "duration": float(match.group("duration")),
            }
        )
    return suggestions
