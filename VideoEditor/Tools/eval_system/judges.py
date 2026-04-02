from __future__ import annotations

import json
import mimetypes
import hashlib
import urllib.error
import time
import urllib.parse
import urllib.request
import uuid
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

from .config import EvalConfig
from .models import JudgeResult, JudgeTask
from .storage import EvalStore


class JudgeAdapter(ABC):
    provider_name: str

    def __init__(self, config: EvalConfig) -> None:
        self.config = config

    @abstractmethod
    def is_configured(self) -> bool:
        raise NotImplementedError

    @abstractmethod
    def evaluate(self, task: JudgeTask, evidence_paths: list[Path]) -> JudgeResult:
        raise NotImplementedError


class GeminiJudgeAdapter(JudgeAdapter):
    provider_name = "gemini"

    def is_configured(self) -> bool:
        return bool(self.config.gemini_api_key)

    def _request(self, url: str, *, method: str = "POST", headers: dict[str, str] | None = None, payload: bytes | None = None) -> tuple[dict[str, Any], dict[str, str]]:
        request_headers = headers or {}
        req = urllib.request.Request(url, data=payload, headers=request_headers, method=method)
        with urllib.request.urlopen(req, timeout=300) as response:
            body = response.read()
            response_headers = {key: value for key, value in response.headers.items()}
        if not body:
            return {}, response_headers
        decoded = body.decode("utf-8")
        if not decoded.strip():
            return {}, response_headers
        return json.loads(decoded), response_headers

    def _upload_file(self, media_path: Path) -> tuple[str, str]:
        mime_type = mimetypes.guess_type(media_path.name)[0] or "application/octet-stream"
        start_url = (
            "https://generativelanguage.googleapis.com/upload/v1beta/files"
            f"?key={urllib.parse.quote(self.config.gemini_api_key or '')}"
        )
        start_payload = json.dumps({"file": {"display_name": media_path.name}}).encode("utf-8")
        _, headers = self._request(
            start_url,
            headers={
                "Content-Type": "application/json",
                "X-Goog-Upload-Protocol": "resumable",
                "X-Goog-Upload-Command": "start",
                "X-Goog-Upload-Header-Content-Length": str(media_path.stat().st_size),
                "X-Goog-Upload-Header-Content-Type": mime_type,
            },
            payload=start_payload,
        )
        upload_url = headers.get("X-Goog-Upload-URL")
        if not upload_url:
            raise RuntimeError("Gemini upload did not return X-Goog-Upload-URL")
        payload = media_path.read_bytes()
        response, _ = self._request(
            upload_url,
            headers={
                "Content-Length": str(len(payload)),
                "X-Goog-Upload-Offset": "0",
                "X-Goog-Upload-Command": "upload, finalize",
            },
            payload=payload,
        )
        file_info = response.get("file", {})
        return file_info["uri"], mime_type

    def _wait_for_file_ready(self, file_uri: str) -> None:
        file_name = file_uri.split("/v1beta/", 1)[-1]
        url = (
            f"https://generativelanguage.googleapis.com/v1beta/{file_name}"
            f"?key={urllib.parse.quote(self.config.gemini_api_key or '')}"
        )
        deadline = time.time() + 180
        last_state = "UNKNOWN"
        while time.time() < deadline:
            response, _ = self._request(url, method="GET")
            state = str(response.get("state", "ACTIVE")).upper()
            last_state = state
            if state == "ACTIVE":
                return
            if state == "FAILED":
                raise RuntimeError(f"Gemini file processing failed for {file_name}")
            time.sleep(5)
        raise TimeoutError(f"Timed out waiting for Gemini file readiness; last state={last_state}")

    def evaluate(self, task: JudgeTask, evidence_paths: list[Path]) -> JudgeResult:
        if not self.is_configured():
            return JudgeResult(task.judge_id, self.provider_name, task.rubric_id, "unavailable", None, None, "GEMINI_API_KEY is not configured")
        if not evidence_paths:
            return JudgeResult(task.judge_id, self.provider_name, task.rubric_id, "skipped", None, None, "No evidence paths were provided")
        try:
            file_uri, mime_type = self._upload_file(evidence_paths[0])
            self._wait_for_file_ready(file_uri)
            url = (
                f"https://generativelanguage.googleapis.com/v1beta/models/{self.config.gemini_model}:generateContent"
                f"?key={urllib.parse.quote(self.config.gemini_api_key or '')}"
            )
            payload = json.dumps(
                {
                    "contents": [
                        {
                            "parts": [
                                {"text": task.prompt},
                                {"file_data": {"file_uri": file_uri, "mime_type": mime_type}},
                            ]
                        }
                    ]
                }
            ).encode("utf-8")
            response, _ = self._request(url, headers={"Content-Type": "application/json"}, payload=payload)
            text = response["candidates"][0]["content"]["parts"][0].get("text", "")
            parsed = _extract_judge_json(text)
            return JudgeResult(
                judge_id=task.judge_id,
                provider=self.provider_name,
                rubric_id=task.rubric_id,
                status=_normalize_status(parsed.get("status", "pass")),
                score=_coerce_number(parsed.get("score")),
                confidence=_coerce_number(parsed.get("confidence")),
                explanation=parsed.get("explanation", text.strip()),
                evidence_paths=[str(path) for path in evidence_paths],
                metadata={"raw_text": text},
            )
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if exc.code == 429:
                return JudgeResult(
                    task.judge_id,
                    self.provider_name,
                    task.rubric_id,
                    "skipped",
                    None,
                    None,
                    f"Gemini rate limited: {body[:500]}",
                    metadata={"skip_reason": "rate_limited"},
                )
            return JudgeResult(task.judge_id, self.provider_name, task.rubric_id, "quarantine", None, None, f"Gemini evaluation failed: HTTP {exc.code}: {body[:500]}")
        except Exception as exc:  # noqa: BLE001
            return JudgeResult(task.judge_id, self.provider_name, task.rubric_id, "quarantine", None, None, f"Gemini evaluation failed: {exc}")


class TwelveLabsJudgeAdapter(JudgeAdapter):
    provider_name = "twelvelabs"

    def __init__(self, config: EvalConfig) -> None:
        super().__init__(config)
        self._index_id_cache: str | None = config.twelvelabs_index_id

    def is_configured(self) -> bool:
        return bool(self.config.twelvelabs_api_key)

    def _request(self, path: str, *, method: str = "GET", headers: dict[str, str] | None = None, payload: bytes | None = None, timeout: int = 300) -> dict[str, Any]:
        request_headers = {"x-api-key": self.config.twelvelabs_api_key or "", "Accept": "application/json"}
        request_headers.update(headers or {})
        req = urllib.request.Request(f"https://api.twelvelabs.io{path}", data=payload, headers=request_headers, method=method)
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read().decode("utf-8")
        return _decode_best_json_object(body)

    def _ensure_index(self) -> str:
        if self._index_id_cache:
            return self._index_id_cache
        payload = json.dumps(
            {
                "index_name": f"videoeditor-eval-{uuid.uuid4().hex[:8]}",
                "models": [
                    {"model_name": "marengo3.0", "model_options": ["visual", "audio"]},
                    {"model_name": "pegasus1.2", "model_options": ["visual", "audio"]},
                ],
                "addons": ["thumbnail"],
            }
        ).encode("utf-8")
        response = self._request("/v1.3/indexes", method="POST", headers={"Content-Type": "application/json"}, payload=payload)
        self._index_id_cache = response["_id"]
        return self._index_id_cache

    def _multipart_body(self, fields: dict[str, str], file_field: str, file_path: Path) -> tuple[bytes, str]:
        boundary = f"----VideoEditorEval{uuid.uuid4().hex}"
        lines: list[bytes] = []
        for key, value in fields.items():
            lines.append(f"--{boundary}\r\n".encode())
            lines.append(f'Content-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
        mime_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
        lines.append(f"--{boundary}\r\n".encode())
        lines.append(
            (
                f'Content-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'
                f"Content-Type: {mime_type}\r\n\r\n"
            ).encode()
        )
        lines.append(file_path.read_bytes())
        lines.append(b"\r\n")
        lines.append(f"--{boundary}--\r\n".encode())
        return b"".join(lines), boundary

    def _upload_and_index(self, media_path: Path) -> str:
        index_id = self._ensure_index()
        payload, boundary = self._multipart_body({"index_id": index_id}, "video_file", media_path)
        response = self._request(
            "/v1.3/tasks",
            method="POST",
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            payload=payload,
            timeout=900,
        )
        task_id = response["_id"]
        for _ in range(120):
            task = self._request(f"/v1.3/tasks/{task_id}")
            status = task.get("status", "").lower()
            if status == "ready":
                return task["video_id"]
            if status in {"failed", "invalid"}:
                raise RuntimeError(f"TwelveLabs indexing failed: {task}")
            time.sleep(5)
        raise TimeoutError("Timed out waiting for TwelveLabs indexing task")

    def evaluate(self, task: JudgeTask, evidence_paths: list[Path]) -> JudgeResult:
        if not self.is_configured():
            return JudgeResult(task.judge_id, self.provider_name, task.rubric_id, "unavailable", None, None, "TWELVELABS_API_KEY is not configured")
        if not evidence_paths:
            return JudgeResult(task.judge_id, self.provider_name, task.rubric_id, "skipped", None, None, "No evidence paths were provided")
        try:
            video_id = self._upload_and_index(evidence_paths[0])
            payload = json.dumps(
                {
                    "video_id": video_id,
                    "prompt": task.prompt,
                    "temperature": 0.1,
                    "stream": False,
                    "response_format": {
                        "type": "json_schema",
                        "json_schema": _judge_response_schema(),
                    },
                }
            ).encode("utf-8")
            response = self._request(
                "/v1.3/analyze",
                method="POST",
                headers={"Content-Type": "application/json"},
                payload=payload,
                timeout=300,
            )
            text = response.get("data") or response.get("summary") or json.dumps(response)
            parsed = _extract_judge_json(text)
            return JudgeResult(
                judge_id=task.judge_id,
                provider=self.provider_name,
                rubric_id=task.rubric_id,
                status=_normalize_status(parsed.get("status", "pass")),
                score=_coerce_number(parsed.get("score")),
                confidence=_coerce_number(parsed.get("confidence")),
                explanation=parsed.get("explanation", str(text).strip()),
                evidence_paths=[str(path) for path in evidence_paths],
                metadata={"raw_text": text, "video_id": video_id},
            )
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if exc.code == 429:
                return JudgeResult(
                    task.judge_id,
                    self.provider_name,
                    task.rubric_id,
                    "skipped",
                    None,
                    None,
                    f"TwelveLabs rate limited: {body[:500]}",
                    metadata={"skip_reason": "rate_limited"},
                )
            return JudgeResult(task.judge_id, self.provider_name, task.rubric_id, "quarantine", None, None, f"TwelveLabs evaluation failed: HTTP {exc.code}: {body[:500]}")
        except Exception as exc:  # noqa: BLE001
            return JudgeResult(task.judge_id, self.provider_name, task.rubric_id, "quarantine", None, None, f"TwelveLabs evaluation failed: {exc}")


def _extract_judge_json(text: str) -> dict[str, Any]:
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = stripped.strip("`")
        if "\n" in stripped:
            stripped = stripped.split("\n", 1)[1]
        if stripped.endswith("```"):
            stripped = stripped[:-3].strip()
    decoder = json.JSONDecoder()
    start = stripped.find("{")
    if start != -1:
        try:
            parsed, _ = decoder.raw_decode(stripped[start:])
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass
    if stripped.startswith("{") and stripped.endswith("}"):
        return json.loads(stripped)
    start = stripped.find("{")
    end = stripped.rfind("}")
    if start != -1 and end != -1 and end > start:
        return json.loads(stripped[start : end + 1])
    return {"status": "quarantine", "explanation": stripped or "Judge did not return structured JSON"}


def _normalize_status(value: Any) -> str:
    if isinstance(value, bool):
        return "pass" if value else "fail"
    if value is None:
        return "quarantine"
    normalized = str(value).strip().lower()
    if normalized in {"pass", "passed", "success", "ok", "true"}:
        return "pass"
    if normalized in {"fail", "failed", "false"}:
        return "fail"
    if normalized in {"quarantine", "review", "uncertain"}:
        return "quarantine"
    if normalized in {"skipped", "unavailable"}:
        return normalized
    return "quarantine"


def _judge_response_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "properties": {
            "status": {"type": "string", "enum": ["pass", "fail", "quarantine"]},
            "score": {"type": "number"},
            "confidence": {"type": "number"},
            "explanation": {"type": "string"},
        },
        "required": ["status", "score", "confidence", "explanation"],
    }


def _decode_best_json_object(text: str) -> dict[str, Any]:
    stripped = text.strip()
    if not stripped:
        return {}
    try:
        parsed = json.loads(stripped)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass
    decoder = json.JSONDecoder()
    objects: list[dict[str, Any]] = []
    index = 0
    while index < len(stripped):
        next_start = stripped.find("{", index)
        if next_start == -1:
            break
        try:
            parsed, offset = decoder.raw_decode(stripped[next_start:])
        except json.JSONDecodeError:
            index = next_start + 1
            continue
        if isinstance(parsed, dict):
            objects.append(parsed)
        index = next_start + offset
    if objects:
        preferred_keys = ("data", "summary", "output", "result", "status", "error")
        for candidate in reversed(objects):
            if any(key in candidate for key in preferred_keys):
                return candidate
        return objects[-1]
    raise json.JSONDecodeError("Unable to decode JSON object", stripped, 0)


def _coerce_number(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


class JudgeGateway:
    def __init__(self, config: EvalConfig, store: EvalStore, extra_adapters: list[JudgeAdapter] | None = None) -> None:
        self.config = config
        self.store = store
        self.adapters: list[JudgeAdapter] = [
            GeminiJudgeAdapter(config),
            TwelveLabsJudgeAdapter(config),
        ]
        if extra_adapters:
            self.adapters.extend(extra_adapters)

    def evaluate(self, task: JudgeTask, evidence_paths: list[Path], *, split: str) -> list[JudgeResult]:
        cache_key = _build_cache_key(task, evidence_paths)
        results: list[JudgeResult] = []
        for adapter in self.adapters:
            required = adapter.provider_name in self.config.primary_judge_providers
            allowed_splits = self.config.judge_required_splits if required else self.config.judge_optional_splits
            if split not in allowed_splits:
                results.append(
                    JudgeResult(
                        judge_id=task.judge_id,
                        provider=adapter.provider_name,
                        rubric_id=task.rubric_id,
                        status="skipped",
                        score=None,
                        confidence=None,
                        explanation=f"{adapter.provider_name} skipped for split {split} by policy",
                        evidence_paths=[str(path) for path in evidence_paths],
                        metadata={"required": required, "skip_reason": "split_policy"},
                    )
                )
                continue
            cached = self.store.get_cached_judge_result(adapter.provider_name, cache_key)
            if cached is not None:
                cached.metadata = dict(cached.metadata, cached=True, required=required)
                results.append(cached)
                continue
            result = adapter.evaluate(task, evidence_paths)
            result.metadata = dict(result.metadata, required=required)
            if result.status not in {"skipped", "unavailable"} or result.metadata.get("skip_reason") != "rate_limited":
                self.store.cache_judge_result(adapter.provider_name, cache_key, result)
            results.append(result)
        return results


class MockJudgeAdapter(JudgeAdapter):
    provider_name = "mock"

    def __init__(self, responses: dict[str, dict[str, Any]]) -> None:
        self.responses = responses

    def is_configured(self) -> bool:
        return True

    def evaluate(self, task: JudgeTask, evidence_paths: list[Path]) -> JudgeResult:
        payload = self.responses.get(task.judge_id, {"status": "pass", "score": 1.0, "confidence": 0.9, "explanation": "mock"})
        return JudgeResult(
            judge_id=task.judge_id,
            provider=self.provider_name,
            rubric_id=task.rubric_id,
            status=payload.get("status", "pass"),
            score=payload.get("score"),
            confidence=payload.get("confidence"),
            explanation=payload.get("explanation", "mock"),
            evidence_paths=[str(path) for path in evidence_paths],
            metadata=payload.get("metadata", {}),
        )


def _build_cache_key(task: JudgeTask, evidence_paths: list[Path]) -> str:
    digest = hashlib.sha256()
    digest.update(task.judge_id.encode("utf-8"))
    digest.update(b"\0")
    digest.update(task.rubric_id.encode("utf-8"))
    digest.update(b"\0")
    digest.update(task.prompt.encode("utf-8"))
    for path in evidence_paths:
        digest.update(b"\0")
        digest.update(path.name.encode("utf-8"))
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                digest.update(chunk)
    return digest.hexdigest()
