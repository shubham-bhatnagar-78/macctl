# macctl Plan 4 — All 51 Apple App Adapters

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Register all 51 Apple-shipped apps in the BuiltinShortcutRegistry and AdapterRegistry so that any Apple app command resolves in O(1) via compile-time keyboard shortcuts, with no runtime AX menu scanning.

**Architecture:** Single `AppleAppAdapter` struct (not 51 separate files) accepts bundleID/displayName/capabilities as parameters. All 51 instances registered in `AppleAdapterRegistry.swift`. BuiltinShortcutRegistry expanded from 10 to all 51 apps. Daemon registers all adapters at startup.

**Tech Stack:** Swift 6, existing AppAdapter protocol, BuiltinShortcutRegistry, AdapterRegistry.

---

## File Map

```
Sources/MacCtlKit/Adapters/Apple/
  AppleAppAdapter.swift            NEW — generic struct conforming to AppAdapter
  AppleAdapterRegistry.swift       NEW — registers all 51 adapters, one file
  BuiltinShortcutRegistry.swift    EXPAND — add remaining 41 apps

Sources/macctl-daemon/
  main.swift                       MODIFY — call AppleAdapterRegistry.registerAll()

Tests/MacCtlKitTests/
  AppleAdapterRegistryTests.swift  NEW — all 51 adapters registered + shortcuts correct
```

---

## Task 1: AppleAppAdapter generic struct

**Files:**
- Create: `Sources/MacCtlKit/Adapters/Apple/AppleAppAdapter.swift`

- [ ] **Implement AppleAppAdapter.swift**

```swift
// Sources/MacCtlKit/Adapters/Apple/AppleAppAdapter.swift
@preconcurrency import AppKit

/// Generic adapter for any Apple-shipped app.
/// Most Apple apps only need keyboard shortcuts + AX — no custom logic.
/// Apps with special framework paths (EventKit, ContactsKit) can be
/// subclassed or replaced in the registry in Plan 3B.
public actor AppleAppAdapter: AppAdapter {
    public nonisolated let bundleIdentifier: String
    public nonisolated let displayName: String
    public nonisolated let capabilities: AdapterCapabilities

    public nonisolated var builtinShortcuts: [String: KeyCombo]? {
        BuiltinShortcutRegistry.allShortcuts(for: bundleIdentifier)
    }

    public init(
        bundleID: String,
        displayName: String,
        capabilities: AdapterCapabilities = [.keyboard, .accessibility]
    ) {
        self.bundleIdentifier = bundleID
        self.displayName = displayName
        self.capabilities = capabilities
    }

    public func isAvailable() async -> Bool {
        NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == bundleIdentifier }
    }

    public func perform(_ operation: MacOperation) async throws -> OperationResult {
        // Apple adapters declare capabilities; OperationRouter handles actual dispatch.
        throw RPCError(code: 5, message: "Use OperationRouter — AppleAppAdapter.perform not direct-callable")
    }
}
```

- [ ] **Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Adapters/Apple/AppleAppAdapter.swift
git commit -m "feat: add AppleAppAdapter generic struct (all 51 apps share this)"
```

---

## Task 2: Expand BuiltinShortcutRegistry to all 51 apps

**Files:**
- Modify: `Sources/MacCtlKit/Adapters/Apple/BuiltinShortcutRegistry.swift`

- [ ] **Add all remaining 41 apps to the registry dictionary**

Append to the existing `registry` dictionary in `BuiltinShortcutRegistry.swift`. Add after the existing `"com.apple.systempreferences"` entry:

```swift
        // MARK: Reminders
        "com.apple.reminders": [
            "new-reminder": KeyCombo("n", .maskCommand),
            "new-list":     KeyCombo("n", [.maskCommand, .maskAlternate]),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "toggle-done":  KeyCombo(" "),
            "find":         KeyCombo("f", .maskCommand),
            "today":        KeyCombo("t", .maskCommand),
        ],

        // MARK: Contacts
        "com.apple.AddressBook": [
            "new-contact":  KeyCombo("n", .maskCommand),
            "new-group":    KeyCombo("n", [.maskCommand, .maskShift]),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
            "edit":         KeyCombo("l", .maskCommand),
        ],

        // MARK: Photos
        "com.apple.Photos": [
            "new-album":    KeyCombo("n", .maskCommand),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "duplicate":    KeyCombo("d", .maskCommand),
            "get-info":     KeyCombo("i", .maskCommand),
            "export":       KeyCombo("e", [.maskCommand, .maskShift]),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Music
        "com.apple.Music": [
            "play-pause":   KeyCombo(" "),
            "next":         KeyCombo("\u{F703}", .maskCommand),
            "previous":     KeyCombo("\u{F702}", .maskCommand),
            "vol-up":       KeyCombo("\u{F700}", .maskCommand),
            "vol-down":     KeyCombo("\u{F701}", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
            "add-library":  KeyCombo("d", .maskCommand),
            "show-library": KeyCombo("l", .maskCommand),
        ],

        // MARK: TV
        "com.apple.TV": [
            "play-pause":   KeyCombo(" "),
            "find":         KeyCombo("f", .maskCommand),
            "next-chapter": KeyCombo("\u{F703}", .maskCommand),
            "prev-chapter": KeyCombo("\u{F702}", .maskCommand),
        ],

        // MARK: Podcasts
        "com.apple.podcasts": [
            "play-pause":   KeyCombo(" "),
            "find":         KeyCombo("f", .maskCommand),
            "refresh":      KeyCombo("r", .maskCommand),
        ],

        // MARK: Books
        "com.apple.iBooksX": [
            "find":         KeyCombo("f", .maskCommand),
            "new-window":   KeyCombo("n", .maskCommand),
        ],

        // MARK: Messages
        "com.apple.MobileSMS": [
            "new-message":  KeyCombo("n", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "archive":      KeyCombo("a", [.maskCommand, .maskControl]),
        ],

        // MARK: FaceTime
        "com.apple.FaceTime": [
            "new-call":     KeyCombo("n", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Maps
        "com.apple.Maps": [
            "find":         KeyCombo("f", .maskCommand),
            "directions":   KeyCombo("d", .maskCommand),
        ],

        // MARK: News
        "com.apple.News": [
            "find":         KeyCombo("f", .maskCommand),
            "reload":       KeyCombo("r", .maskCommand),
        ],

        // MARK: Stocks
        "com.apple.Stocks": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Home
        "com.apple.Home": [
            "new-home":     KeyCombo("n", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Voice Memos
        "com.apple.VoiceMemos": [
            "record":       KeyCombo("r", .maskCommand),
            "play-pause":   KeyCombo(" "),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
        ],

        // MARK: Weather
        "com.apple.weather": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Clock
        "com.apple.clock": [
            "new-alarm":    KeyCombo("n", .maskCommand),
        ],

        // MARK: Freeform
        "com.apple.Freeform": [
            "new-board":    KeyCombo("n", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
            "zoom-in":      KeyCombo("=", .maskCommand),
            "zoom-out":     KeyCombo("-", .maskCommand),
        ],

        // MARK: Shortcuts
        "com.apple.shortcuts": [
            "new":          KeyCombo("n", .maskCommand),
            "run":          KeyCombo("r", .maskCommand),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
        ],

        // MARK: App Store
        "com.apple.AppStore": [
            "find":         KeyCombo("f", .maskCommand),
            "reload":       KeyCombo("r", .maskCommand),
        ],

        // MARK: Calculator
        "com.apple.Calculator": [
            "basic":        KeyCombo("1", .maskCommand),
            "scientific":   KeyCombo("2", .maskCommand),
            "programmer":   KeyCombo("3", .maskCommand),
            "clear":        KeyCombo("a", .maskCommand),
            "clear-entry":  KeyCombo("e", .maskCommand),
        ],

        // MARK: Preview
        "com.apple.Preview": [
            "new":          KeyCombo("n", .maskCommand),
            "open":         KeyCombo("o", .maskCommand),
            "save":         KeyCombo("s", .maskCommand),
            "save-as":      KeyCombo("s", [.maskCommand, .maskShift]),
            "find":         KeyCombo("f", .maskCommand),
            "zoom-in":      KeyCombo("=", .maskCommand),
            "zoom-out":     KeyCombo("-", .maskCommand),
            "actual-size":  KeyCombo("0", .maskCommand),
        ],

        // MARK: QuickTime Player
        "com.apple.QuickTimePlayerX": [
            "new-movie":    KeyCombo("n", .maskCommand),
            "new-screen":   KeyCombo("n", [.maskCommand, .maskControl]),
            "play-pause":   KeyCombo(" "),
            "open":         KeyCombo("o", .maskCommand),
            "save":         KeyCombo("s", .maskCommand),
            "trim":         KeyCombo("t", .maskCommand),
        ],

        // MARK: Stickies
        "com.apple.Stickies": [
            "new-note":     KeyCombo("n", .maskCommand),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "float":        KeyCombo("f", [.maskCommand, .maskShift]),
            "collapse":     KeyCombo("m", .maskCommand),
        ],

        // MARK: Font Book
        "com.apple.FontBook": [
            "add":          KeyCombo("o", .maskCommand),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "validate":     KeyCombo("v", [.maskCommand, .maskShift]),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Dictionary
        "com.apple.Dictionary": [
            "find":         KeyCombo("f", .maskCommand),
            "new-window":   KeyCombo("n", .maskCommand),
        ],

        // MARK: Pages
        "com.apple.iWork.Pages": [
            "new":          KeyCombo("n", .maskCommand),
            "open":         KeyCombo("o", .maskCommand),
            "save":         KeyCombo("s", .maskCommand),
            "bold":         KeyCombo("b", .maskCommand),
            "italic":       KeyCombo("i", .maskCommand),
            "underline":    KeyCombo("u", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
            "insert-link":  KeyCombo("k", .maskCommand),
            "zoom-in":      KeyCombo("=", .maskCommand),
            "zoom-out":     KeyCombo("-", .maskCommand),
        ],

        // MARK: Numbers
        "com.apple.iWork.Numbers": [
            "new":          KeyCombo("n", .maskCommand),
            "save":         KeyCombo("s", .maskCommand),
            "bold":         KeyCombo("b", .maskCommand),
            "italic":       KeyCombo("i", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
            "zoom-in":      KeyCombo("=", .maskCommand),
            "zoom-out":     KeyCombo("-", .maskCommand),
        ],

        // MARK: Keynote
        "com.apple.iWork.Keynote": [
            "new":          KeyCombo("n", .maskCommand),
            "save":         KeyCombo("s", .maskCommand),
            "play":         KeyCombo("p", .maskCommand),
            "bold":         KeyCombo("b", .maskCommand),
            "italic":       KeyCombo("i", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
            "zoom-in":      KeyCombo("=", .maskCommand),
            "zoom-out":     KeyCombo("-", .maskCommand),
        ],

        // MARK: Activity Monitor
        "com.apple.ActivityMonitor": [
            "find":         KeyCombo("f", .maskCommand),
            "quit-process": KeyCombo("q", .maskCommand),
            "inspect":      KeyCombo(" "),
        ],

        // MARK: Console
        "com.apple.Console": [
            "find":         KeyCombo("f", .maskCommand),
            "clear":        KeyCombo("k", .maskCommand),
            "reload":       KeyCombo("r", .maskCommand),
        ],

        // MARK: Disk Utility
        "com.apple.DiskUtility": [
            "new-image":    KeyCombo("n", .maskCommand),
            "get-info":     KeyCombo("i", .maskCommand),
            "eject":        KeyCombo("e", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Script Editor
        "com.apple.ScriptEditor2": [
            "new":          KeyCombo("n", .maskCommand),
            "run":          KeyCombo("r", .maskCommand),
            "compile":      KeyCombo("k", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Automator
        "com.apple.Automator": [
            "new":          KeyCombo("n", .maskCommand),
            "run":          KeyCombo("r", .maskCommand),
            "stop":         KeyCombo(".", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Image Capture
        "com.apple.Image_Capture": [
            "import-all":   KeyCombo("i", [.maskCommand, .maskShift]),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Digital Color Meter
        "com.apple.DigitalColorMeter": [
            "lock":         KeyCombo("l", .maskCommand),
            "copy-as-text": KeyCombo("c", [.maskCommand, .maskShift]),
        ],

        // MARK: Keychain Access
        "com.apple.keychainaccess": [
            "find":         KeyCombo("f", .maskCommand),
            "new-password": KeyCombo("n", .maskCommand),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "lock-all":     KeyCombo("l", .maskCommand),
        ],

        // MARK: Audio MIDI Setup
        "com.apple.audio.AudioMIDISetup": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Photo Booth
        "com.apple.Photo-Booth": [
            "take-photo":   KeyCombo("\r"),
            "effects":      KeyCombo("e", .maskCommand),
        ],

        // MARK: Find My
        "com.apple.findmy": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: iMovie
        "com.apple.iMovieApp": [
            "play-pause":   KeyCombo(" "),
            "in-point":     KeyCombo("i", []),
            "out-point":    KeyCombo("o", []),
            "export":       KeyCombo("e", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: GarageBand
        "com.apple.GarageBand": [
            "play-pause":   KeyCombo(" "),
            "record":       KeyCombo("r", []),
            "undo":         KeyCombo("z", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Migration Assistant
        "com.apple.MigrationAssistant": [:],  // no useful shortcuts

        // MARK: System Information
        "com.apple.SystemProfiler": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Screen Sharing
        "com.apple.ScreenSharing": [
            "fullscreen":   KeyCombo("f", [.maskCommand, .maskControl]),
            "screenshot":   KeyCombo("3", [.maskCommand, .maskShift]),
        ],

        // MARK: AirPort Utility
        "com.apple.AirPortUtility": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Wireless Diagnostics
        "com.apple.WirelessDiagnostics": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Directory Utility
        "com.apple.DirectoryUtility": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: ColorSync Utility
        "com.apple.ColorSyncUtility": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Bluetooth File Exchange
        "com.apple.BluetoothFileExchange": [
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: iPhone Mirroring (macOS 15+)
        "com.apple.ScreenContinuity": [
            "connect":      KeyCombo("k", [.maskCommand, .maskShift]),
            "fullscreen":   KeyCombo("f", [.maskCommand, .maskControl]),
            "actual-size":  KeyCombo("0", .maskCommand),
        ],
```

> **Note:** This replaces the closing `]` of the registry dictionary. The existing 10 apps (Finder through System Settings) remain at the top. These 41 new apps go between the last existing entry and the closing `]` of the `registry` constant.

- [ ] **Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Adapters/Apple/BuiltinShortcutRegistry.swift
git commit -m "feat: expand BuiltinShortcutRegistry to all 51 Apple apps"
```

---

## Task 3: AppleAdapterRegistry — register all 51 adapters

**Files:**
- Create: `Sources/MacCtlKit/Adapters/Apple/AppleAdapterRegistry.swift`
- Modify: `Sources/macctl-daemon/main.swift`

- [ ] **Implement AppleAdapterRegistry.swift**

```swift
// Sources/MacCtlKit/Adapters/Apple/AppleAdapterRegistry.swift
import Foundation

/// Registers all 51 Apple-shipped app adapters in one call.
/// Each adapter is an AppleAppAdapter instance with the correct bundleID + capabilities.
public enum AppleAdapterRegistry {
    /// Call once at daemon startup — O(51) registrations, ~2ms total.
    public static func registerAll() async {
        let registry = await AdapterRegistry.shared

        // Helper: register with default [.keyboard, .accessibility] capabilities
        func reg(_ id: String, _ name: String,
                 _ caps: AdapterCapabilities = [.keyboard, .accessibility]) async {
            await registry.register(AppleAppAdapter(bundleID: id, displayName: name, capabilities: caps))
        }
        // Helper: apps that also have Scripting Bridge support
        func regSB(_ id: String, _ name: String) async {
            await reg(id, name, [.keyboard, .accessibility, .scriptingBridge])
        }
        // Helper: apps that use framework APIs (EventKit, ContactsKit, etc.)
        func regFW(_ id: String, _ name: String) async {
            await reg(id, name, [.keyboard, .accessibility, .frameworkAPI])
        }

        // System apps
        await reg("com.apple.finder",              "Finder")
        await reg("com.apple.systempreferences",   "System Settings")
        await reg("com.apple.AppStore",            "App Store")
        await reg("com.apple.Calculator",          "Calculator")
        await reg("com.apple.Dictionary",          "Dictionary")
        await reg("com.apple.FontBook",            "Font Book")
        await reg("com.apple.Preview",             "Preview")
        await reg("com.apple.QuickTimePlayerX",    "QuickTime Player")
        await reg("com.apple.Stickies",            "Stickies")
        await reg("com.apple.TextEdit",            "TextEdit")
        await reg("com.apple.clock",               "Clock")
        await reg("com.apple.weather",             "Weather")

        // Developer tools
        await reg("com.apple.Terminal",            "Terminal")
        await reg("com.apple.dt.Xcode",            "Xcode")
        await regSB("com.apple.ScriptEditor2",     "Script Editor")
        await regSB("com.apple.Automator",         "Automator")
        await reg("com.apple.ActivityMonitor",     "Activity Monitor")
        await reg("com.apple.Console",             "Console")
        await reg("com.apple.DiskUtility",         "Disk Utility")
        await reg("com.apple.audio.AudioMIDISetup","Audio MIDI Setup")
        await reg("com.apple.ColorSyncUtility",    "ColorSync Utility")
        await reg("com.apple.DirectoryUtility",    "Directory Utility")
        await reg("com.apple.AirPortUtility",      "AirPort Utility")
        await reg("com.apple.WirelessDiagnostics", "Wireless Diagnostics")
        await reg("com.apple.keychainaccess",      "Keychain Access")
        await reg("com.apple.DigitalColorMeter",   "Digital Color Meter")
        await reg("com.apple.Image_Capture",       "Image Capture")
        await reg("com.apple.MigrationAssistant",  "Migration Assistant")
        await reg("com.apple.SystemProfiler",      "System Information")
        await reg("com.apple.BluetoothFileExchange","Bluetooth File Exchange")
        await reg("com.apple.ScreenSharing",       "Screen Sharing")

        // Apple productivity + iWork
        await regSB("com.apple.Safari",            "Safari")
        await regSB("com.apple.mail",              "Mail")
        await regSB("com.apple.Notes",             "Notes")
        await regFW("com.apple.iCal",              "Calendar")
        await regFW("com.apple.reminders",         "Reminders")
        await regFW("com.apple.AddressBook",       "Contacts")
        await regSB("com.apple.finder",            "Finder")  // Scripting Bridge + AX
        await reg("com.apple.iWork.Pages",         "Pages")
        await reg("com.apple.iWork.Numbers",       "Numbers")
        await reg("com.apple.iWork.Keynote",       "Keynote")

        // Communication + media
        await regSB("com.apple.MobileSMS",         "Messages")
        await reg("com.apple.FaceTime",            "FaceTime")
        await regFW("com.apple.Photos",            "Photos")
        await reg("com.apple.Music",               "Music")
        await reg("com.apple.TV",                  "TV")
        await reg("com.apple.podcasts",            "Podcasts")
        await reg("com.apple.iBooksX",             "Books")
        await reg("com.apple.News",                "News")
        await reg("com.apple.Stocks",              "Stocks")
        await reg("com.apple.Home",                "Home")
        await reg("com.apple.Maps",                "Maps")
        await reg("com.apple.VoiceMemos",          "Voice Memos")
        await reg("com.apple.Freeform",            "Freeform")
        await reg("com.apple.shortcuts",           "Shortcuts")

        // Creative + misc
        await reg("com.apple.iMovieApp",           "iMovie")
        await reg("com.apple.GarageBand",          "GarageBand")
        await reg("com.apple.Photo-Booth",         "Photo Booth")
        await reg("com.apple.findmy",              "Find My")
        await reg("com.apple.ScreenContinuity",    "iPhone Mirroring")
    }
}
```

- [ ] **Wire into daemon main.swift**

In `Sources/macctl-daemon/main.swift`, add after `await daemonLifecycle.start()`:

```swift
// Register all 51 Apple app adapters (O(51), ~2ms)
await AppleAdapterRegistry.registerAll()
```

- [ ] **Build to verify**

```bash
swift build --product macctl-daemon 2>&1 | grep -E "error:|complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Adapters/Apple/AppleAdapterRegistry.swift Sources/macctl-daemon/main.swift
git commit -m "feat: add AppleAdapterRegistry, register all 51 Apple apps at daemon startup"
```

---

## Task 4: Tests

**Files:**
- Create: `Tests/MacCtlKitTests/AppleAdapterRegistryTests.swift`

- [ ] **Write tests**

```swift
// Tests/MacCtlKitTests/AppleAdapterRegistryTests.swift
import Testing
@testable import MacCtlKit

@Suite("AppleAdapterRegistry")
struct AppleAdapterRegistryTests {
    @Test func registryHas51AppleApps() async throws {
        await AppleAdapterRegistry.registerAll()
        let ids = await AdapterRegistry.shared.allBundleIDs()
        // At minimum the 51 Apple apps should be registered
        // (may be more if GenericAdapter was also registered)
        #expect(ids.count >= 51)
    }

    @Test func finderAdapterRegistered() async throws {
        await AppleAdapterRegistry.registerAll()
        let adapter = await AdapterRegistry.shared.adapter(for: "com.apple.finder")
        #expect(adapter != nil)
        #expect(adapter?.bundleIdentifier == "com.apple.finder")
    }

    @Test func safariHasKeyboardCapability() async throws {
        await AppleAdapterRegistry.registerAll()
        let adapter = await AdapterRegistry.shared.adapter(for: "com.apple.Safari")
        #expect(adapter?.capabilities.contains(.keyboard) == true)
    }

    @Test func calendarHasFrameworkAPICapability() async throws {
        await AppleAdapterRegistry.registerAll()
        let adapter = await AdapterRegistry.shared.adapter(for: "com.apple.iCal")
        #expect(adapter?.capabilities.contains(.frameworkAPI) == true)
    }

    @Test func mailHasScriptingBridgeCapability() async throws {
        await AppleAdapterRegistry.registerAll()
        let adapter = await AdapterRegistry.shared.adapter(for: "com.apple.mail")
        #expect(adapter?.capabilities.contains(.scriptingBridge) == true)
    }

    @Test func unknownAppReturnsNilFromRegistry() async throws {
        let adapter = await AdapterRegistry.shared.adapter(for: "com.unknown.NotReal")
        #expect(adapter == nil)
    }

    @Test func shortcutRegistryCoversAllRegisteredApps() async throws {
        await AppleAdapterRegistry.registerAll()
        let allIDs = await AdapterRegistry.shared.allBundleIDs()
        // Every registered Apple app should have either shortcuts or empty map (not nil)
        // Apps with no useful shortcuts (MigrationAssistant) return empty dict, not nil
        var appsWithShortcuts = 0
        for id in allIDs where id.hasPrefix("com.apple.") {
            if let shortcuts = BuiltinShortcutRegistry.allShortcuts(for: id),
               !shortcuts.isEmpty {
                appsWithShortcuts += 1
            }
        }
        // At least 45 of the 51 apps should have at least one shortcut
        #expect(appsWithShortcuts >= 45)
    }

    @Test func safariNewTabShortcut() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "new-tab", app: "com.apple.Safari")
        #expect(combo?.key == "t")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func xcodeRunShortcut() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "run", app: "com.apple.dt.Xcode")
        #expect(combo?.key == "r")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func calendarTodayShortcut() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "today", app: "com.apple.iCal")
        #expect(combo?.key == "t")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func remindersNewReminderShortcut() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "new-reminder", app: "com.apple.reminders")
        #expect(combo?.key == "n")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func iMoviePlayPauseShortcut() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "play-pause", app: "com.apple.iMovieApp")
        #expect(combo?.key == " ")
        #expect(combo?.modifiers == [])
    }
}
```

- [ ] **Run tests**

```bash
swift test --filter AppleAdapterRegistryTests 2>&1 | grep -E "passed|failed" | head -15
```
Expected: All 12 tests passed.

- [ ] **Run full test suite**

```bash
swift test 2>&1 | grep "Suite 'All tests'"
```
Expected: passed.

- [ ] **Commit**

```bash
git add Tests/MacCtlKitTests/AppleAdapterRegistryTests.swift
git commit -m "test: add AppleAdapterRegistry tests — 12 tests covering all 51 apps + shortcuts"
```

---

## Task 5: Smoke test + adapter lookup benchmark

- [ ] **Start daemon and verify adapters registered**

```bash
.build/debug/macctl-daemon &
DPID=$!
sleep 1.5
```

```bash
# Query via shell command — daemon lists registered adapters internally
# Verify key workflows still work (adapters shouldn't break existing commands)
.build/debug/macctl key save --app com.apple.TextEdit 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('key save:', d['success'], 'layer:', d.get('meta',{}).get('layer','?'))"
.build/debug/macctl app list 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('app list:', d['success'], 'count:', d['data']['count'])"
kill $DPID
```

Expected:
```
key save: True layer: keyboard-builtin
app list: True count: <N>
```

- [ ] **Benchmark adapter registry lookup**

```python
import subprocess, json, time

def run(args):
    r = subprocess.run(['.build/debug/macctl'] + args, capture_output=True, text=True, timeout=5)
    try: return json.loads(r.stdout)
    except: return {"success": False}

# Start daemon
import subprocess as sp
d = sp.Popen(['.build/debug/macctl-daemon'], stdout=sp.DEVNULL, stderr=sp.DEVNULL)
time.sleep(1.5)

# Benchmark key command for 10 different Apple apps
# All should hit keyboard-builtin (O(1) registry lookup)
apps = [
    ("save", "com.apple.TextEdit"),
    ("new-tab", "com.apple.Safari"),
    ("new-note", "com.apple.Notes"),
    ("find", "com.apple.Preview"),
    ("build", "com.apple.dt.Xcode"),
    ("new-event", "com.apple.iCal"),
    ("new-message", "com.apple.mail"),
    ("play-pause", "com.apple.Music"),
    ("find", "com.apple.Calculator"),
    ("new-reminder", "com.apple.reminders"),
]

print("Keyboard shortcut lookup for all Apple apps (target <3ms):")
for action, app in apps:
    times = []
    for _ in range(8):
        r = run(['key', action, '--app', app])
        t = r.get('meta',{}).get('durationMs',-1)
        if t > 0: times.append(t)
    if times:
        times.sort()
        p50 = times[int(len(times)*0.5)]
        lyr = run(['key', action, '--app', app]).get('meta',{}).get('layer','?')
        ok = p50 <= 3
        print(f"  {'✅' if ok else '⚠️'} {app.split('.')[-1]:<20} {action:<18} P50={p50:.1f}ms [{lyr}]")

d.terminate()
```

Expected: all P50 < 3ms, all layer = keyboard-builtin (for apps that have the shortcut).

- [ ] **Commit**

```bash
git add -A
git commit -m "feat: Plan 4 complete — all 51 Apple app adapters registered, O(1) shortcut lookup verified"
```

---

## Self-Review

| Spec requirement | Task | Status |
|---|---|---|
| 51 Apple app adapters | Tasks 1+3 | ✅ |
| BuiltinShortcutRegistry all 51 apps | Task 2 | ✅ |
| AppleAppAdapter generic struct | Task 1 | ✅ |
| AdapterRegistry.registerAll() | Task 3 | ✅ |
| Daemon registers at startup | Task 3 | ✅ |
| Tests (12) | Task 4 | ✅ |
| Benchmark | Task 5 | ✅ |
| Scripting Bridge capability declared | Task 3 | ✅ |
| Framework API capability declared | Task 3 | ✅ |
| iPhone Mirroring adapter | Task 2+3 | ✅ |
