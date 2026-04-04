from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Any
from urllib import request

from .models import ToolDescriptor


class MCPError(RuntimeError):
    pass


def classify_tool_family(name: str) -> str:
    if name.startswith(("set_clip_", "move_clip", "split_clip", "trim_clip", "duplicate_clip", "roll_trim")):
        return "clip"
    if name.endswith("_track") or name.startswith(("mute_track", "lock_track", "set_track_", "add_track", "remove_track")):
        return "track"
    if "transcript" in name or "transcribe" in name:
        return "transcript"
    if "short" in name:
        return "shorts"
    if "export" in name:
        return "export"
    if name.startswith(("import_", "add_to_timeline", "clear_project", "save_snapshot", "restore_snapshot")):
        return "project"
    if name.startswith(("verify_", "take_screenshot", "set_zoom", "get_state")):
        return "verification"
    return "analysis"


@dataclass
class MCPClient:
    url: str
    session_name: str = "videoeditor-eval"

    def __post_init__(self) -> None:
        self._initialized = False
        self._request_id = 0
        self.initialize()

    def initialize(self) -> None:
        if self._initialized:
            return
        self._post(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "clientInfo": {"name": self.session_name, "version": "0.1"},
                "capabilities": {},
            },
        )
        self._post("notifications/initialized", None)
        self._initialized = True

    def _post(self, method: str, params: dict[str, Any] | None, timeout: int = 120) -> dict[str, Any]:
        self._request_id += 1
        payload = {"jsonrpc": "2.0", "id": self._request_id, "method": method}
        if params is not None:
            payload["params"] = params
        last_error: Exception | None = None
        for attempt in range(3):
            req = request.Request(
                self.url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                with request.urlopen(req, timeout=timeout) as response:
                    data = json.loads(response.read().decode("utf-8"))
            except json.JSONDecodeError as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(0.5 * (attempt + 1))
                    continue
                raise
            if "error" in data:
                error = data["error"]
                if isinstance(error, dict) and error.get("code") == -32700 and attempt < 2:
                    last_error = MCPError(error)
                    time.sleep(0.5 * (attempt + 1))
                    continue
                raise MCPError(error)
            return data
        if last_error is not None:
            raise last_error
        raise MCPError("Unknown MCP post failure")

    def call_tool(self, name: str, arguments: dict[str, Any] | None = None, timeout: int = 180) -> str:
        response = self._post(
            "tools/call",
            {"name": name, "arguments": arguments or {}},
            timeout=timeout,
        )
        return "".join(
            item.get("text", "")
            for item in response.get("result", {}).get("content", [])
            if item.get("type") == "text"
        )

    def read_resource(self, uri: str, timeout: int = 60) -> Any:
        response = self._post("resources/read", {"uri": uri}, timeout=timeout)
        contents = response.get("result", {}).get("contents", [])
        if not contents:
            raise MCPError(f"Resource {uri} returned no contents")
        return json.loads(contents[0]["text"])

    def list_tools(self, timeout: int = 60) -> list[ToolDescriptor]:
        response = self._post("tools/list", {}, timeout=timeout)
        descriptors = []
        for tool in response.get("result", {}).get("tools", []):
            descriptors.append(
                ToolDescriptor(
                    name=tool["name"],
                    family=classify_tool_family(tool["name"]),
                    description=tool.get("description", ""),
                    input_schema=tool.get("inputSchema", {}),
                )
            )
        return descriptors


class RecordingMCPClient(MCPClient):
    def __init__(self, url: str, session_name: str = "videoeditor-eval") -> None:
        self.observed_tools: list[str] = []
        super().__init__(url=url, session_name=session_name)

    def call_tool(self, name: str, arguments: dict[str, Any] | None = None, timeout: int = 180) -> str:
        output = super().call_tool(name, arguments=arguments, timeout=timeout)
        self.observed_tools.append(name)
        return output
