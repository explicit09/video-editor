from __future__ import annotations

import json
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

from .config import EvalConfig
from .runner import EvaluationRunner
from .storage import EvalStore


DASHBOARD_HTML = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>VideoEditor Eval Dashboard</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; background: #121316; color: #f3f4f6; }
    h1, h2 { margin: 0 0 12px 0; }
    .grid { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); margin-bottom: 24px; }
    .card { background: #1c1f26; border: 1px solid #2f3642; border-radius: 12px; padding: 16px; }
    table { width: 100%; border-collapse: collapse; margin-top: 8px; }
    th, td { border-bottom: 1px solid #2a2f39; text-align: left; padding: 8px; font-size: 13px; vertical-align: top; }
    .status-pass { color: #4ade80; }
    .status-fail { color: #f87171; }
    .status-quarantine, .status-unavailable, .status-skipped { color: #fbbf24; }
    .muted { color: #9ca3af; }
    code { color: #93c5fd; }
  </style>
</head>
<body>
  <h1>VideoEditor Eval Dashboard</h1>
  <div id="summary" class="grid"></div>
  <div class="card">
    <h2>Recent Runs</h2>
    <table id="runs"><thead><tr><th>Run</th><th>Workflow</th><th>Item</th><th>Status</th></tr></thead><tbody></tbody></table>
  </div>
  <div class="card">
    <h2>MCP Tool Coverage</h2>
    <table id="coverage"><thead><tr><th>Tool</th><th>Family</th><th>Status</th><th>Workflows</th></tr></thead><tbody></tbody></table>
  </div>
  <script>
    async function loadJson(path) {
      const response = await fetch(path);
      return await response.json();
    }
    function pill(status) {
      return `<span class="status-${status}">${status}</span>`;
    }
    async function render() {
      const summary = await loadJson('/api/summary');
      const runs = await loadJson('/api/runs');
      const coverage = await loadJson('/api/coverage');
      document.getElementById('summary').innerHTML = [
        ['Corpus Items', summary.corpus_items],
        ['Runs', summary.runs],
        ['Pass', summary.pass],
        ['Fail', summary.fail],
        ['Quarantine', summary.quarantine],
      ].map(([title, value]) => `<div class="card"><div class="muted">${title}</div><div style="font-size:32px;margin-top:8px">${value}</div></div>`).join('');
      document.querySelector('#runs tbody').innerHTML = runs.map(run =>
        `<tr><td><code>${run.run_id}</code></td><td>${run.workflow_id}</td><td>${run.corpus_item_id}</td><td>${pill(run.final_status || run.status)}</td></tr>`
      ).join('');
      document.querySelector('#coverage tbody').innerHTML = coverage.map(entry =>
        `<tr><td><code>${entry.tool_name}</code></td><td>${entry.family}</td><td>${pill(entry.status)}</td><td>${(entry.workflows || []).map(w => `<div><code>${w.workflow_id}</code> <span class="muted">${w.status}</span></div>`).join('') || '<span class="muted">none</span>'}</td></tr>`
      ).join('');
    }
    render();
  </script>
</body>
</html>
"""


class EvalHTTPRequestHandler(BaseHTTPRequestHandler):
    server: "EvalHTTPServer"  # type: ignore[assignment]

    def _send_json(self, payload: Any, status: int = HTTPStatus.OK) -> None:
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, body: str) -> None:
        encoded = body.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self._send_html(DASHBOARD_HTML)
            return
        if parsed.path == "/api/summary":
            self._send_json(self.server.store.summary())
            return
        if parsed.path == "/api/runs":
            limit = int(parse_qs(parsed.query).get("limit", ["100"])[0])
            self._send_json(self.server.store.list_runs(limit=limit))
            return
        if parsed.path.startswith("/api/run/"):
            run_id = parsed.path.rsplit("/", 1)[-1]
            self._send_json(self.server.store.get_run(run_id))
            return
        if parsed.path == "/api/coverage":
            self._send_json(self.server.store.coverage_report(self.server.config.stale_coverage_days))
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path != "/api/enqueue":
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        run_ids = self.server.runner.enqueue(
            payload["workflow_id"],
            split=payload.get("split"),
            source_family=payload.get("source_family"),
            limit=payload.get("limit"),
        )
        self._send_json({"queued_run_ids": run_ids}, status=HTTPStatus.ACCEPTED)

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        return


class EvalHTTPServer(ThreadingHTTPServer):
    def __init__(self, config: EvalConfig, store: EvalStore, runner: EvaluationRunner) -> None:
        super().__init__((config.dashboard_host, config.dashboard_port), EvalHTTPRequestHandler)
        self.config = config
        self.store = store
        self.runner = runner
        self._worker = threading.Thread(target=self._worker_loop, daemon=True)

    def start(self) -> None:
        self._worker.start()
        self.serve_forever()

    def _worker_loop(self) -> None:
        while True:
            self.runner.run_queued(limit=1)
            threading.Event().wait(2.0)
