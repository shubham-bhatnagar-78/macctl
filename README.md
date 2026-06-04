# macctl

<div align="center">

**Ultra-fast, ultra-reliable macOS automation CLI**  
Built for agentic LLMs. Works standalone too.

[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square)](LICENSE)
[![MCP](https://img.shields.io/badge/MCP-35%20tools-6366f1?style=flat-square)](https://modelcontextprotocol.io)
[![CLI](https://img.shields.io/badge/CLI-25%20commands-10b981?style=flat-square)]()
[![Actors](https://img.shields.io/badge/Swift%20actors-21-f59e0b?style=flat-square)]()

[**Quick Start**](#quick-start) · [**MCP Setup**](#mcp-server) · [**Commands**](#commands) · [**Architecture**](#architecture)

</div>

---

## What is macctl?

`macctl` is a production-grade macOS automation daemon with sub-5ms latency for most operations. It exposes the full macOS API surface — UI automation, system state, files, apps, windows, processes, calendar, contacts — through a unified CLI and a 35-tool MCP server that any LLM can drive.

```bash
# Click a button in Safari
macctl click "New Tab" --app com.apple.Safari

# Type into any app instantly (0.5ms via AX setValue)
macctl type "Hello, world!" --app com.apple.TextEdit

# Get all running apps
macctl app list

# Watch file changes in real-time
macctl watch file ~/Downloads

# Query calendar events
macctl calendar fetch-events

# Search files with Spotlight
macctl spotlight search "invoice 2024"

# Move a window to left half of screen
macctl window tile-left --id 12345
```

## Feature Parity

| Feature | macctl | Hammerspoon | Peekaboo | cliclick | Keyboard Maestro |
|---|---|---|---|---|---|
| Click / type / key | ✅ | ✅ | ✅ | ✅ | ✅ |
| See UI elements (AX tree) | ✅ | ✅ | ✅ | ❌ | ✅ |
| Screenshot | ✅ | ✅ | ✅ | ❌ | ✅ |
| App launch/quit | ✅ | ✅ | ❌ | ❌ | ✅ |
| Window move/resize/tile | ✅ | ✅ | ❌ | ❌ | ✅ |
| Process list/kill | ✅ | ✅ | ❌ | ❌ | ❌ |
| System volume/brightness/WiFi/BT | ✅ | ✅ | ❌ | ❌ | ✅ |
| Clipboard (all types) | ✅ | ✅ | ❌ | ❌ | ✅ |
| File read/write/move/copy | ✅ | ✅ | ❌ | ❌ | ✅ |
| iCloud Drive (eviction-aware) | ✅ | ❌ | ❌ | ❌ | ❌ |
| File tags (xattr, 0.1ms) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Calendar + Reminders (EventKit) | ✅ | ❌ | ❌ | ❌ | ✅ |
| Contacts (ContactsKit) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Notes (AppleScript) | ✅ | ❌ | ❌ | ❌ | ✅ |
| Spotlight search | ✅ | ✅ | ❌ | ❌ | ✅ |
| NSUserDefaults read/write | ✅ | ✅ | ❌ | ❌ | ❌ |
| Screen lock / caffeinate | ✅ | ✅ | ❌ | ❌ | ✅ |
| Keyboard input source | ✅ | ✅ | ❌ | ❌ | ❌ |
| Live file watching (kqueue) | ✅ | ✅ | ❌ | ❌ | ❌ |
| App lifecycle stream | ✅ | ✅ | ❌ | ❌ | ❌ |
| Shell execution | ✅ | ✅ | ❌ | ❌ | ✅ |
| MCP server (LLM tool use) | ✅ 35 tools | ❌ | ✅ limited | ❌ | ❌ |
| Builtin shortcut registry (59 apps) | ✅ O(1) | ❌ | ❌ | ❌ | ❌ |
| Swift 6 strict concurrency | ✅ | ❌ | ❌ | ❌ | ❌ |
| Open source | ✅ AGPL | ✅ MIT | ✅ MIT | ✅ MIT | ❌ paid |

---

## Performance

### Feature Parity

| Tool | Spawn | Binary | MCP | Calendar/Reminders | Contacts | Files | Streaming | Spotlight |
|---|---|---|---|---|---|---|---|---|
| **macctl** | **6ms** | 52KB | ✅ 35 tools | ✅ | ✅ | ✅ iCloud-aware | ✅ | ✅ |
| Hammerspoon | 10ms | 30MB | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Peekaboo | 146ms | 12MB | ✅ limited | ❌ | ❌ | ❌ | ❌ | ❌ |
| cliclick | 18ms | 200KB | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### MCP Tool Call Latency (persistent process, 20 sequential calls)

| Server | Per call | Reliability |
|---|---|---|
| **macctl-mcp** | **24.6ms** | 20/20 ✅ |

MCP server runs as a persistent process — spawn is one-time. Per-call cost is socket IPC only (~1.5ms after first connect).

### Operation Latency vs Competitors

All times in ms. macctl uses daemon socket IPC; competitors re-spawn per call.

| Operation | macctl | Hammerspoon | Peekaboo | cliclick |
|---|---|---|---|---|
| App list | **0.4** | 18 | 219 | N/A |
| See UI elements | **11** | 18 | 707 | N/A |
| Keyboard shortcut | **2.2** | 18 | N/A | N/A |
| System status | **1.4** | 24 | N/A | N/A |
| Type text | **0.5** | ~18 | N/A | ~18 |
| Screenshot | **60** | ~80 | ~200 | N/A |
| Calendar events | **28** | N/A | N/A | N/A |
| File read/write | **0.1–0.8** | ~5 | N/A | N/A |

---

## Quick Start

### Install

```bash
# Clone and build
git clone https://github.com/YOUR_USERNAME/macctl
cd macctl

# Build Swift daemon (the engine)
swift build -c release --target macctl-daemon

# Build C thin clients (CLI + MCP — ultra-fast spawn)
clang -O2 -o .build/macctl Sources/macctl-c/main.c
clang -O2 -o .build/macctl-mcp Sources/macctl-c/mcp.c

# Install
sudo cp .build/macctl /usr/local/bin/
sudo cp .build/macctl-mcp /usr/local/bin/
sudo cp .build/release/macctl-daemon /usr/local/bin/
```

### Start the daemon

```bash
# Install as launchd service (auto-starts on login)
launchctl load ~/Library/LaunchAgents/com.macctl.daemon.plist

# Or run manually
macctl-daemon &
```

### Grant permissions

First run of UI automation / screenshots will prompt for:
- **Accessibility** — for click, type, see
- **Screen Recording** — for screenshots
- **Contacts / Calendar / Reminders** — for data commands

---

## MCP Server

Wire `macctl-mcp` into any MCP-compatible LLM client. Claude Code, Cursor, Codex, and Gemini CLI are supported out of the box.

### Claude Code

Add to `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "macctl": {
      "command": "/usr/local/bin/macctl-mcp"
    }
  }
}
```

Restart Claude Code. All 35 `macctl_*` tools appear automatically.

### Ollama / Local LLMs

```bash
# Bridge via mcphost
npm install -g @modelcontextprotocol/mcphost
mcphost --model ollama:llama3.3 --mcp-config ~/.mcphost/config.json
```

### Available MCP Tools

| Category | Tools |
|---|---|
| UI Automation | `macctl_click`, `macctl_type`, `macctl_key`, `macctl_see`, `macctl_screenshot`, `macctl_scroll` |
| App Lifecycle | `macctl_app_launch`, `macctl_app_quit`, `macctl_app_list` |
| Shell | `macctl_shell` |
| System State | `macctl_system_status`, `macctl_system_volume` |
| Files | `macctl_file_read`, `macctl_file_write`, `macctl_file_list`, `macctl_file_stat` |
| Clipboard | `macctl_clipboard_read`, `macctl_clipboard_write` |
| Calendar | `macctl_calendar_events`, `macctl_calendar_create` |
| Reminders | `macctl_reminders_list`, `macctl_reminders_create` |
| Contacts | `macctl_contacts_search` |
| Windows | `macctl_window_list`, `macctl_window_set_bounds`, `macctl_window_tile`, `macctl_window_fullscreen` |
| Processes | `macctl_process_list`, `macctl_process_kill` |
| Search | `macctl_spotlight_search` |
| Display | `macctl_screen_list` |
| Input | `macctl_input_source_list`, `macctl_input_source_select` |
| Defaults | `macctl_defaults_read`, `macctl_defaults_write` |
| Notes | `macctl notes list/get/create/append/delete` (CLI only) |

---

## Commands

```
macctl <command> [options]

UI Automation:
  click      Click a UI element by label or element ID
  type       Type text (AX setValue → paste → CGEvent fallback)
  key        Send keyboard shortcut (2.2ms, O(1) builtin registry)
  see        Enumerate interactive UI elements with IDs
  scroll     Scroll in an app window
  drag       Drag between coordinates
  screenshot Capture screen or app window to PNG

App Management:
  app        launch / quit / hide / show / list

Shell:
  shell      Execute shell command via /bin/zsh

System State:
  system     volume / brightness / wifi / bluetooth / status
  power      caffeinate / lock / sleep / status
  clipboard  read / write / clear (text, HTML, files)
  network    status / resolve
  defaults   read / write / delete (NSUserDefaults)
  screen     list displays, set brightness
  input-source  current / list / select keyboard layout

File Operations:
  file       read / write / copy / move / delete / list / stat
             mkdir / tag / reveal / open / resolve-icloud

Data:
  calendar   list-calendars / fetch-events / create-event / delete-event (EventKit)
  reminders  list-lists / fetch / create / complete (EventKit)
  contacts   search / get / create (ContactsKit)
  notes      list / get / find / create / append / delete / folders (AppleScript)

Window Management:
  window     list / move / resize / set-bounds / focus
             minimize / fullscreen / tile-left / tile-right

Process Management:
  process    list (all processes) / kill / is-running
  spotlight  search / find (NSMetadataQuery)

Streaming:
  watch      file <path>   — real-time file change events
             apps          — app launch/quit/activate events

Misc:
  install    Install daemon as launchd service
```

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Clients                           │
│  macctl CLI   macctl-mcp (MCP)   Python/Node SDK   │
└──────────┬──────────────┬───────────────┬──────────┘
           │              │               │
           └──────────────┴───────────────┘
                          │ Unix socket JSON-RPC 2.0
                          ▼
           ┌──────────────────────────────┐
           │        macctl-daemon         │
           │  ┌─────────────────────────┐ │
           │  │   Middleware Pipeline   │ │
           │  │  Logging → DryRun       │ │
           │  └──────────┬──────────────┘ │
           │             │                │
           │  ┌──────────▼──────────────┐ │
           │  │   Operation Router      │ │
           │  │  Keyboard → AX → Paste  │ │
           │  └──────────┬──────────────┘ │
           │             │                │
           │  ┌──────────▼─────────────────────────────────┐
           │  │              Swift 6 Actors                │
           │  │                                            │
           │  │  AXActor     InputActor    KeyboardActor   │
           │  │  WindowActor CaptureActor  SystemStateActor│
           │  │  FileActor   EventKitActor ContactsActor   │
           │  │  ProcessActor SpotlightActor ShellActor    │
           │  │  NetworkActor DefaultsActor PowerActor     │
           │  │  ClipboardActor ScreenActor InputSourceActor│
           │  └────────────────────────────────────────────┘
           └──────────────────────────────┘
```

### Key Design Decisions

**Daemon architecture** — process spawns once at login, all commands are socket IPC (~0.5ms). Eliminates the 80–150ms per-invocation startup cost of tools like Peekaboo.

**Keyboard-first resolution** — 59 Apple apps have compile-time shortcut registries. `macctl key new-tab --app Safari` resolves in O(1) at 2.2ms, no AX scanning needed.

**Three-layer operation routing** — every operation tries the fastest reliable path: (1) BuiltinShortcutRegistry, (2) direct native API (CoreAudio/IOKit/EventKit), (3) AX/CGEvent.

**Swift 6 strict concurrency** — all actors enforce data-race freedom at compile time. No `@unchecked Sendable` except at DispatchQueue bridges for blocking C APIs.

**Real timeouts on blocking AX calls** — `AXUIElementSetAttributeValue` is synchronous IPC. Wrapped with `DispatchSemaphore` (not task groups, which can't cancel synchronous calls) — falls through to paste on timeout.

---

## Apple App Coverage

BuiltinShortcutRegistry covers all 59 Apple-shipped apps. O(1) dictionary lookup, compile-time only, no runtime AX scanning needed.

`Finder` `Safari` `Mail` `Messages` `FaceTime` `Calendar` `Reminders` `Notes` `Contacts` `Maps` `Weather` `News` `Stocks` `Home` `Clock` `Freeform` `Shortcuts` `Photos` `Music` `TV` `Podcasts` `Books` `VoiceMemos` `FaceTime` `Preview` `QuickTime` `TextEdit` `Stickies` `Dictionary` `FontBook` `Calculator` `PhotoBooth` `FindMy` `Terminal` `Xcode` `ScriptEditor` `Automator` `ActivityMonitor` `Console` `DiskUtility` `AudioMIDISetup` `ColorSyncUtility` `DirectoryUtility` `AirPortUtility` `WirelessDiagnostics` `KeychainAccess` `DigitalColorMeter` `ImageCapture` `MigrationAssistant` `SystemInformation` `BluetoothFileExchange` `ScreenSharing` `Pages` `Numbers` `Keynote` `iMovie` `GarageBand` `PhotoBooth` `iPhone Mirroring`

---

## Requirements

- macOS 13.0+ (Ventura)
- Swift 6.0+
- Xcode 15+ or Swift toolchain

---

## Building from Source

```bash
git clone https://github.com/YOUR_USERNAME/macctl
cd macctl

# Swift daemon (the engine — all 21 actors, system APIs)
swift build               # debug
swift build -c release    # release

# C thin clients (CLI 52KB, MCP 68KB — 6ms spawn)
clang -O2 -o .build/macctl Sources/macctl-c/main.c
clang -O2 -o .build/macctl-mcp Sources/macctl-c/mcp.c

# Tests
swift test                # 122 tests
```

### Architecture

```
macctl (C, 52KB)          macctl-mcp (C, 68KB)
     │ Unix socket JSON-RPC       │
     └──────────────┬─────────────┘
                    │
          macctl-daemon (Swift, 4MB)
          21 actors: AX, Input, Keyboard,
          AppLifecycle, System, File, EventKit,
          Contacts, Notes, Window, Process,
          Spotlight, Screen, Clipboard, Network...
```

---

## License

AGPL-3.0 — see [LICENSE](LICENSE).

---

<div align="center">

Built with ❤️ on macOS · Powered by Swift 6 strict concurrency

*If macctl saves you time, consider giving it a ⭐*

</div>
