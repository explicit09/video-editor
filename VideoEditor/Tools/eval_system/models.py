from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class CorpusItem:
    id: str
    source_family: str
    relative_path: str
    media_type: str
    split: str
    content_tags: list[str]
    tasks: list[str]
    annotations: dict[str, Any]
    expected: dict[str, Any]
    probe: dict[str, Any]
    filename: str | None = None

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "CorpusItem":
        annotations = dict(data.get("annotations", {}))
        split = data.get("split") or annotations.get("split") or "development"
        probe = dict(data.get("probe", {}))
        if not probe:
            duration = data.get("duration") or data.get("duration_seconds")
            resolution = data.get("resolution")
            has_audio = data.get("has_audio")
            fps = data.get("fps")
            if duration is not None:
                probe["duration_seconds"] = duration
            if resolution is not None:
                probe["resolution"] = resolution
            if has_audio is not None:
                probe["has_audio"] = has_audio
            if fps is not None:
                probe["fps"] = fps
        return cls(
            id=data["id"],
            source_family=data.get("source_family") or data.get("source_type", "unknown"),
            relative_path=data["relative_path"],
            media_type=data.get("media_type", "video"),
            split=split,
            content_tags=list(data.get("content_tags", [])),
            tasks=list(data.get("tasks", [])),
            annotations=annotations,
            expected=dict(data.get("expected", {})),
            probe=probe,
            filename=data.get("filename"),
        )

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["annotations"] = dict(self.annotations, split=self.split)
        return payload


@dataclass
class CorpusManifest:
    name: str
    version: str
    created: str
    description: str
    splits: dict[str, int]
    items: list[CorpusItem]

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "CorpusManifest":
        return cls(
            name=data.get("name") or data.get("dataset_name", "eval-corpus"),
            version=data.get("version", "2.0"),
            created=data.get("created") or data.get("created_at", ""),
            description=data.get("description", ""),
            splits=dict(data.get("splits", {})),
            items=[CorpusItem.from_dict(item) for item in data.get("items", [])],
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "version": self.version,
            "created": self.created,
            "description": self.description,
            "splits": self.splits,
            "items": [item.to_dict() for item in self.items],
        }


@dataclass
class WorkflowSpec:
    id: str
    description: str
    eligibility_tags: list[str]
    allowed_source_families: list[str]
    max_duration_seconds: float | None
    max_duration_by_source_family: dict[str, float]
    declared_tools: list[str]
    steps: list[dict[str, Any]]
    validators: list[dict[str, Any]]
    judges: list[dict[str, Any]]

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "WorkflowSpec":
        return cls(
            id=data["id"],
            description=data.get("description", ""),
            eligibility_tags=list(data.get("eligibility_tags", [])),
            allowed_source_families=list(data.get("allowed_source_families", [])),
            max_duration_seconds=data.get("max_duration_seconds"),
            max_duration_by_source_family=dict(data.get("max_duration_by_source_family", {})),
            declared_tools=list(data.get("declared_tools", [])),
            steps=list(data.get("steps", [])),
            validators=list(data.get("validators", [])),
            judges=list(data.get("judges", [])),
        )


@dataclass
class ArtifactRecord:
    label: str
    path: str
    kind: str
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class ValidatorResult:
    validator_id: str
    status: str
    score: float | None
    details: str
    evidence_paths: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class JudgeTask:
    judge_id: str
    rubric_id: str
    prompt: str
    artifact_labels: list[str]
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class JudgeResult:
    judge_id: str
    provider: str
    rubric_id: str
    status: str
    score: float | None
    confidence: float | None
    explanation: str
    evidence_paths: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class FinalDecision:
    status: str
    reasons: list[str]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class RunRecord:
    run_id: str
    workflow_id: str
    corpus_item_id: str
    status: str
    started_at: str | None = None
    finished_at: str | None = None


@dataclass
class ToolDescriptor:
    name: str
    family: str
    description: str
    input_schema: dict[str, Any]
