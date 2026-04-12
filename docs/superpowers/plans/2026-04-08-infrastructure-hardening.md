# Infrastructure Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the VideoEditor's infrastructure across 5 areas: MCP security, Python reproducibility, CI, release pipeline, and observability.

**Architecture:** Five independent PRs in dependency order. MCP hardening is a security fix to the existing server. Python/reproducibility is a small prep step. CI and release are new GitHub Actions workflows. Observability adds Sentry SDK to the app target.

**Tech Stack:** Swift 6.0, Network framework (NWListener), GitHub Actions, XcodeGen, Sentry Swift SDK, Python 3, xcodebuild, notarytool

**Spec:** `docs/superpowers/specs/2026-04-08-infrastructure-hardening-design.md`

---

## Task 1: MCP Server — Loopback-Only Binding

**Files:**
- Modify: `VideoEditor/VideoEditor/App/MCPServer.swift:22-45` (start method)

- [ ] **Step 1: Add loopback-only connection guard to `handleNewConnection`**

In `MCPServer.swift`, add a helper method that checks if a connection's remote endpoint is loopback. Insert this right after the `stop()` method (~line 51):

```swift
// MARK: - Security

/// Returns true if the remote endpoint is a loopback address (127.0.0.1 or ::1).
private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
    switch endpoint {
    case .hostPort(let host, _):
        switch host {
        case .ipv4(let addr):
            return addr == IPv4Address.loopback
        case .ipv6(let addr):
            return addr == IPv6Address.loopback
        default:
            return false
        }
    default:
        return false
    }
}
```

- [ ] **Step 2: Guard connections in `handleNewConnection`**

At the top of `handleNewConnection` (line 54), before `connection.start(...)`, add the loopback check:

```swift
private func handleNewConnection(_ connection: NWConnection) {
    // Reject non-loopback connections
    if let remote = connection.currentPath?.remoteEndpoint, !isLoopback(remote) {
        print("[MCP] Rejected non-loopback connection from \(remote)")
        connection.cancel()
        return
    }

    connection.start(queue: .global(qos: .utility))
    // ... rest of existing code unchanged
```

Note: `connection.currentPath` may be nil before the connection is started. As a belt-and-suspenders approach, also add a check after `connection.start`:

```swift
private func handleNewConnection(_ connection: NWConnection) {
    connection.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        if case .ready = state {
            if let remote = connection.currentPath?.remoteEndpoint, !self.isLoopback(remote) {
                print("[MCP] Rejected non-loopback connection from \(remote)")
                connection.cancel()
                return
            }
        }
    }

    connection.start(queue: .global(qos: .utility))
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
        // ... existing receive code unchanged
```

- [ ] **Step 3: Build and verify**

Run:
```bash
cd VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```
Expected: Build succeeds.

- [ ] **Step 4: Manual test — loopback connection works**

Launch the app, then:
```bash
curl -s -X POST http://127.0.0.1:8420 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```
Expected: JSON response with tools array.

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/VideoEditor/App/MCPServer.swift
git commit -m "security(mcp): reject non-loopback connections"
```

---

## Task 2: MCP Server — Restrictive CORS

**Files:**
- Modify: `VideoEditor/VideoEditor/App/MCPServer.swift:68-91` (connection handling, CORS headers)

- [ ] **Step 1: Add Origin validation helper**

Add this method below the `isLoopback` method:

```swift
/// Returns true if the Origin header value is from a loopback address.
private func isAllowedOrigin(_ origin: String) -> Bool {
    let allowed = ["http://127.0.0.1", "http://localhost", "http://[::1]"]
    return allowed.contains(where: { origin.hasPrefix($0) })
}

/// Returns the CORS origin header value for the given request headers.
/// Returns the request's Origin if allowed, otherwise nil.
private func corsOrigin(from headers: String) -> String? {
    let lines = headers.components(separatedBy: "\r\n")
    for line in lines {
        let lower = line.lowercased()
        if lower.hasPrefix("origin:") {
            let origin = line.dropFirst("origin:".count).trimmingCharacters(in: .whitespaces)
            return isAllowedOrigin(origin) ? origin : nil
        }
    }
    // No Origin header — non-browser request (curl, etc.). Allow.
    return ""
}
```

- [ ] **Step 2: Update CORS preflight response**

Replace the OPTIONS handler block (around line 73-77):

```swift
// CORS preflight
if headers.hasPrefix("OPTIONS") {
    let origin = corsOrigin(from: headers)
    if origin == nil {
        // Disallowed origin — reject preflight
        let response = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
        return
    }
    var corsHeader = ""
    if !origin!.isEmpty {
        corsHeader = "Access-Control-Allow-Origin: \(origin!)\r\nVary: Origin\r\n"
    }
    let response = "HTTP/1.1 200 OK\r\n\(corsHeader)Access-Control-Allow-Methods: POST\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: 0\r\n\r\n"
    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
    return
}
```

- [ ] **Step 3: Update normal response CORS header**

Replace the httpResponse construction (around line 89):

```swift
let origin = self.corsOrigin(from: headers)
var corsHeader = ""
if let origin, !origin.isEmpty {
    corsHeader = "Access-Control-Allow-Origin: \(origin)\r\nVary: Origin\r\n"
}
let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\(corsHeader)Content-Length: \(responseJSON.utf8.count)\r\n\r\n\(responseJSON)"
```

- [ ] **Step 4: Build and verify**

Run:
```bash
cd VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```
Expected: Build succeeds.

- [ ] **Step 5: Manual test — allowed origin works**

```bash
curl -s -X OPTIONS http://127.0.0.1:8420 -H "Origin: http://localhost:3000" -v 2>&1 | grep -i "access-control"
```
Expected: `Access-Control-Allow-Origin: http://localhost:3000`

- [ ] **Step 6: Manual test — disallowed origin rejected**

```bash
curl -s -X OPTIONS http://127.0.0.1:8420 -H "Origin: http://evil.com" -v 2>&1 | grep "403"
```
Expected: `HTTP/1.1 403 Forbidden`

- [ ] **Step 7: Manual test — no Origin header (curl/agents) works**

```bash
curl -s -X POST http://127.0.0.1:8420 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```
Expected: JSON response with tools, no CORS header in response.

- [ ] **Step 8: Commit**

```bash
git add VideoEditor/VideoEditor/App/MCPServer.swift
git commit -m "security(mcp): restrictive CORS — allow only loopback origins"
```

---

## Task 3: Python Requirements + Package.resolved

**Files:**
- Create: `VideoEditor/Tools/requirements.txt`
- Modify: `.gitignore:16` (remove `Package.resolved`)
- Modify: `CLAUDE.md:9` (add ffmpeg to prerequisites)

- [ ] **Step 1: Audit current Python imports to confirm dependency list**

Run:
```bash
cd /Users/tadies/Projects/video-editor && grep -rh "^import \|^from " VideoEditor/Tools/ --include="*.py" | grep -v "^from \." | grep -v "^import \(os\|sys\|json\|re\|pathlib\|typing\|dataclass\|collections\|http\|threading\|unittest\|argparse\|shutil\|uuid\|hashlib\|datetime\|sqlite3\|urllib\|abc\|__future__\|subprocess\|time\|tempfile\|textwrap\|enum\|copy\|functools\|io\|contextlib\|string\|glob\|logging\)" | sort -u
```

Confirm the third-party imports are: `cv2`, `numpy`, `PIL` (Pillow), `requests`, `youtube_transcript_api`.

- [ ] **Step 2: Create requirements.txt**

Create `VideoEditor/Tools/requirements.txt`:

```
Pillow>=10.0.0
opencv-python-headless>=4.8.0
numpy>=1.24.0
requests>=2.31.0
youtube-transcript-api>=1.2.0
```

- [ ] **Step 3: Verify Python tests pass with these deps**

Run:
```bash
cd /Users/tadies/Projects/video-editor/VideoEditor/Tools && python3 -m pip install -r requirements.txt && python3 -m unittest discover -s tests -p "test_*.py"
```
Expected: All 45 tests pass.

- [ ] **Step 4: Remove Package.resolved from .gitignore**

In `.gitignore`, remove the line `Package.resolved` (line 16).

The resulting Swift Package Manager section should be:
```
# Swift Package Manager
.build/
.swiftpm/
```

- [ ] **Step 5: Generate and commit Package.resolved files**

Run:
```bash
cd /Users/tadies/Projects/video-editor/VideoEditor/Packages/EditorCore && swift package resolve
cd /Users/tadies/Projects/video-editor/VideoEditor/Packages/AIServices && swift package resolve
```

Check that `Package.resolved` files now exist:
```bash
ls -la /Users/tadies/Projects/video-editor/VideoEditor/Packages/EditorCore/Package.resolved
ls -la /Users/tadies/Projects/video-editor/VideoEditor/Packages/AIServices/Package.resolved
```

- [ ] **Step 6: Add ffmpeg to CLAUDE.md prerequisites**

Update `CLAUDE.md` line 9, change:
```
XcodeGen must be installed: `brew install xcodegen`
```
to:
```
XcodeGen and ffmpeg must be installed: `brew install xcodegen ffmpeg`
```

- [ ] **Step 7: Commit**

```bash
git add VideoEditor/Tools/requirements.txt .gitignore CLAUDE.md
git add VideoEditor/Packages/EditorCore/Package.resolved VideoEditor/Packages/AIServices/Package.resolved
git commit -m "chore: add Python requirements.txt, commit Package.resolved, document ffmpeg prereq"
```

---

## Task 4: CI Baseline — GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflow directory**

```bash
mkdir -p /Users/tadies/Projects/video-editor/.github/workflows
```

- [ ] **Step 2: Write the CI workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    runs-on: macos-latest
    timeout-minutes: 30

    steps:
      - uses: actions/checkout@v4

      - name: Install tooling
        run: |
          brew install xcodegen ffmpeg

      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData
            ~/.swiftpm
          key: swiftpm-${{ runner.os }}-${{ hashFiles('**/Package.swift', '**/Package.resolved', 'VideoEditor/project.yml') }}
          restore-keys: |
            swiftpm-${{ runner.os }}-

      - name: Generate Xcode project
        working-directory: VideoEditor
        run: xcodegen generate

      - name: Build
        working-directory: VideoEditor
        run: |
          xcodebuild \
            -scheme VideoEditor \
            -destination 'platform=macOS' \
            -derivedDataPath ~/Library/Developer/Xcode/DerivedData \
            build

      - name: Swift package tests (EditorCore)
        working-directory: VideoEditor/Packages/EditorCore
        run: swift test

      - name: Install Python dependencies
        working-directory: VideoEditor/Tools
        run: python3 -m pip install -r requirements.txt

      - name: Python tests
        working-directory: VideoEditor/Tools
        run: python3 -m unittest discover -s tests -p "test_*.py"
```

- [ ] **Step 3: Validate workflow syntax**

Run (if `actionlint` is installed, otherwise skip):
```bash
actionlint /Users/tadies/Projects/video-editor/.github/workflows/ci.yml
```

Or validate YAML parses:
```bash
python3 -c "import yaml; yaml.safe_load(open('/Users/tadies/Projects/video-editor/.github/workflows/ci.yml'))" 2>&1 || echo "pyyaml not installed, skip"
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow for build + test"
```

---

## Task 5: Release Pipeline — GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `release/ExportOptions.plist`

- [ ] **Step 1: Create the export options plist**

```bash
mkdir -p /Users/tadies/Projects/video-editor/release
```

Create `release/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>teamID</key>
    <string>$(APPLE_TEAM_ID)</string>
</dict>
</plist>
```

Note: The `$(APPLE_TEAM_ID)` placeholder will be replaced at build time by the workflow using `sed` before invoking `xcodebuild -exportArchive`.

- [ ] **Step 2: Write the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags: ['v*']

jobs:
  ci:
    uses: ./.github/workflows/ci.yml

  release:
    needs: ci
    runs-on: macos-latest
    timeout-minutes: 60
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4

      - name: Install tooling
        run: brew install xcodegen create-dmg

      - name: Import signing certificate
        env:
          CERT_BASE64: ${{ secrets.APPLE_DEVELOPER_ID_CERT_BASE64 }}
          CERT_PASSWORD: ${{ secrets.APPLE_DEVELOPER_ID_CERT_PASSWORD }}
        run: |
          CERT_PATH=$RUNNER_TEMP/certificate.p12
          KEYCHAIN_PATH=$RUNNER_TEMP/build.keychain-db
          KEYCHAIN_PASSWORD=$(openssl rand -base64 32)

          echo -n "$CERT_BASE64" | base64 --decode -o "$CERT_PATH"

          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security import "$CERT_PATH" -P "$CERT_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
          security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

      - name: Generate Xcode project
        working-directory: VideoEditor
        run: xcodegen generate

      - name: Archive
        working-directory: VideoEditor
        run: |
          xcodebuild archive \
            -scheme VideoEditor \
            -destination 'platform=macOS' \
            -archivePath $RUNNER_TEMP/VideoEditor.xcarchive \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            DEVELOPMENT_TEAM=${{ secrets.APPLE_TEAM_ID }} \
            CODE_SIGN_STYLE=Manual \
            OTHER_CODE_SIGN_FLAGS="--keychain $RUNNER_TEMP/build.keychain-db"

      - name: Prepare export options
        run: |
          sed "s/\$(APPLE_TEAM_ID)/${{ secrets.APPLE_TEAM_ID }}/g" \
            release/ExportOptions.plist > $RUNNER_TEMP/ExportOptions.plist

      - name: Export
        run: |
          xcodebuild -exportArchive \
            -archivePath $RUNNER_TEMP/VideoEditor.xcarchive \
            -exportOptionsPlist $RUNNER_TEMP/ExportOptions.plist \
            -exportPath $RUNNER_TEMP/export

      - name: Notarize
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_ID_APP_PASSWORD: ${{ secrets.APPLE_ID_APP_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          # Create zip for notarization
          ditto -c -k --keepParent \
            "$RUNNER_TEMP/export/VideoEditor.app" \
            "$RUNNER_TEMP/VideoEditor-notarize.zip"

          # Submit for notarization
          xcrun notarytool submit \
            "$RUNNER_TEMP/VideoEditor-notarize.zip" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_ID_APP_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait

          # Staple
          xcrun stapler staple "$RUNNER_TEMP/export/VideoEditor.app"

      - name: Create DMG
        run: |
          create-dmg \
            --volname "VideoEditor" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "VideoEditor.app" 150 190 \
            --app-drop-link 450 190 \
            "$RUNNER_TEMP/VideoEditor-${{ github.ref_name }}.dmg" \
            "$RUNNER_TEMP/export/VideoEditor.app" \
          || true
          # Fallback to hdiutil if create-dmg fails
          if [ ! -f "$RUNNER_TEMP/VideoEditor-${{ github.ref_name }}.dmg" ]; then
            hdiutil create \
              -volname "VideoEditor" \
              -srcfolder "$RUNNER_TEMP/export/VideoEditor.app" \
              -ov \
              "$RUNNER_TEMP/VideoEditor-${{ github.ref_name }}.dmg"
          fi

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: ${{ runner.temp }}/VideoEditor-${{ github.ref_name }}.dmg
          generate_release_notes: true
          draft: true
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml release/ExportOptions.plist
git commit -m "ci: add release pipeline — sign, notarize, DMG, GitHub Release"
```

- [ ] **Step 4: Document required secrets**

The user must add these secrets to their GitHub repository settings (Settings > Secrets and variables > Actions):

| Secret | How to get it |
|--------|--------------|
| `APPLE_DEVELOPER_ID_CERT_BASE64` | Export "Developer ID Application" cert from Keychain as .p12, then `base64 -i cert.p12` |
| `APPLE_DEVELOPER_ID_CERT_PASSWORD` | Password used when exporting the .p12 |
| `APPLE_ID` | Apple ID email |
| `APPLE_ID_APP_PASSWORD` | Generate at appleid.apple.com > App-Specific Passwords |
| `APPLE_TEAM_ID` | Found in Apple Developer portal > Membership |

---

## Task 6: Observability — Add Sentry SDK Dependency

**Files:**
- Modify: `VideoEditor/project.yml` (add Sentry package)

- [ ] **Step 1: Add Sentry SPM package to project.yml**

Add to the `packages:` section (after AIServices):

```yaml
packages:
  EditorCore:
    path: Packages/EditorCore
  AIServices:
    path: Packages/AIServices
  Sentry:
    url: https://github.com/getsentry/sentry-cocoa
    from: "8.0.0"
```

Add Sentry to the VideoEditor target dependencies:

```yaml
    dependencies:
      - package: EditorCore
      - package: AIServices
      - package: Sentry
        product: Sentry
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
cd VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```
Expected: Build succeeds with Sentry resolved and linked.

- [ ] **Step 3: Commit Package.resolved update**

The build will update `Package.resolved` with Sentry's resolved version.

```bash
git add VideoEditor/project.yml VideoEditor/Packages/*/Package.resolved
git commit -m "deps: add Sentry Swift SDK"
```

---

## Task 7: Observability — Sentry Initialization

**Files:**
- Create: `VideoEditor/VideoEditor/App/SentrySetup.swift`
- Modify: `VideoEditor/VideoEditor/App/VideoEditorApp.swift:6-9`

- [ ] **Step 1: Create SentrySetup.swift**

Create `VideoEditor/VideoEditor/App/SentrySetup.swift`:

```swift
import Foundation
import Sentry

enum SentrySetup {
    static func configure() {
        guard let dsn = ProcessInfo.processInfo.environment["SENTRY_DSN"] ??
              EnvironmentLoader.shared.value(forKey: "SENTRY_DSN"),
              !dsn.isEmpty else {
            print("[Sentry] No DSN configured, skipping initialization")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.tracesSampleRate = 0.2
            options.enableAutoSessionTracking = true
            options.attachStacktrace = true

            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif

            // Privacy: no PII collection
            options.sendDefaultPii = false
        }
    }
}
```

Note: `EnvironmentLoader` is the existing helper used by the app to read `.env` files. Check that it exists by searching for it. If the app uses a different mechanism to load env vars, adapt accordingly.

- [ ] **Step 2: Verify EnvironmentLoader exists**

Run:
```bash
grep -r "EnvironmentLoader" /Users/tadies/Projects/video-editor/VideoEditor/VideoEditor/ --include="*.swift" -l
```

If it doesn't exist, use only `ProcessInfo.processInfo.environment["SENTRY_DSN"]` and document that `SENTRY_DSN` must be set as a system environment variable or in the Xcode scheme.

- [ ] **Step 3: Call configure on app launch**

In `VideoEditorApp.swift`, add the import and init call. Modify the struct:

```swift
import SwiftUI
import AppKit
import Combine
import Sentry

@main
struct VideoEditorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()

    init() {
        SentrySetup.configure()
    }

    var body: some Scene {
        // ... existing code unchanged
```

- [ ] **Step 4: Build and verify**

Run:
```bash
cd VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/VideoEditor/App/SentrySetup.swift VideoEditor/VideoEditor/App/VideoEditorApp.swift
git commit -m "feat(observability): initialize Sentry on app launch"
```

---

## Task 8: Observability — Performance Spans

**Files:**
- Modify: `VideoEditor/VideoEditor/App/SentrySetup.swift` (add span helper)
- Modify: `VideoEditor/VideoEditor/App/MCPServer.swift:556-562` (wrap executeToolCall)

- [ ] **Step 1: Add span helper to SentrySetup**

Append to `SentrySetup.swift`:

```swift
extension SentrySetup {
    /// Run a block inside a Sentry performance span.
    /// If there's an active transaction, creates a child span. Otherwise creates a new transaction.
    @discardableResult
    static func span<T>(_ operation: String, description: String, body: () async throws -> T) async rethrows -> T {
        let parentSpan = SentrySDK.span
        let span: Span
        if let parentSpan {
            span = parentSpan.startChild(operation: operation, description: description)
        } else {
            span = SentrySDK.startTransaction(name: description, operation: operation)
        }

        do {
            let result = try await body()
            span.finish(status: .ok)
            return result
        } catch {
            span.finish(status: .internalError)
            throw error
        }
    }
}
```

- [ ] **Step 2: Wrap MCP tool execution with a span**

In `MCPServer.swift`, find the `executeToolForAgent` method (~line 558):

```swift
func executeToolForAgent(name: String, arguments: [String: Any]) async -> String {
    guard let appState else { return "Error: Editor not available" }
    return await executeToolCall(name: name, arguments: arguments, appState: appState)
}
```

And the `tools/call` handler (~line 532):

```swift
let result = await executeToolCall(name: toolName, arguments: arguments, appState: appState)
```

Wrap both call sites. For `executeToolForAgent`:

```swift
func executeToolForAgent(name: String, arguments: [String: Any]) async -> String {
    guard let appState else { return "Error: Editor not available" }
    return await SentrySetup.span("mcp.tool", description: name) {
        await executeToolCall(name: name, arguments: arguments, appState: appState)
    }
}
```

For the `tools/call` handler:

```swift
let result = await SentrySetup.span("mcp.tool", description: toolName) {
    await self.executeToolCall(name: toolName, arguments: arguments, appState: appState)
}
```

Add `import Sentry` at the top of `MCPServer.swift` if not already present.

- [ ] **Step 3: Build and verify**

Run:
```bash
cd VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add VideoEditor/VideoEditor/App/SentrySetup.swift VideoEditor/VideoEditor/App/MCPServer.swift
git commit -m "feat(observability): add Sentry performance spans for MCP tool calls"
```

---

## Task 9: Observability — Document SENTRY_DSN

**Files:**
- Modify: `CLAUDE.md` (note SENTRY_DSN in env section)

`.env` is gitignored (`.gitignore` has `.env*`), so we can't commit it. Instead, document the new key.

- [ ] **Step 1: Add SENTRY_DSN to local .env**

Manually append to `VideoEditor/.env` (this file is gitignored, won't be committed):
```
SENTRY_DSN=
```

The user fills in the actual DSN after creating a Sentry project at sentry.io.

- [ ] **Step 2: Document in CLAUDE.md**

In `CLAUDE.md`, update the Environment Variables section from:
```
API keys go in `VideoEditor/.env`. Check that file for what's needed.
```
to:
```
API keys go in `VideoEditor/.env`. Check `.env.example` for what's needed. Sentry DSN also goes here (`SENTRY_DSN`).
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note SENTRY_DSN in CLAUDE.md"
```

---

## Task 10: Final Verification

- [ ] **Step 1: Full build**

```bash
cd VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```
Expected: Clean build succeeds.

- [ ] **Step 2: Swift tests**

```bash
cd VideoEditor/Packages/EditorCore && swift test
```
Expected: All 5 tests pass.

- [ ] **Step 3: Python tests**

```bash
cd VideoEditor/Tools && python3 -m unittest discover -s tests -p "test_*.py"
```
Expected: All 45 tests pass.

- [ ] **Step 4: Manual MCP test — loopback works**

Launch app, then:
```bash
curl -s http://127.0.0.1:8420 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```
Expected: Tools list returned.

- [ ] **Step 5: Manual MCP test — CORS rejected**

```bash
curl -s -X OPTIONS http://127.0.0.1:8420 -H "Origin: http://evil.com" -w "%{http_code}" -o /dev/null
```
Expected: `403`

- [ ] **Step 6: Verify CI workflow file is valid YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('OK')"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('OK')"
```
Expected: Both print `OK`.
