# macctl — Design Spec
**Date:** 2026-06-04  
**Status:** Approved for implementation

---

## 1. Vision

Ultra-fast, ultra-reliable macOS automation CLI. Sub-5ms for most operations. 95%+ reliability across all 51 Apple-shipped apps and any third-party app. Built for agentic LLM use (MCP + raw socket) and standalone use.

100X improvement over Peekaboo: daemon architecture eliminates 80-150ms per-invocation startup, keyboard-first resolution, three-layer operation routing, direct framework APIs instead of AX-only.

---

## 2. Design Decisions

| Decision | Choice | Reason |
|---|---|---|
| Execution model | Daemon + thin CLI | Sub-5ms round-trip vs 80-150ms process spawn |
| Language | Swift 6 (strict concurrency) | Required for AX, SCK, IOKit; actor model prevents races |
| Distribution | Homebrew + direct binary (notarized) | Full API access, no sandbox restrictions |
| Wire protocol | JSON-RPC 2.0 over Unix socket | Language-agnostic, typed, versioned |
| LLM interface | MCP server + raw socket | MCP for Claude/Cursor/Codex; socket for Python/Node/Rust |
| Scope v1 | Tier 1 (deep UI) + Tier 2 (system state) | File ops, 51 Apple apps, system APIs |
| Browser automation | v2 slot via BrowserCapable protocol | Protocol defined v1, implemented v2 |
| macOS minimum | macOS 13 (Ventura) | ScreenCaptureKit, Stage Manager, URL scheme panes |

---

## 3. Architecture Overview

### Three binaries, one Swift package

```
macctl/
├── MacCtlKit/          ← Swift library (embeddable, zero IPC for Swift callers)
├── macctl-daemon/      ← persistent background process, Unix socket server
├── macctl/             ← thin CLI binary (parse args → RPC → socket → print JSON)
└── macctl-mcp/         ← MCP server binary (MCP stdio → RPC → socket)
```

### Execution paths

```
[MacCtlKit]    ──── in-process (0 IPC overhead) ────────▶ [daemon actors]
[macctl CLI]   ──── Unix socket JSON-RPC (~0.5ms IPC) ──▶ │
[macctl-mcp]   ──── Unix socket JSON-RPC (~0.5ms IPC) ──▶ │
[Python SDK]   ──── Unix socket JSON-RPC (~0.5ms IPC) ──▶ │
[Any language] ──── Unix socket JSON-RPC (~0.5ms IPC) ──▶ │
```

### Actor model

Each subsystem is a Swift 6 actor. No shared mutable state. Concurrent requests to different actors run in parallel; concurrent requests to same actor are serialized (preventing AX race conditions).

```
macctl-daemon owns:
  AXActor                 ← Accessibility API, element tree, AXObserver pool
  InputActor              ← CGEvent synthesis (click, type, scroll, drag)
  CaptureActor            ← ScreenCaptureKit warm session
  KeyboardActor           ← CGEvent key post, builtin + user-override shortcuts
  ScriptingBridgeActor    ← SBApplication pool (compiled once, reused), AppleScript
  SystemStateActor        ← CoreAudio, CoreWLAN, IOBluetooth, IOKit, AVAudio
  AppLifecycleActor       ← open/quit/hide/show, bundle URL cache, running index
  WindowActor             ← list/move/resize/tile/fullscreen/spaces, Stage Manager
  ClipboardActor          ← NSPasteboard: text/image/file/RTF/HTML/color, watch
  FileActor               ← POSIX + iCloud + Finder + FSEvents + NSFileCoordinator
  SystemDataActor         ← EventKit/ContactsKit/PhotosKit/MailKit
  PowerActor              ← IOPMAssertion, sleep/lock/display-sleep, App Nap prevention
  ScreenActor             ← brightness/resolution/arrangement, Retina-aware
  ProcessActor            ← all processes (not just apps), memory/CPU, Rosetta detection
  ShellActor              ← arbitrary shell execution, streaming output
  ShareActor              ← NSSharingService direct (no UI)
  NetworkActor            ← NWPathMonitor, DNS, interface enumeration
  DefaultsActor           ← NSUserDefaults read/write per domain
  NotificationCenterActor ← UNUserNotificationCenter: list/dismiss/post/stream
  SpotlightActor          ← NSMetadataQuery search + keyboard open
  InputSourceActor        ← TISInputSource switching
  PermissionMonitor       ← TCC watch, revocation detection, FD limit bootstrap
  DaemonLifecycle         ← App Nap prevention, activity token
```

---

## 4. Operation Router — Three-Layer Resolution

Every operation tries layers in order, stops at first success. Layer used is reported in response metadata.

```
Layer 0: BuiltinShortcutRegistry   0ms      99.9%  compile-time Apple app shortcuts
Layer 1: Direct native API         0.1-2ms  99.9%  CoreAudio/CoreWLAN/IOKit/EventKit
Layer 2: Runtime-discovered shortcut 0.1ms  98%    AX menu scan cache (third-party)
Layer 3: AX setValue / action      1-5ms    97%    text fields, toggles, sliders
Layer 4: Scripting Bridge          5-15ms   97%    scriptable system apps
Layer 5: AX find → click           5-20ms   95%    generic UI elements
Layer 6: Visual coordinate         50ms+    85%    last resort, non-AX apps
```

### System Settings: URL scheme (not navigation)

```swift
// Direct pane open — 50-100ms, 99% reliable
NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
// NOT: keyboard nav → click pane → wait for animation (300-600ms, 95%)
```

Full pane URL map versioned per macOS 13/14/15/future in `SystemSettingsPaneMap.swift`.

---

## 5. Keyboard-First Strategy

### Builtin shortcut registry (51 Apple apps, compile-time)

All Apple-shipped app shortcuts are hardcoded. Zero runtime lookup cost. 99.9% reliable.

Selected examples:
```
Finder:  new-window=Cmd+N, move-to-trash=Cmd+Delete, quick-look=Space, go-back=Cmd+[
Safari:  focus-addressbar=Cmd+L, new-tab=Cmd+T, reload=Cmd+R, back=Cmd+[
Notes:   new-note=Cmd+N, bold=Cmd+B, checklist=Cmd+Shift+L
Calendar: new-event=Cmd+N, today=Cmd+T, view-week=Cmd+2
Mail:    new-message=Cmd+N, reply=Cmd+R, send=Cmd+Shift+D, trash=Cmd+Delete
Terminal: new-tab=Cmd+T, clear=Cmd+K, split=Cmd+D
Xcode:   build=Cmd+B, run=Cmd+R, test=Cmd+U, open-quickly=Cmd+Shift+O
```

### User override merging

At daemon start, read `NSUserKeyEquivalents` from GlobalPreferences + per-app plists. Merge with builtin map (user overrides win). Localized menu title ↔ action name mapping via one-time AX scan.

### Smart text input routing

```
Text input decision:
  settable AX text field?  → AX setValue (1-2ms, any length)
  text > 20 chars?         → paste via clipboard (3-5ms)
  short text, no AX?       → CGEvent sequence (last resort)
```
Result: 200-char input = 2ms (not 2000ms via keystrokes).

---

## 6. Reliability Mechanisms

### SnapshotCache — AXObserver-driven invalidation

No TTL. Snapshots valid until AX notifies of UI change:
- `kAXLayoutChangedNotification` → invalidate app snapshots
- `kAXUIElementDestroyedNotification` → invalidate specific element
- Fires in <1ms from UI change. Zero stale element errors in normal flow.

### ElementResolver — 4-strategy fallback

```
1. Exact element ID (cache hit)         → O(1)
2. AX fingerprint (role+label+position) → O(app tree size)
3. Semantic query (role+label fuzzy)    → O(app tree size)
4. Visual fallback (screenshot + find)  → 50ms+
```

### WaitEngine — zero polling

All waits use AXObserver. No `sleep()` anywhere in codebase.
`waitForElement`, `waitForNavigation`, `waitUntilHittable` all fire on AXObserver callback (<2ms from event).

### AXObserver pool

Max 200 observers (Mach port safe). LRU eviction. Observers shared across operations for same (pid, notification set).

### Per-app operation queue

Serial queue per app. Op2 on Safari waits for Op1's AXObserver completion signal before starting. No sleep-based sequencing.

### Retry engine

Per operation: 2 retries with 50ms/150ms backoff. Per layer: escalate on failure. Logs which layer succeeded.

### Scripting Bridge timeout

Every SBApplication call wrapped in 5s timeout. Prevents deadlock on unsaved-changes dialogs.

### Coordinate space

All internal coordinates in logical points. Retina conversion at API boundary only.
`CoordinateSpace.toLogical(pixelPoint, screen)` — prevents silent 2× coordinate mismatch on Retina displays.

---

## 7. File Operations

### Five tiers

| Tier | API | Latency | Reliability |
|---|---|---|---|
| POSIX/FileManager | Direct syscall | 0.1-2ms | 99.9% |
| iCloud | NSMetadataQuery download wait | 100ms-30s | 99% |
| Finder-mediated | NSWorkspace + xattr direct | 1-30ms | 97% |
| System app data | EventKit/ContactsKit/PhotosKit/MailKit | 2-50ms | 99% |
| File watching | FSEvents (kFSEventStreamCreateFlagNoDefer) + kqueue fallback | <1ms notify | 99.9% |

### Key reliability fixes
- iCloud: check `ubiquitousItemDownloadingStatus` before read, trigger download, wait via NSMetadataQuery
- Shared files: NSFileCoordinator on all writes to system-app-shared locations
- Cross-volume move: copy+verify+delete explicitly (not atomic rename)
- FSEvents: `kFSEventStreamCreateFlagNoDefer` — no coalescing for important events
- Network volumes: kqueue fallback (FSEvents unreliable on SMB/NFS)

---

## 8. System State (Tier 2)

Direct framework APIs — no UI automation needed.

| Operation | API | Latency |
|---|---|---|
| Volume | CoreAudio `kAudioHardwareServiceDeviceProperty_VirtualMasterVolume` | 1ms |
| Brightness | IOKit `IODisplaySetFloatParameter` | 2ms |
| Wi-Fi toggle | CoreWLAN `CWWiFiClient.setNetworkProfile` | 5-15ms |
| Bluetooth | IOBluetooth `IOBluetoothPreferenceSetControllerPowerState` | 5ms |
| Audio device switch | AVAudioEngine / CoreAudio device selection | 2ms |
| Input source | TISInputSource `TISSelectInputSource` | 1ms |
| Screen lock | `SACLockScreenImmediately` (private, stable) | 1ms |
| System sleep | `IOPMSleepSystem` | 10ms |
| Prevent sleep | `IOPMAssertionCreateWithName` | 1ms |
| Focus mode read | `CNFocusStatusCenter` | 1ms |
| Focus mode set | Shortcuts URL scheme bridge | 200-500ms |
| DNS lookup | CFHost | 5-100ms |
| Network status | NWPathMonitor | <1ms |
| NSUserDefaults | Direct per domain | 0.5ms |

---

## 9. Adapter System — Modularity

### AppAdapter protocol

```swift
public protocol AppAdapter: Actor, Sendable {
    var bundleIdentifier: String { get }
    var displayName: String { get }
    var builtinShortcuts: [String: KeyCombo]? { get }
    var capabilities: AdapterCapabilities { get }
    func perform(_ operation: MacOperation) async throws -> OperationResult
    func isAvailable() async -> Bool
}

public struct AdapterCapabilities: OptionSet {
    public static let keyboard        = AdapterCapabilities(rawValue: 1 << 0)
    public static let accessibility   = AdapterCapabilities(rawValue: 1 << 1)
    public static let scriptingBridge = AdapterCapabilities(rawValue: 1 << 2)
    public static let frameworkAPI    = AdapterCapabilities(rawValue: 1 << 3)
    public static let cdp             = AdapterCapabilities(rawValue: 1 << 4)  // v2
    public static let webInspector    = AdapterCapabilities(rawValue: 1 << 5)  // v2
    public static let iosMirroring    = AdapterCapabilities(rawValue: 1 << 6)  // v2
}
```

### Adding any new app = one file

```swift
// Example: adding Slack
actor SlackAdapter: AppAdapter {
    let bundleIdentifier = "com.tinyspeck.slackmacgap"
    let displayName = "Slack"
    var builtinShortcuts: [String: KeyCombo]? {[
        "new-message": KeyCombo("k", .command),
        "new-dm":      KeyCombo("n", [.command, .shift]),
        "search":      KeyCombo("f", [.command, .shift]),
        "next-unread": KeyCombo("j", .option),
    ]}
    var capabilities: AdapterCapabilities { [.keyboard, .accessibility] }
    func perform(_ op: MacOperation) async throws -> OperationResult {
        // keyboard first, AX fallback, GenericAdapter for unknowns
    }
}
// Register: AdapterRegistry.shared.register(SlackAdapter())
// Done. Router, MCP, CLI all work automatically.
```

### AdapterRegistry hot-plug

FSEvents watches `/Applications` and `~/Applications`. New app installed → auto-register `GenericAdapter`. Known bundle ID → register specific adapter. Zero daemon restart needed.

### 51 Apple adapters shipped

```
System apps:   Finder, Safari, Mail, Messages, FaceTime, Calendar, Reminders,
               Notes, Contacts, Maps, Weather, News, Stocks, Home, Clock,
               Freeform, Shortcuts, Photos, Music, TV, Podcasts, Books,
               VoiceMemos, FaceTime

Productivity:  Pages, Numbers, Keynote, TextEdit, Preview, QuickTimePlayer,
               Stickies, Dictionary, FontBook, Calculator, PhotoBooth, FindMy

Developer:     Terminal, Xcode, ScriptEditor, Automator

Utilities:     SystemSettings, AppStore, ActivityMonitor, Console, DiskUtility,
               AudioMIDISetup, ColorSyncUtility, DirectoryUtility, FontBook,
               DigitalColorMeter, KeychainAccess, ImageCapture, Grapher,
               MigrationAssistant, SystemInformation, WirelessDiagnostics,
               BluetoothFileExchange, AirPortUtility, ScreenSharing,
               BootCampAssistant, DVDPlayer

macOS 15:      iPhoneMirroring (iOS automation surface via Continuity)

Creative:      iMovie, GarageBand, RealityComposerPro
```

---

## 10. Wire Protocol

### JSON-RPC 2.0 over Unix domain socket

Socket path: `~/Library/Application Support/macctl/daemon.sock` (per-user, Fast User Switching safe)

### Request

```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "method": "click",
  "params": {
    "app": "com.apple.Safari",
    "query": "Address bar",
    "background": true
  }
}
```

### Response envelope

```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "result": {
    "success": true,
    "data": { "elementId": "E42", "coords": {"x": 400, "y": 44} },
    "meta": {
      "durationMs": 2.3,
      "layer": "keyboard",
      "retries": 0,
      "sessionID": "uuid-abc",
      "daemonVersion": "1.0.0"
    }
  }
}
```

### Error envelope

```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "error": {
    "code": 2,
    "message": "Element 'Submit button' not found in Safari",
    "data": {
      "hint": "Try: macctl see --app Safari to inspect current elements",
      "recoverable": true,
      "errorCode": "elementNotFound"
    }
  }
}
```

### Batch requests

```json
{
  "op": "batch",
  "ops": [
    {"op": "screenshot", "app": "Safari", "resultKey": "snap"},
    {"op": "find-element", "query": "Address bar", "snapshot": "$snap", "resultKey": "elem"},
    {"op": "click", "elementID": "$elem.id"}
  ],
  "failFast": true
}
```

### Streaming subscriptions (NDJSON)

```
Client: {"op":"subscribe","topic":"file-watch","params":{"path":"~/Downloads"},"subID":"s1"}
Daemon: {"subID":"s1","event":"created","path":"~/Downloads/report.pdf","ts":1749043200}
Daemon: {"subID":"s1","event":"modified","path":"~/Downloads/report.pdf","ts":1749043205}
Client: {"op":"unsubscribe","subID":"s1"}
```

Topics: `file-watch`, `app-lifecycle`, `clipboard-watch`, `notification-stream`, `ax-element-watch`, `process-watch`, `screen-change`, `focus-change`, `network-change`

---

## 11. Middleware Pipeline

```swift
OperationRouter pipeline (in order):
  1. LoggingMiddleware       ← operation name, layer, duration, retries
  2. MetricsMiddleware       ← counters, histograms per operation type
  3. RateLimitMiddleware     ← token bucket, 1000 ops/sec default
  4. DryRunMiddleware        ← --dry-run: describe without executing
  5. [user-injectable]       ← testing mocks, custom transforms
  6. base handler            ← actual actor dispatch
```

Adding logging/metrics/rate-limiting/mocking = zero changes to actors.

---

## 12. Daemon Operations

### Install / lifecycle

```bash
macctl install           # writes launchd plist, starts daemon
macctl uninstall         # stops daemon, removes plist
macctl status            # daemon running? version? permissions?
macctl permissions       # check/request all required TCC permissions
macctl upgrade           # graceful drain + binary replace + reconnect
```

### launchd plist

```xml
<key>KeepAlive</key><true/>
<key>RunAtLoad</key><true/>
<key>HardResourceLimits</key>
<dict>
  <key>NumberOfFiles</key><integer>4096</integer>
</dict>
```

Crash → launchd restarts in <1s. Clients detect session ID change → invalidate caches → reconnect → resume.

### Permission bootstrap (first run)

```bash
macctl permissions status    # structured JSON: what's granted, what's missing
macctl permissions request   # opens System Settings to each missing pane
macctl permissions wait      # blocks until all granted
```

---

## 13. CLI Interface

### Output — always JSON

```bash
# Every command outputs MacCtlResponse<T> envelope
macctl click "Save" --app TextEdit
# → {"success":true,"data":{"elementId":"B3"},"meta":{"durationMs":1.8,"layer":"keyboard"}}

macctl screenshot --app Safari
# → {"success":true,"data":{"path":"/tmp/macctl/snap-123.png","width":2560,"height":1600}}

macctl volume --set 0.5
# → {"success":true,"data":{"previous":0.8,"current":0.5},"meta":{"durationMs":1.1,"layer":"native-api"}}
```

### Exit codes

```
0: success
1: operation failed
2: permission denied (TCC)
3: timeout
4: daemon not running
5: invalid arguments
```

### Flags present on all commands

```
--json          force JSON output (default)
--dry-run       describe what would happen, don't execute
--timeout 5s    override default timeout
--retries 2     override retry count
--app <id>      target specific app by bundle ID or name
--background    don't bring app to foreground (default true)
--foreground    force foreground delivery
```

---

## 14. MCP Interface

MCP server (`macctl-mcp`) connects to daemon via same Unix socket. Exposes all daemon operations as MCP tools. Tool names are stable (semver-versioned).

```json
{
  "tools": [
    {"name": "macctl_click", "description": "Click UI element by label or ID"},
    {"name": "macctl_type", "description": "Type text into focused element"},
    {"name": "macctl_screenshot", "description": "Capture screen or app window"},
    {"name": "macctl_see", "description": "Capture and enumerate UI elements with IDs"},
    {"name": "macctl_key", "description": "Send keyboard shortcut"},
    {"name": "macctl_app", "description": "Open, quit, hide, show apps"},
    {"name": "macctl_window", "description": "Move, resize, tile windows"},
    {"name": "macctl_system", "description": "Volume, brightness, WiFi, Bluetooth"},
    {"name": "macctl_file", "description": "File operations with iCloud awareness"},
    {"name": "macctl_clipboard", "description": "Read/write clipboard"},
    {"name": "macctl_shell", "description": "Execute shell commands"},
    {"name": "macctl_batch", "description": "Execute multiple operations atomically"}
  ]
}
```

---

## 15. Honest Latency Tiers

### Tier A — <5ms (LLM agent hot path)

| Operation | Latency |
|---|---|
| Builtin keyboard shortcut | 0.1ms |
| NSUserDefaults read/write | 0.5ms |
| Clipboard read/write | 0.5ms |
| Network status | <1ms |
| App is-running check | 0.1ms |
| Native API (volume/BT/WiFi) | 1-3ms |
| AX setValue (any text length) | 1-2ms |

### Tier B — 5-50ms

| Operation | Latency |
|---|---|
| Share via NSSharingService | 5ms |
| Shell command | 5-20ms |
| Scripting Bridge | 5-15ms |
| App activate (running) | 3-5ms |
| Screenshot (SCK warm) | 16-33ms |
| System Settings pane (URL scheme) | 50-100ms |

### Tier C — 100ms+ (irreducible)

| Operation | Latency | Reason |
|---|---|---|
| App open (cold) | 300ms-2s | macOS app launch |
| Full-screen window focus | 400-600ms | Space transition animation |
| Focus mode set | 200-500ms | Shortcuts bridge |
| iCloud file download | 100ms-30s | Network |

---

## 16. v2 Browser Automation Slot

Protocol defined in v1, implemented in v2. Zero v1 core changes needed.

```swift
public protocol BrowserCapable {
    func navigate(to url: URL) async throws
    func evaluate(js: String) async throws -> JSONValue
    func findElement(css: String) async throws -> BrowserElement
    func click(element: BrowserElement) async throws
    func type(text: String, into: BrowserElement) async throws
    func waitForElement(css: String, timeout: Duration) async throws -> BrowserElement
    func screenshot() async throws -> Data
    func currentURL() async throws -> URL
}

// ChromeAdapter v1: keyboard only
// ChromeAdapter v2: + CDP over WebSocket (chrome://inspect port 9222)
// SafariAdapter v1: keyboard only
// SafariAdapter v2: + Safari Web Inspector protocol
// iPhoneMirroringAdapter v1: AX through Continuity window
```

---

## 17. Testing Strategy

### Unit tests
- Each actor tested in isolation
- Mock AX responses via protocol injection
- All middleware tested independently

### Integration tests
- Daemon start/stop/restart
- Client reconnect after daemon restart (session ID invalidation)
- Permission revocation mid-session

### Reliability tests
- 1000 consecutive click operations on Safari: expect 99%+ success
- Concurrent 10-app automation: no deadlocks, no Mach port exhaustion
- App Nap simulation: operations stay <5ms under battery pressure

### Latency benchmarks
- P50/P95/P99 per operation type
- Regression gate: P95 keyboard op must be <1ms, P95 AX op must be <10ms

---

## 18. Build Structure

```
Package.swift targets:
  MacCtlKit          ← library, no UI, no main
  macctl-daemon      ← executable, depends MacCtlKit
  macctl             ← executable, thin client, depends MacCtlKit (protocol types only)
  macctl-mcp         ← executable, depends MacCtlKit (protocol types only)
  MacCtlKitTests     ← test target

Swift version: 6.0 (strict concurrency)
Platforms: macOS 13+
Dependencies:
  Commander (steipete fork) — CLI argument parsing
  swift-log             — structured logging
  swift-argument-parser — backup arg parsing
  (zero other deps — all functionality via Apple frameworks)
```

---

## 19. Acceptance Criteria

- [ ] `macctl install` completes in <5s, daemon starts, permissions guided
- [ ] `macctl click "Save" --app TextEdit` completes in <5ms (warm)
- [ ] `macctl volume --set 0.5` completes in <3ms
- [ ] `macctl screenshot` completes in <50ms
- [ ] 1000 consecutive ops on 5 different apps: 95%+ success rate
- [ ] Daemon crash → launchd restart → client reconnect → resume: <2s total
- [ ] All 51 Apple app adapters registered and respond to `macctl app list`
- [ ] MCP server recognized by Claude Code, Cursor, Codex
- [ ] Adding new third-party adapter: 1 file, zero other changes
- [ ] `macctl batch` with 10 ops returns single response with all results
- [ ] File watch stream delivers events in <5ms on local APFS volume
