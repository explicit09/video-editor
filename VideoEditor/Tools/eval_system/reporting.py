from __future__ import annotations

import json
import re
from collections import Counter
from dataclasses import dataclass
from typing import Any

from .models import WorkflowSpec


FAILURE_CATEGORY_PRODUCT = "product"
FAILURE_CATEGORY_INFRASTRUCTURE = "infrastructure"
FAILURE_CATEGORY_EXPECTED = "expected_failure_pack"
FAILURE_CATEGORY_MIXED = "mixed"
FAILURE_CATEGORY_UNKNOWN = "unknown"

INFRASTRUCTURE_PATTERNS = (
    r"\btimed out\b",
    r"\btimeout\b",
    r"\bconnection closed\b",
    r"\bparse error\b",
    r"\brate limit",
    r"\b429\b",
    r"\b504\b",
    r"\bgateway timeout\b",
    r"\bdisk full\b",
    r"\bno space left\b",
    r"\bunavailable\b",
    r"\bexport path was not detected\b",
    r"\bexport file does not exist\b",
    r"\bffmpeg not available\b",
    r"\bunable to resolve imported asset\b",
    r"\bunable to probe duration\b",
)

PRODUCT_PATTERNS = (
    r"\bblack frame\b",
    r"\btranscript was empty or missing\b",
    r"\baudio stream was expected but missing\b",
    r"\baudio stream was not expected but exists\b",
    r"\bnon-monotonic\b",
    r"\bscreenshot drifted\b",
    r"\bstructural failures\b",
)


@dataclass(frozen=True)
class FailureClassification:
    category: str
    reasons: list[str]
    signals: dict[str, list[str]]


def workflow_policy_summary(workflow: WorkflowSpec) -> dict[str, Any]:
    validator_policies = Counter()
    for validator in workflow.validators:
        validator_id = validator.get("id", "")
        if validator_id == "verify_playback_clean":
            validator_policies["source_content_match"] += 1
        elif validator_id == "verify_playback_post_edit_integrity":
            validator_policies["post_edit_integrity"] += 1
        elif validator_id == "transcript_present":
            validator_policies["transcript_presence"] += 1
        elif validator_id == "export_exists":
            validator_policies["artifact_presence"] += 1
        elif validator_id == "duration_sanity":
            validator_policies["media_probe"] += 1
        elif validator_id == "audio_present":
            validator_policies["audio_stream_presence"] += 1
        elif validator_id == "no_black_frames":
            validator_policies["render_quality"] += 1
        elif validator_id == "screenshot_baseline":
            validator_policies["visual_baseline"] += 1
        elif validator_id == "transcript_timing_sanity":
            validator_policies["transcript_timing"] += 1
        elif validator_id == "timeline_changed":
            validator_policies["timeline_mutation"] += 1
        elif validator_id == "broll_inserted":
            validator_policies["broll_enrichment"] += 1
        elif validator_id in {"hook_applied", "hook_structure_changed"}:
            validator_policies["hook_optimization"] += 1
        else:
            validator_policies["unknown"] += 1

    long_form_guardrails: dict[str, Any] = {}
    if workflow.max_duration_seconds is not None:
        long_form_guardrails["max_duration_seconds"] = workflow.max_duration_seconds
    if workflow.max_duration_by_source_family:
        long_form_guardrails["max_duration_by_source_family"] = dict(workflow.max_duration_by_source_family)

    return {
        "workflow_id": workflow.id,
        "validator_policies": dict(validator_policies),
        "allowed_source_families": list(workflow.allowed_source_families),
        "eligibility_tags": list(workflow.eligibility_tags),
        "long_form_guardrails": long_form_guardrails,
    }


def classify_run_failure(
    run: dict[str, Any],
    corpus_item: dict[str, Any],
    validator_rows: list[dict[str, Any]],
    judge_rows: list[dict[str, Any]],
) -> FailureClassification:
    if (run.get("final_status") or run.get("status")) == "pass":
        return FailureClassification(category="pass", reasons=["run passed"], signals={})

    tags = set(_load_json_field(corpus_item.get("tags_json"), []))
    source_family = corpus_item.get("source_family")
    if source_family == "failure" or "failure-case" in tags:
        return FailureClassification(
            category=FAILURE_CATEGORY_EXPECTED,
            reasons=["Corpus item is tagged as a failure-case"],
            signals={"expected": ["failure-case corpus item"]},
        )

    infra_signals: list[str] = []
    product_signals: list[str] = []
    unknown_signals: list[str] = []

    for validator in validator_rows:
        metadata = _load_json_field(validator.get("metadata_json"), {})
        detail = validator.get("details", "")
        _record_failure_signal(
            detail,
            metadata,
            infra_signals=infra_signals,
            product_signals=product_signals,
            unknown_signals=unknown_signals,
        )

    for judge in judge_rows:
        metadata = _load_json_field(judge.get("metadata_json"), {})
        detail = judge.get("explanation", "")
        _record_failure_signal(
            detail,
            metadata,
            infra_signals=infra_signals,
            product_signals=product_signals,
            unknown_signals=unknown_signals,
        )

    for reason in _load_json_field(run.get("reasons_json"), []):
        _record_failure_signal(
            str(reason),
            {},
            infra_signals=infra_signals,
            product_signals=product_signals,
            unknown_signals=unknown_signals,
        )

    if infra_signals and product_signals:
        return FailureClassification(
            category=FAILURE_CATEGORY_MIXED,
            reasons=["Run shows both infrastructure and product-failure signals"],
            signals={"infrastructure": infra_signals, "product": product_signals},
        )
    if infra_signals:
        return FailureClassification(
            category=FAILURE_CATEGORY_INFRASTRUCTURE,
            reasons=["Run matches infrastructure-failure signals"],
            signals={"infrastructure": infra_signals},
        )
    if product_signals:
        return FailureClassification(
            category=FAILURE_CATEGORY_PRODUCT,
            reasons=["Run matches product-failure signals"],
            signals={"product": product_signals},
        )
    return FailureClassification(
        category=FAILURE_CATEGORY_UNKNOWN,
        reasons=["Run did not match an explicit failure category"],
        signals={"unknown": unknown_signals or ["no explicit classification signals"]},
    )


def _load_json_field(value: Any, default: Any) -> Any:
    if value is None:
        return default
    if isinstance(value, (list, dict)):
        return value
    try:
        return json.loads(value)
    except (TypeError, json.JSONDecodeError):
        return default


def _record_failure_signal(
    text: str,
    metadata: dict[str, Any],
    *,
    infra_signals: list[str],
    product_signals: list[str],
    unknown_signals: list[str],
) -> None:
    failure_class = metadata.get("failure_class")
    if failure_class == FAILURE_CATEGORY_INFRASTRUCTURE:
        infra_signals.append(text)
        return
    if failure_class == FAILURE_CATEGORY_PRODUCT:
        product_signals.append(text)
        return
    if failure_class == FAILURE_CATEGORY_EXPECTED:
        return

    lowered = text.lower()
    if any(re.search(pattern, lowered) for pattern in INFRASTRUCTURE_PATTERNS):
        infra_signals.append(text)
        return
    if any(re.search(pattern, lowered) for pattern in PRODUCT_PATTERNS):
        product_signals.append(text)
        return
    if text:
        unknown_signals.append(text)
