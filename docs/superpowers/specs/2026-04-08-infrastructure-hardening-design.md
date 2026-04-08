# Infrastructure Hardening Design Spec

**Date:** 2026-04-08
**Status:** Approved
**Scope:** MCP security, CI, release pipeline, observability, Python reproducibility

## Context

The VideoEditor is a native macOS app (Swift + SwiftUI + AVFoundation + Metal) with 116 MCP tools exposed at localhost:8420. Current state:

- **MCP server binds to 0.0.0.0** (all interfaces) with `Access-Control-Allow-Origin: *` and zero auth. This is a security vulnerability.
- **No CI/CD** — builds and tests are manual-only.
- **No release pipeline** — no code signing, notarization, or distribution automation. Apple Developer Program is available.
- **No observability** — no crash reporting, telemetry, or structured logging. Just `print()` statements.
- **Python deps are implicit** — eval system and tools have no requirements file. `Package.resolved` is gitignored.

### Constraints

- Solo dev now, teammates possible later.
- MCP server ships in production builds — external AI agents connect.
- MCP trust model: trust the local machine, prevent network/CORS attacks.
- Full eval corpus (305 videos) stays local. CI only needs build + unit tests.
- Crash reports + anonymized analytics are acceptable.
- No Firebase.

## 1. MCP Server Hardening

### Problem

MCPServer.swift creates an NWListener on port 8420 with default parameters, which binds to all network interfaces. Combined with `Access-Control-Allow-Origin: *`, any device on the local network — or any website in a browser — can call all 116 MCP tools.

### Design

**Loopback-only binding.** Configure NWListener to only accept connections from 127.0.0.1. Two layers of defense:

1. **Listener level:** Set the NWListener's parameters to restrict to loopback. NWListener doesn't directly support interface restriction, so we add a connection-level guard.
2. **Connection-level guard:** In `newConnectionHandler`, inspect the remote endpoint. Reject any connection where the remote address is not `127.0.0.1` or `::1`.

**Restrictive CORS.** Replace `Access-Control-Allow-Origin: *` with:
- `Access-Control-Allow-Origin: http://127.0.0.1` (match the request Origin header against an allowlist)
- Allowlist: any Origin starting with `http://127.0.0.1`, `http://localhost`, or `http://[::1]` (any port, since local tools may run on various ports)
- Add `Vary: Origin` header.
- Reject preflight requests from non-allowed origins.

**No auth token.** The trust model is "any local process is trusted." Network isolation is the security boundary, not application-level auth.

### Files

- `VideoEditor/VideoEditor/App/MCPServer.swift` — modify listener setup, connection handler, and CORS response construction.

### Verification

- Confirm connections from 127.0.0.1 succeed.
- Confirm connections from other IPs are rejected (test with `curl --interface` or from another device).
- Confirm CORS preflight from `http://evil.com` is rejected.
- Confirm eval harness and Claude Code skills still work (they connect from localhost).

## 2. CI Baseline

### Problem

No automated build or test validation. Regressions are caught manually. Future collaborators have no way to validate their changes.

### Design

**GitHub Actions workflow** (`.github/workflows/ci.yml`) triggered on PRs and pushes to `main`.

**Steps:**
1. `macos-latest` runner
2. Install XcodeGen and ffmpeg via Homebrew
3. Cache SwiftPM packages + DerivedData, keyed on `Package.swift` + `project.yml` hashes
4. `xcodegen generate`
5. `xcodebuild -scheme VideoEditor -destination 'platform=macOS' build`
6. `swift test --package-path Packages/EditorCore`
7. `python3 -m pip install -r Tools/requirements.txt`
8. `python3 -m unittest discover -s Tools/tests -p "test_*.py"`

**AIServices tests:** Skip in CI — they depend on API keys and WhisperKit model downloads. Can add later with mocked providers.

**PR gating:** Start as informational (not required). Promote to required after 2 weeks of stability.

**Estimated cost:** ~10-15 min/run at ~$0.08/min = ~$1/run.

### Reproducibility (bundled)

- **Commit `Package.resolved`:** Remove from `.gitignore`. Run `swift package resolve`, commit the file. Ensures identical dependency versions across machines and CI.
- **Python requirements:** See Section 5.

### Files

- `.github/workflows/ci.yml` (new)
- `.gitignore` (remove `Package.resolved` line)

### Verification

- Push a PR, confirm workflow runs and passes.
- Confirm cache hit on second run (faster build).
- Break a test intentionally, confirm CI catches it.

## 3. Release Pipeline

### Problem

No way to produce signed, notarized builds. macOS Gatekeeper blocks unsigned apps. Distribution requires manual steps that are error-prone and not repeatable.

### Design

**GitHub Actions workflow** (`.github/workflows/release.yml`) triggered on tags matching `v*`.

**Steps:**
1. Run full CI (build + tests) as prerequisite
2. Import signing certificate from GitHub Secrets into a temporary keychain
3. `xcodegen generate`
4. `xcodebuild archive -scheme VideoEditor -archivePath build/VideoEditor.xcarchive`
5. Export with Developer ID signing: `xcodebuild -exportArchive` with an export options plist
6. Notarize: `xcrun notarytool submit` with Apple ID credentials from secrets, wait for completion
7. Staple: `xcrun stapler staple VideoEditor.app`
8. Package: Create DMG using `hdiutil`
9. Publish: Create GitHub Release with DMG attached, auto-generated changelog from commits since last tag

**GitHub Secrets required:**
| Secret | Purpose |
|--------|---------|
| `APPLE_DEVELOPER_ID_CERT_BASE64` | Base64-encoded .p12 certificate |
| `APPLE_DEVELOPER_ID_CERT_PASSWORD` | Certificate password |
| `APPLE_ID` | Apple ID email for notarytool |
| `APPLE_ID_APP_PASSWORD` | App-specific password for notarytool |
| `APPLE_TEAM_ID` | Developer team identifier |

**Export options plist** (`release/ExportOptions.plist`):
- Method: `developer-id`
- Signing style: manual
- Team ID from environment

**What this defers:**
- Mac App Store submission (separate export method, can layer on)
- Sparkle auto-updates (add once release cadence is stable)
- project.yml keeps `CODE_SIGN_IDENTITY: "-"` for local dev; CI overrides via xcodebuild flags

### Files

- `.github/workflows/release.yml` (new)
- `release/ExportOptions.plist` (new)

### Verification

- Create a test tag `v0.0.1-test`, confirm workflow runs end-to-end.
- Download DMG from GitHub Release, open on a clean Mac, confirm Gatekeeper doesn't block.
- Verify notarization: `spctl -a -vvv VideoEditor.app` shows "accepted" with "notarized" source.

## 4. Observability (Sentry)

### Problem

No visibility into crashes, hangs, or performance in production. The eval system tracks test-level metrics but nothing from real usage.

### Design

**Sentry Swift SDK** added as a SwiftPM dependency to the main app target only (EditorCore and AIServices stay dependency-free).

**Initialization:** Call `SentrySDK.start()` on app launch with:
- DSN from `.env` (new key: `SENTRY_DSN`)
- `tracesSampleRate: 0.2` (sample 20% of transactions for performance)
- `enableAutoSessionTracking: true` (release health)
- `attachStacktrace: true`
- Environment: "production" for release builds, "development" for debug

**Performance spans** on critical pipelines:
- **Export:** Wrap the full export flow (encode + write + finalize)
- **Transcription:** Wrap both cloud (Deepgram) and local (WhisperKit) paths
- **MCP tool execution:** Wrap `executeToolCall` — every tool call becomes a span with the tool name as operation
- **Timeline render:** Wrap composition build + render pass

**Implementation:** A single `SentrySetup.swift` file with:
- `configureSentry()` — called from app entry point
- `span(_:operation:)` — lightweight wrapper for creating child spans on the current transaction

**Privacy:**
- Sentry default PII stripping is enabled
- No file paths, project names, or media content
- Sessions are anonymous (no user ID set)
- Device metadata only: macOS version, chip, memory

### Files

- `project.yml` — add Sentry SPM dependency to VideoEditor target
- `VideoEditor/VideoEditor/App/SentrySetup.swift` (new)
- `VideoEditor/VideoEditor/App/VideoEditorApp.swift` — call `configureSentry()` on launch
- `VideoEditor/.env` — add `SENTRY_DSN` key

### Verification

- Trigger a test crash in debug, confirm it appears in Sentry dashboard.
- Run an export, confirm a performance transaction appears with spans.
- Confirm no PII in captured events (inspect in Sentry UI).

## 5. Python Environment + Reproducibility

### Problem

Eval system and Python tools have implicit dependencies (Pillow, OpenCV, numpy, requests). No requirements file means CI and collaborators must guess what to install. `ffmpeg`/`ffprobe` are required but undocumented.

### Design

**`VideoEditor/Tools/requirements.txt`** — Pin all Python dependencies:
```
Pillow>=10.0.0
opencv-python-headless>=4.8.0
numpy>=1.24.0
requests>=2.31.0
youtube-transcript-api>=1.2.0
```

Exact versions to be determined during implementation by checking what's currently installed on the dev machine and what the code actually imports.

**System dependencies in CLAUDE.md** — Add `ffmpeg` to the Prerequisites section:
```
brew install xcodegen ffmpeg
```

**Remove `Package.resolved` from `.gitignore`** — Commit the resolved file so Swift dependency versions are pinned across all environments.

### Files

- `VideoEditor/Tools/requirements.txt` (new)
- `.gitignore` (remove `Package.resolved`)
- `CLAUDE.md` (add `ffmpeg` to prerequisites)

### Verification

- Fresh `pip install -r requirements.txt` in a clean venv, then `python3 -m unittest discover` passes.
- `swift package resolve` produces a `Package.resolved` that matches the committed one.

## Implementation Order

The sections should be implemented in this order, each as a separate PR:

1. **MCP Hardening** — Security fix, highest urgency, zero dependencies on other work
2. **Python requirements + Package.resolved** — Small, unblocks CI
3. **CI Baseline** — Depends on requirements.txt existing for the Python test step
4. **Release Pipeline** — Depends on CI workflow existing (reuses it as prerequisite)
5. **Observability (Sentry)** — Independent but lower urgency; benefits from release pipeline being in place so you can track crash-free rates per version

Each PR should be small and independently mergeable.
