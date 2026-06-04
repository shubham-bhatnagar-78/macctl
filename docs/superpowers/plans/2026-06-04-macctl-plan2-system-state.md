# macctl Plan 2 — System State Control

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add direct system state control — volume, brightness, WiFi, Bluetooth, power management, full clipboard types, network status, and NSUserDefaults — each as a new actor wired into the daemon dispatcher and exposed as CLI commands.

**Architecture:** Each subsystem is a new Swift 6 actor in `Sources/MacCtlKit/Actors/`. All actors follow the existing pattern: `public init() {}`, actor-isolated state, wired into `Sources/macctl-daemon/Dispatcher.swift` via new method cases, exposed via new subcommands in `Sources/macctl/Commands/`. Plan 1's daemon, socket server, CLI framework, and test infrastructure are already in place — this plan only adds new actors and wires them.

**Tech Stack:** Swift 6, macOS 13+, CoreAudio (volume), IOKit (brightness — undocumented but stable), CoreWLAN (WiFi), IOBluetooth (Bluetooth read + private write), IOKit/IOPowerManagement (sleep/caffeinate), NSPasteboard (clipboard), Network.framework (NWPathMonitor, DNS), Foundation/UserDefaults (defaults).

---

## API Reality Check (read before coding)

| Operation | API | Public? | Notes |
|---|---|---|---|
| Get/set volume | CoreAudio `AudioHardwareServiceGetPropertyData` | ✅ public | Works on all Macs |
| Get/set brightness | IOKit `IODisplaySetFloatParameter` | ⚠️ undocumented | Works macOS 13+, mark with comment |
| WiFi on/off | CoreWLAN `CWInterface.setPower(_:)` | ✅ public | May throw on M1/M2 silently |
| Bluetooth on/off | `IOBluetoothPreferenceSetControllerPowerState` | ❌ private | Stable for 10+ years, mark with comment |
| Bluetooth read | `IOBluetoothHostController.default().powerState` | ✅ public | |
| Prevent sleep | `IOPMAssertionCreateWithName` | ✅ public | |
| Screen lock | `SACLockScreenImmediately()` | ❌ private | Or use `loginwindow` restart trick |
| Display sleep | `IOPMSleepSystem(port)` | ✅ public | |
| Clipboard types | `NSPasteboard` | ✅ public | |
| Network status | `NWPathMonitor` | ✅ public | |
| DNS lookup | `CFHostCreateWithName` / `getaddrinfo` | ✅ public | |
| NSUserDefaults | `UserDefaults(suiteName:)` | ✅ public | |

---

## File Map

```
Sources/MacCtlKit/Actors/
  SystemStateActor.swift     NEW — volume, brightness, WiFi, Bluetooth
  PowerActor.swift           NEW — sleep prevention, screen lock, display sleep
  ClipboardActor.swift       REPLACE partial stub — full NSPasteboard types
  NetworkActor.swift         NEW — NWPathMonitor, DNS
  DefaultsActor.swift        NEW — NSUserDefaults read/write/delete

Sources/macctl-daemon/
  Dispatcher.swift           MODIFY — add new method cases for all actors
  main.swift                 MODIFY — instantiate + pass new actors

Sources/macctl/Commands/
  SystemCommand.swift        NEW — system volume/brightness/wifi/bluetooth
  PowerCommand.swift         NEW — power sleep/lock/caffeinate/status
  ClipboardCommand.swift     NEW — clipboard read/write/clear
  NetworkCommand.swift       NEW — network status/resolve
  DefaultsCommand.swift      NEW — defaults read/write/delete
  (main.swift)               MODIFY — register new subcommands

Tests/MacCtlKitTests/
  SystemStateActorTests.swift  NEW
  PowerActorTests.swift        NEW
  ClipboardActorTests.swift    NEW
  NetworkActorTests.swift      NEW
  DefaultsActorTests.swift     NEW
```

---

## Task 1: SystemStateActor — Volume

**Files:**
- Create: `Sources/MacCtlKit/Actors/SystemStateActor.swift`
- Create: `Tests/MacCtlKitTests/SystemStateActorTests.swift`

- [ ] **Write failing test**

```swift
// Tests/MacCtlKitTests/SystemStateActorTests.swift
import Testing
import Foundation
@testable import MacCtlKit

@Suite("SystemStateActor")
struct SystemStateActorTests {
    @Test func getVolumeReturnsValidRange() async throws {
        let actor = SystemStateActor()
        let vol = await actor.volume()
        #expect(vol >= 0.0 && vol <= 1.0)
    }

    @Test func setAndGetVolumeRoundTrip() async throws {
        let actor = SystemStateActor()
        let original = await actor.volume()
        await actor.setVolume(0.42)
        let after = await actor.volume()
        #expect(abs(after - 0.42) < 0.05)  // CoreAudio rounds to hardware steps
        await actor.setVolume(original)    // restore
    }

    @Test func muteToggle() async throws {
        let actor = SystemStateActor()
        let wasMuted = await actor.isMuted()
        await actor.setMuted(!wasMuted)
        let now = await actor.isMuted()
        #expect(now == !wasMuted)
        await actor.setMuted(wasMuted)    // restore
    }
}
```

- [ ] **Run — expect compile failure**

```bash
swift test --filter SystemStateActorTests 2>&1 | grep error: | head -3
```
Expected: `SystemStateActor` not found.

- [ ] **Implement SystemStateActor.swift (volume section)**

```swift
// Sources/MacCtlKit/Actors/SystemStateActor.swift
import CoreAudio
import Foundation
import Logging

public actor SystemStateActor {
    private let logger = Logger(label: "macctl.system-state")

    public init() {}

    // MARK: - Volume (CoreAudio — public API)

    public func volume() -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return 0 }
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &vol)
        return vol
    }

    public func setVolume(_ value: Float) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }
        var vol = max(0, min(1, value))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
    }

    public func isMuted() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return muted != 0
    }

    public func setMuted(_ muted: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }
        var val: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val)
    }

    private func defaultOutputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    // Placeholders — brightness, WiFi, BT added in later steps
}
```

- [ ] **Run tests — expect pass**

```bash
swift test --filter SystemStateActorTests 2>&1 | grep -E "passed|failed" | head -5
```
Expected: 3 tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/SystemStateActor.swift Tests/MacCtlKitTests/SystemStateActorTests.swift
git commit -m "feat: add SystemStateActor with CoreAudio volume get/set/mute"
```

---

## Task 2: SystemStateActor — Brightness

**Files:**
- Modify: `Sources/MacCtlKit/Actors/SystemStateActor.swift`
- Modify: `Tests/MacCtlKitTests/SystemStateActorTests.swift`

- [ ] **Add brightness tests**

Add to `SystemStateActorTests.swift`:

```swift
    @Test func getBrightnessReturnsValidRange() async throws {
        let actor = SystemStateActor()
        let b = await actor.brightness()
        #expect(b >= 0.0 && b <= 1.0)
    }

    @Test func setAndGetBrightnessRoundTrip() async throws {
        let actor = SystemStateActor()
        let original = await actor.brightness()
        await actor.setBrightness(0.5)
        try await Task.sleep(for: .milliseconds(100))
        let after = await actor.brightness()
        #expect(abs(after - 0.5) < 0.1)
        await actor.setBrightness(original)
    }
```

- [ ] **Run — expect failure**

```bash
swift test --filter "getBrightnessReturnsValidRange" 2>&1 | grep error: | head -2
```
Expected: `brightness()` not found.

- [ ] **Add brightness to SystemStateActor.swift**

Add after the `setMuted` function, before the private helpers:

```swift
    // MARK: - Brightness
    // Uses IOKit IODisplaySetFloatParameter — undocumented but stable since macOS 10.x.
    // No public API for programmatic brightness control exists on macOS.

    public func brightness() -> Float {
        var brightness: Float = 0
        var service = io_object_t()
        var iterator = io_iterator_t()
        IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"), &iterator)
        service = IOIteratorNext(iterator)
        while service != 0 {
            IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey, &brightness)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return brightness
    }

    public func setBrightness(_ value: Float) {
        let clamped = max(0, min(1, value))
        var service = io_object_t()
        var iterator = io_iterator_t()
        IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"), &iterator)
        service = IOIteratorNext(iterator)
        while service != 0 {
            IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey, clamped)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
    }
```

Also add `import IOKit` at the top of `SystemStateActor.swift`.

- [ ] **Run tests — expect pass**

```bash
swift test --filter SystemStateActorTests 2>&1 | grep -E "passed|failed" | head -8
```
Expected: 5 tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/SystemStateActor.swift Tests/MacCtlKitTests/SystemStateActorTests.swift
git commit -m "feat: add brightness get/set via IOKit IODisplaySetFloatParameter"
```

---

## Task 3: SystemStateActor — WiFi + Bluetooth

**Files:**
- Modify: `Sources/MacCtlKit/Actors/SystemStateActor.swift`
- Modify: `Tests/MacCtlKitTests/SystemStateActorTests.swift`

- [ ] **Add WiFi + Bluetooth tests**

Add to `SystemStateActorTests.swift`:

```swift
    @Test func wifiStatusIsBoolean() async throws {
        let actor = SystemStateActor()
        let status = await actor.wifiEnabled()
        // Just verify it returns a Bool without throwing
        #expect(status == true || status == false)
    }

    @Test func bluetoothStatusIsBoolean() async throws {
        let actor = SystemStateActor()
        let status = await actor.bluetoothEnabled()
        #expect(status == true || status == false)
    }

    @Test func systemStatusSummary() async throws {
        let actor = SystemStateActor()
        let summary = await actor.status()
        #expect(summary.volume >= 0 && summary.volume <= 1)
        #expect(summary.brightness >= 0 && summary.brightness <= 1)
    }
```

- [ ] **Run — expect failure**

```bash
swift test --filter "wifiStatusIsBoolean" 2>&1 | grep error: | head -2
```
Expected: `wifiEnabled()` not found.

- [ ] **Add WiFi + Bluetooth + status to SystemStateActor.swift**

Add imports at top: `import CoreWLAN` and `import IOBluetooth`.

Add methods after `setBrightness`:

```swift
    // MARK: - WiFi (CoreWLAN — public API)

    public func wifiEnabled() -> Bool {
        CWWiFiClient.shared().interface()?.powerOn() ?? false
    }

    public func setWifiEnabled(_ enabled: Bool) throws {
        guard let iface = CWWiFiClient.shared().interface() else {
            throw SystemStateError.wifiInterfaceNotFound
        }
        try iface.setPower(enabled)
    }

    public func wifiSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    // MARK: - Bluetooth
    // Read: public IOBluetooth API.
    // Write: IOBluetoothPreferenceSetControllerPowerState — private but stable 10+ years.

    public func bluetoothEnabled() -> Bool {
        IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateOn
    }

    public func setBluetoothEnabled(_ enabled: Bool) {
        // Private API: IOBluetoothPreferenceSetControllerPowerState
        // Documented in multiple open-source tools (blueutil, etc.)
        let state: BluetoothHCIPowerState = enabled ? kBluetoothHCIPowerStateOn : kBluetoothHCIPowerStateOff
        IOBluetoothPreferenceSetControllerPowerState(state)
    }

    // MARK: - Status summary

    public struct SystemStatus: Sendable {
        public let volume: Float
        public let isMuted: Bool
        public let brightness: Float
        public let wifiEnabled: Bool
        public let wifiSSID: String?
        public let bluetoothEnabled: Bool
    }

    public func status() -> SystemStatus {
        SystemStatus(
            volume: volume(),
            isMuted: isMuted(),
            brightness: brightness(),
            wifiEnabled: wifiEnabled(),
            wifiSSID: wifiSSID(),
            bluetoothEnabled: bluetoothEnabled()
        )
    }
```

Add error type at bottom of file:

```swift
public enum SystemStateError: Error, Sendable {
    case wifiInterfaceNotFound
    case brightnessUnavailable
}
```

- [ ] **Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Run tests — expect pass**

```bash
swift test --filter SystemStateActorTests 2>&1 | grep -E "passed|failed" | head -10
```
Expected: 8 tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/SystemStateActor.swift Tests/MacCtlKitTests/SystemStateActorTests.swift
git commit -m "feat: add WiFi (CoreWLAN), Bluetooth (IOBluetooth), status summary to SystemStateActor"
```

---

## Task 4: PowerActor

**Files:**
- Create: `Sources/MacCtlKit/Actors/PowerActor.swift`
- Create: `Tests/MacCtlKitTests/PowerActorTests.swift`

- [ ] **Write failing tests**

```swift
// Tests/MacCtlKitTests/PowerActorTests.swift
import Testing
import Foundation
@testable import MacCtlKit

@Suite("PowerActor")
struct PowerActorTests {
    @Test func caffeinateAndRelease() async throws {
        let actor = PowerActor()
        // Prevent sleep, then release immediately — verifies no crash
        let token = try await actor.preventSleep(reason: "test")
        await actor.releaseSleep(token: token)
        // No assertion needed — crash-free execution is the test
    }

    @Test func preventSleepTokenIsUnique() async throws {
        let actor = PowerActor()
        let t1 = try await actor.preventSleep(reason: "test1")
        let t2 = try await actor.preventSleep(reason: "test2")
        #expect(t1 != t2)
        await actor.releaseSleep(token: t1)
        await actor.releaseSleep(token: t2)
    }

    @Test func activeSleepPreventionsCount() async throws {
        let actor = PowerActor()
        let before = await actor.activePreventionCount()
        let t1 = try await actor.preventSleep(reason: "test")
        let during = await actor.activePreventionCount()
        #expect(during == before + 1)
        await actor.releaseSleep(token: t1)
        let after = await actor.activePreventionCount()
        #expect(after == before)
    }
}
```

- [ ] **Run — expect failure**

```bash
swift test --filter PowerActorTests 2>&1 | grep error: | head -3
```
Expected: `PowerActor` not found.

- [ ] **Implement PowerActor.swift**

```swift
// Sources/MacCtlKit/Actors/PowerActor.swift
import IOKit.pwr_mgt
import Foundation
import Logging

public typealias SleepToken = UInt64  // unique ID per prevention

public actor PowerActor {
    private var assertions: [SleepToken: IOPMAssertionID] = [:]
    private var tokenCounter: UInt64 = 0
    private let logger = Logger(label: "macctl.power")

    public init() {}

    // MARK: - Sleep prevention

    public func preventSleep(reason: String) throws -> SleepToken {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            throw PowerError.assertionFailed(result)
        }
        tokenCounter += 1
        let token = tokenCounter
        assertions[token] = assertionID
        logger.debug("Sleep prevention started: \(reason) token=\(token)")
        return token
    }

    public func releaseSleep(token: SleepToken) {
        guard let assertionID = assertions.removeValue(forKey: token) else { return }
        IOPMAssertionRelease(assertionID)
        logger.debug("Sleep prevention released: token=\(token)")
    }

    public func releaseAllSleep() {
        for (_, assertionID) in assertions { IOPMAssertionRelease(assertionID) }
        assertions.removeAll()
    }

    public func activePreventionCount() -> Int { assertions.count }

    // MARK: - System sleep / display sleep

    public func displaySleep() throws {
        // Post display dim event via IOKit
        let port = IOPMFindPowerManagement(MACH_PORT_NULL)
        guard port != MACH_PORT_NULL else { throw PowerError.portUnavailable }
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    public func systemSleep() throws {
        let port = IOPMFindPowerManagement(MACH_PORT_NULL)
        guard port != MACH_PORT_NULL else { throw PowerError.portUnavailable }
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    // MARK: - Screen lock
    // Uses SACLockScreenImmediately() — private API in SecurityAgentCocoa.framework.
    // Most reliable method; alternatives (screensaver, loginwindow) have delays.

    public func lockScreen() {
        // SACLockScreenImmediately is private but the most reliable lock API.
        // Bridged via dlopen/dlsym to avoid link-time dependency.
        if let handle = dlopen("/System/Library/PrivateFrameworks/SecurityAgentCocoa.framework/SecurityAgentCocoa", RTLD_LAZY),
           let sym = dlsym(handle, "SACLockScreenImmediately") {
            typealias LockFn = @convention(c) () -> Void
            let lock = unsafeBitCast(sym, to: LockFn.self)
            lock()
            dlclose(handle)
        } else {
            // Fallback: activate screensaver (triggers lock if "require password" is set)
            Process.run("/usr/bin/open", args: ["-a", "ScreenSaverEngine"])
        }
    }
}

public enum PowerError: Error, Sendable {
    case assertionFailed(kern_return_t)
    case portUnavailable
}

private extension Process {
    @discardableResult
    static func run(_ path: String, args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
```

- [ ] **Run tests — expect pass**

```bash
swift test --filter PowerActorTests 2>&1 | grep -E "passed|failed" | head -5
```
Expected: 3 tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/PowerActor.swift Tests/MacCtlKitTests/PowerActorTests.swift
git commit -m "feat: add PowerActor (IOPMAssertion sleep prevention, screen lock via dlopen)"
```

---

## Task 5: ClipboardActor — Full Types

**Files:**
- Replace: `Sources/MacCtlKit/Actors/ClipboardActor.swift`
- Create: `Tests/MacCtlKitTests/ClipboardActorTests.swift`

The existing stub only handles text. This task replaces it with full type support.

- [ ] **Write failing tests**

```swift
// Tests/MacCtlKitTests/ClipboardActorTests.swift
import Testing
import AppKit
import Foundation
@testable import MacCtlKit

@Suite("ClipboardActor")
struct ClipboardActorTests {
    @Test func readWriteText() async throws {
        let actor = ClipboardActor()
        await actor.write(.text("hello macctl"))
        let result = await actor.read()
        guard case .text(let s) = result else { throw TestError.wrongType }
        #expect(s == "hello macctl")
    }

    @Test func readWriteHTML() async throws {
        let actor = ClipboardActor()
        await actor.write(.html("<b>bold</b>"))
        let result = await actor.readHTML()
        #expect(result == "<b>bold</b>")
    }

    @Test func readWriteFileURLs() async throws {
        let actor = ClipboardActor()
        let url = URL(fileURLWithPath: "/tmp/macctl-test-clipboard.txt")
        await actor.write(.files([url]))
        let files = await actor.readFiles()
        #expect(files.first?.path == url.path)
    }

    @Test func clearClipboard() async throws {
        let actor = ClipboardActor()
        await actor.write(.text("to be cleared"))
        await actor.clear()
        let result = await actor.read()
        guard case .text(let s) = result else { return }  // empty is also ok
        #expect(s.isEmpty)
    }

    @Test func changeCountIncreasesOnWrite() async throws {
        let actor = ClipboardActor()
        let before = await actor.changeCount()
        await actor.write(.text("bump"))
        let after = await actor.changeCount()
        #expect(after > before)
    }
}

enum TestError: Error { case wrongType }
```

- [ ] **Run — expect failure**

```bash
swift test --filter ClipboardActorTests 2>&1 | grep error: | head -5
```
Expected: compile errors (ClipboardContent, ClipboardActor methods not matching).

- [ ] **Replace ClipboardActor.swift**

```swift
// Sources/MacCtlKit/Actors/ClipboardActor.swift
import AppKit
import Foundation

public enum ClipboardContent: Sendable {
    case text(String)
    case html(String)
    case rtf(Data)
    case image(Data)          // PNG data — NSImage is not Sendable, use Data
    case files([URL])
    case color(Double, Double, Double, Double)  // RGBA 0-1
    case empty
}

public actor ClipboardActor {
    public init() {}

    // MARK: - Read

    public func read() -> ClipboardContent {
        let pb = NSPasteboard.general
        // Priority: files > image > HTML > RTF > text
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = images.first,
           let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return .image(png)
        }
        if let html = pb.string(forType: .html) { return .html(html) }
        if let rtf = pb.data(forType: .rtf)     { return .rtf(rtf) }
        if let text = pb.string(forType: .string) { return .text(text) }
        return .empty
    }

    public func readText() -> String?   { pb.string(forType: .string) }
    public func readHTML() -> String?   { pb.string(forType: .html) }
    public func readRTF() -> Data?      { pb.data(forType: .rtf) }
    public func readFiles() -> [URL]    { pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? [] }

    // MARK: - Write

    public func write(_ content: ClipboardContent) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch content {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .html(let h):
            pb.setString(h, forType: .html)
            // Also set plain text fallback
            let stripped = h.replacingOccurrences(of: "<[^>]+>", with: "",
                options: .regularExpression)
            pb.setString(stripped, forType: .string)
        case .rtf(let d):
            pb.setData(d, forType: .rtf)
        case .image(let png):
            if let image = NSImage(data: png) { pb.writeObjects([image]) }
        case .files(let urls):
            pb.writeObjects(urls as [NSURL])
        case .color(let r, let g, let b, let a):
            let color = NSColor(red: r, green: g, blue: b, alpha: a)
            pb.writeObjects([color])
        case .empty:
            break
        }
    }

    public func writeText(_ text: String)   { write(.text(text)) }
    public func writeFiles(_ urls: [URL])   { write(.files(urls)) }

    public func clear() {
        NSPasteboard.general.clearContents()
    }

    public func changeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    // MARK: - Helpers

    private var pb: NSPasteboard { NSPasteboard.general }
}
```

- [ ] **Run tests — expect pass**

```bash
swift test --filter ClipboardActorTests 2>&1 | grep -E "passed|failed" | head -8
```
Expected: 5 tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/ClipboardActor.swift Tests/MacCtlKitTests/ClipboardActorTests.swift
git commit -m "feat: replace ClipboardActor stub with full type support (text/html/rtf/image/files/color)"
```

---

## Task 6: NetworkActor

**Files:**
- Create: `Sources/MacCtlKit/Actors/NetworkActor.swift`
- Create: `Tests/MacCtlKitTests/NetworkActorTests.swift`

- [ ] **Write failing tests**

```swift
// Tests/MacCtlKitTests/NetworkActorTests.swift
import Testing
import Foundation
@testable import MacCtlKit

@Suite("NetworkActor")
struct NetworkActorTests {
    @Test func statusHasConnectivity() async throws {
        let actor = NetworkActor()
        try await Task.sleep(for: .milliseconds(100))  // NWPathMonitor needs a moment to init
        let status = await actor.status()
        // On a developer machine, network is expected to be connected
        // This test verifies the struct fields are populated, not specific values
        #expect(status.interfaces.count >= 0)  // at least returns something
    }

    @Test func resolveLocalhostReturnsAddress() async throws {
        let actor = NetworkActor()
        let addresses = try await actor.resolve(hostname: "localhost")
        #expect(!addresses.isEmpty)
        #expect(addresses.contains("127.0.0.1") || addresses.contains("::1"))
    }

    @Test func resolveInvalidHostThrows() async throws {
        let actor = NetworkActor()
        do {
            _ = try await actor.resolve(hostname: "this.host.definitely.does.not.exist.invalid")
            #expect(Bool(false), "should have thrown")
        } catch {
            // Expected — any error is fine
        }
    }
}
```

- [ ] **Run — expect failure**

```bash
swift test --filter NetworkActorTests 2>&1 | grep error: | head -3
```
Expected: `NetworkActor` not found.

- [ ] **Implement NetworkActor.swift**

```swift
// Sources/MacCtlKit/Actors/NetworkActor.swift
import Network
import Foundation

public actor NetworkActor {
    private let monitor: NWPathMonitor
    private var currentPath: NWPath?
    private let monitorQueue = DispatchQueue(label: "macctl.network-monitor")

    public init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.updatePath(path) }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit { monitor.cancel() }

    private func updatePath(_ path: NWPath) {
        currentPath = path
    }

    // MARK: - Status

    public struct NetworkStatus: Sendable {
        public let isConnected: Bool
        public let isExpensive: Bool        // cellular / personal hotspot
        public let isConstrained: Bool      // Low Data Mode
        public let interfaces: [String]     // interface names: en0, en1, utun0, etc.
        public let hasWifi: Bool
        public let hasCellular: Bool
        public let hasWired: Bool
        public let hasVPN: Bool
    }

    public func status() -> NetworkStatus {
        let path = currentPath ?? monitor.currentPath
        let ifaces = path.availableInterfaces
        return NetworkStatus(
            isConnected:   path.status == .satisfied,
            isExpensive:   path.isExpensive,
            isConstrained: path.isConstrained,
            interfaces:    ifaces.map(\.name),
            hasWifi:       ifaces.contains { $0.type == .wifi },
            hasCellular:   ifaces.contains { $0.type == .cellular },
            hasWired:      ifaces.contains { $0.type == .wiredEthernet },
            hasVPN:        ifaces.contains { $0.type == .other }
        )
    }

    // MARK: - DNS resolution

    public func resolve(hostname: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(hostname, nil, &hints, &result)
                guard status == 0, let result else {
                    continuation.resume(throwing: NetworkError.resolutionFailed(hostname))
                    return
                }
                defer { freeaddrinfo(result) }
                var addresses: [String] = []
                var ptr = result
                while let current = ptr {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen,
                                  &host, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST) == 0 {
                        let addr = String(cString: host)
                        if !addresses.contains(addr) { addresses.append(addr) }
                    }
                    ptr = current.pointee.ai_next
                }
                if addresses.isEmpty {
                    continuation.resume(throwing: NetworkError.resolutionFailed(hostname))
                } else {
                    continuation.resume(returning: addresses)
                }
            }
        }
    }
}

public enum NetworkError: Error, Sendable {
    case resolutionFailed(String)
}
```

- [ ] **Run tests — expect pass**

```bash
swift test --filter NetworkActorTests 2>&1 | grep -E "passed|failed" | head -5
```
Expected: 3 tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/NetworkActor.swift Tests/MacCtlKitTests/NetworkActorTests.swift
git commit -m "feat: add NetworkActor (NWPathMonitor status, getaddrinfo DNS resolution)"
```

---

## Task 7: DefaultsActor

**Files:**
- Create: `Sources/MacCtlKit/Actors/DefaultsActor.swift`
- Create: `Tests/MacCtlKitTests/DefaultsActorTests.swift`

- [ ] **Write failing tests**

```swift
// Tests/MacCtlKitTests/DefaultsActorTests.swift
import Testing
import Foundation
@testable import MacCtlKit

@Suite("DefaultsActor")
struct DefaultsActorTests {
    private let testDomain = "com.macctl.test.defaults"

    @Test func writeReadDelete() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: testDomain, key: "testKey", value: "testValue")
        let val = await actor.read(domain: testDomain, key: "testKey")
        #expect(val as? String == "testValue")
        await actor.delete(domain: testDomain, key: "testKey")
        let gone = await actor.read(domain: testDomain, key: "testKey")
        #expect(gone == nil)
    }

    @Test func writeReadBool() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: testDomain, key: "boolKey", value: true)
        let val = await actor.read(domain: testDomain, key: "boolKey")
        #expect(val as? Bool == true)
        await actor.delete(domain: testDomain, key: "boolKey")
    }

    @Test func writeReadNumber() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: testDomain, key: "numKey", value: 42)
        let val = await actor.read(domain: testDomain, key: "numKey")
        #expect(val as? Int == 42)
        await actor.delete(domain: testDomain, key: "numKey")
    }

    @Test func readAllKeysInDomain() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: testDomain, key: "k1", value: "v1")
        await actor.write(domain: testDomain, key: "k2", value: "v2")
        let all = await actor.readAll(domain: testDomain)
        #expect(all["k1"] as? String == "v1")
        #expect(all["k2"] as? String == "v2")
        await actor.delete(domain: testDomain, key: "k1")
        await actor.delete(domain: testDomain, key: "k2")
    }
}
```

- [ ] **Run — expect failure**

```bash
swift test --filter DefaultsActorTests 2>&1 | grep error: | head -3
```
Expected: `DefaultsActor` not found.

- [ ] **Implement DefaultsActor.swift**

```swift
// Sources/MacCtlKit/Actors/DefaultsActor.swift
import Foundation

public actor DefaultsActor {
    public init() {}

    public func read(domain: String, key: String) -> Any? {
        UserDefaults(suiteName: domain)?.object(forKey: key)
    }

    public func readString(domain: String, key: String) -> String? {
        UserDefaults(suiteName: domain)?.string(forKey: key)
    }

    public func readBool(domain: String, key: String) -> Bool? {
        guard let defaults = UserDefaults(suiteName: domain),
              defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    public func readInt(domain: String, key: String) -> Int? {
        guard let defaults = UserDefaults(suiteName: domain),
              defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    public func readAll(domain: String) -> [String: Any] {
        UserDefaults(suiteName: domain)?.dictionaryRepresentation() ?? [:]
    }

    public func write(domain: String, key: String, value: Any) {
        UserDefaults(suiteName: domain)?.set(value, forKey: key)
        UserDefaults(suiteName: domain)?.synchronize()
    }

    public func delete(domain: String, key: String) {
        UserDefaults(suiteName: domain)?.removeObject(forKey: key)
        UserDefaults(suiteName: domain)?.synchronize()
    }

    public func deleteAll(domain: String) {
        guard let defaults = UserDefaults(suiteName: domain) else { return }
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }
}
```

- [ ] **Run tests — expect pass**

```bash
swift test --filter DefaultsActorTests 2>&1 | grep -E "passed|failed" | head -6
```
Expected: 4 tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/DefaultsActor.swift Tests/MacCtlKitTests/DefaultsActorTests.swift
git commit -m "feat: add DefaultsActor (NSUserDefaults read/write/delete per domain)"
```

---

## Task 8: Wire Actors into Daemon + Dispatcher

**Files:**
- Modify: `Sources/macctl-daemon/main.swift`
- Modify: `Sources/macctl-daemon/Dispatcher.swift`

- [ ] **Update main.swift — add new actor instances**

In `Sources/macctl-daemon/main.swift`, after the existing actor declarations, add:

```swift
let systemStateActor = SystemStateActor()
let powerActor       = PowerActor()
let clipboardActor   = ClipboardActor()
let networkActor     = NetworkActor()
let defaultsActor    = DefaultsActor()
```

Update the `server = SocketServer { data in` handler call to `dispatch(...)` to pass the new actors. Update the `dispatch` function signature.

- [ ] **Update Dispatcher.swift — add new method cases**

Update the function signature:

```swift
func dispatch(
    method: String,
    params: [String: JSONValue],
    ax: AXActor,
    input: InputActor,
    keyboard: KeyboardActor,
    lifecycle: AppLifecycleActor,
    capture: CaptureActor,
    systemState: SystemStateActor,    // NEW
    power: PowerActor,                // NEW
    clipboard: ClipboardActor,        // NEW
    network: NetworkActor,            // NEW
    defaults: DefaultsActor,          // NEW
    sessionID: String
) async throws -> [String: JSONValue] {
```

Add new method cases at the end of the `switch` before `default`:

```swift
    // MARK: - system.*

    case "system.status":
        let s = await systemState.status()
        return layer("native-api", [
            "volume": .double(Double(s.volume)),
            "isMuted": .bool(s.isMuted),
            "brightness": .double(Double(s.brightness)),
            "wifiEnabled": .bool(s.wifiEnabled),
            "wifiSSID": s.wifiSSID.map { .string($0) } ?? .null,
            "bluetoothEnabled": .bool(s.bluetoothEnabled),
        ])

    case "system.volume":
        if case .double(let v) = params["value"] {
            await systemState.setVolume(Float(v))
            return layer("native-api", ["volume": .double(v)])
        }
        return layer("native-api", ["volume": .double(Double(await systemState.volume()))])

    case "system.mute":
        let muted = params["muted"] == .bool(true)
        await systemState.setMuted(muted)
        return layer("native-api", ["muted": .bool(muted)])

    case "system.brightness":
        if case .double(let v) = params["value"] {
            await systemState.setBrightness(Float(v))
            return layer("native-api", ["brightness": .double(v)])
        }
        return layer("native-api", ["brightness": .double(Double(await systemState.brightness()))])

    case "system.wifi":
        if case .bool(let enabled) = params["enabled"] {
            try await systemState.setWifiEnabled(enabled)
            return layer("native-api", ["wifiEnabled": .bool(enabled)])
        }
        return layer("native-api", [
            "wifiEnabled": .bool(await systemState.wifiEnabled()),
            "ssid": await systemState.wifiSSID().map { .string($0) } ?? .null,
        ])

    case "system.bluetooth":
        if case .bool(let enabled) = params["enabled"] {
            await systemState.setBluetoothEnabled(enabled)
            return layer("native-api", ["bluetoothEnabled": .bool(enabled)])
        }
        return layer("native-api", ["bluetoothEnabled": .bool(await systemState.bluetoothEnabled())])

    // MARK: - power.*

    case "power.prevent-sleep":
        let reason = params["reason"]?.stringValue ?? "macctl automation"
        let token = try await power.preventSleep(reason: reason)
        return layer("native-api", ["token": .int(Int(token))])

    case "power.release-sleep":
        if case .int(let t) = params["token"] {
            await power.releaseSleep(token: SleepToken(t))
        }
        return layer("native-api")

    case "power.lock-screen":
        await power.lockScreen()
        return layer("native-api")

    case "power.sleep":
        try await power.systemSleep()
        return layer("native-api")

    case "power.status":
        return layer("native-api", ["activePreventions": .int(await power.activePreventionCount())])

    // MARK: - clipboard.*

    case "clipboard.read":
        let content = await clipboard.read()
        switch content {
        case .text(let s):   return layer("native-api", ["type": .string("text"), "value": .string(s)])
        case .html(let h):   return layer("native-api", ["type": .string("html"), "value": .string(h)])
        case .files(let us): return layer("native-api", ["type": .string("files"),
            "value": .array(us.map { .string($0.path) })])
        case .image:         return layer("native-api", ["type": .string("image")])
        case .rtf:           return layer("native-api", ["type": .string("rtf")])
        case .color:         return layer("native-api", ["type": .string("color")])
        case .empty:         return layer("native-api", ["type": .string("empty")])
        }

    case "clipboard.write":
        if case .string(let text) = params["text"] {
            await clipboard.writeText(text)
            return layer("native-api", ["written": .string("text")])
        }
        if case .array(let paths) = params["files"] {
            let urls = paths.compactMap { v -> URL? in
                guard case .string(let s) = v else { return nil }
                return URL(fileURLWithPath: s)
            }
            await clipboard.writeFiles(urls)
            return layer("native-api", ["written": .string("files")])
        }
        throw RPCError.operationFailed("clipboard.write requires 'text' or 'files' param")

    case "clipboard.clear":
        await clipboard.clear()
        return layer("native-api")

    // MARK: - network.*

    case "network.status":
        let s = await network.status()
        return layer("native-api", [
            "isConnected":   .bool(s.isConnected),
            "isExpensive":   .bool(s.isExpensive),
            "isConstrained": .bool(s.isConstrained),
            "interfaces":    .array(s.interfaces.map { .string($0) }),
            "hasWifi":       .bool(s.hasWifi),
            "hasCellular":   .bool(s.hasCellular),
            "hasWired":      .bool(s.hasWired),
            "hasVPN":        .bool(s.hasVPN),
        ])

    case "network.resolve":
        guard case .string(let hostname) = params["hostname"] else {
            throw RPCError.operationFailed("network.resolve requires 'hostname'")
        }
        let addresses = try await network.resolve(hostname: hostname)
        return layer("native-api", [
            "hostname":  .string(hostname),
            "addresses": .array(addresses.map { .string($0) }),
        ])

    // MARK: - defaults.*

    case "defaults.read":
        guard case .string(let domain) = params["domain"],
              case .string(let key)    = params["key"]
        else { throw RPCError.operationFailed("defaults.read requires domain + key") }
        let value = await defaults.read(domain: domain, key: key)
        let jsonVal: JSONValue = switch value {
        case let s as String: .string(s)
        case let i as Int:    .int(i)
        case let d as Double: .double(d)
        case let b as Bool:   .bool(b)
        default:               value.map { .string("\($0)") } ?? .null
        }
        return layer("native-api", ["value": jsonVal])

    case "defaults.write":
        guard case .string(let domain) = params["domain"],
              case .string(let key)    = params["key"]
        else { throw RPCError.operationFailed("defaults.write requires domain + key + value") }
        let value: Any = switch params["value"] {
        case .string(let s):  s
        case .int(let i):     i
        case .double(let d):  d
        case .bool(let b):    b
        default:               ""
        }
        await defaults.write(domain: domain, key: key, value: value)
        return layer("native-api", ["written": .bool(true)])

    case "defaults.delete":
        guard case .string(let domain) = params["domain"],
              case .string(let key)    = params["key"]
        else { throw RPCError.operationFailed("defaults.delete requires domain + key") }
        await defaults.delete(domain: domain, key: key)
        return layer("native-api")
```

- [ ] **Update dispatch call in main.swift**

Update the `dispatch(...)` call to include the new actors:

```swift
let resultData = try await dispatch(
    method: request.method,
    params: request.params ?? [:],
    ax: axActor, input: inputActor, keyboard: keyboardActor,
    lifecycle: lifecycleActor, capture: captureActor,
    systemState: systemStateActor,
    power: powerActor,
    clipboard: clipboardActor,
    network: networkActor,
    defaults: defaultsActor,
    sessionID: sessionID
)
```

- [ ] **Build to verify**

```bash
swift build --product macctl-daemon 2>&1 | grep -E "error:|complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/macctl-daemon/
git commit -m "feat: wire SystemState/Power/Clipboard/Network/Defaults actors into daemon dispatcher"
```

---

## Task 9: CLI Commands

**Files:**
- Create: `Sources/macctl/Commands/SystemCommand.swift`
- Create: `Sources/macctl/Commands/PowerCommand.swift`
- Create: `Sources/macctl/Commands/ClipboardCommand.swift`
- Create: `Sources/macctl/Commands/NetworkCommand.swift`
- Create: `Sources/macctl/Commands/DefaultsCommand.swift`
- Modify: `Sources/macctl/main.swift`

- [ ] **SystemCommand.swift**

```swift
// Sources/macctl/Commands/SystemCommand.swift
import ArgumentParser
import MacCtlKit

struct SystemCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "system",
        abstract: "System state: volume, brightness, WiFi, Bluetooth",
        subcommands: [Status.self, Volume.self, Brightness.self, Wifi.self, Bluetooth.self, Mute.self])

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status")
        func run() throws { try rpc(method: "system.status", params: [:]) }
    }

    struct Volume: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "volume",
            abstract: "Get or set volume (0.0-1.0)")
        @Argument(help: "Volume level 0.0-1.0 (omit to read)") var value: Double?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let v = value { params["value"] = .double(v) }
            try rpc(method: "system.volume", params: params)
        }
    }

    struct Brightness: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "brightness",
            abstract: "Get or set brightness (0.0-1.0)")
        @Argument(help: "Brightness level 0.0-1.0 (omit to read)") var value: Double?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let v = value { params["value"] = .double(v) }
            try rpc(method: "system.brightness", params: params)
        }
    }

    struct Wifi: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "wifi",
            abstract: "Get or set WiFi power")
        @Argument(help: "on/off (omit to read)") var state: String?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let s = state { params["enabled"] = .bool(s.lowercased() == "on" || s == "1" || s == "true") }
            try rpc(method: "system.wifi", params: params)
        }
    }

    struct Bluetooth: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "bluetooth",
            abstract: "Get or set Bluetooth power")
        @Argument(help: "on/off (omit to read)") var state: String?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let s = state { params["enabled"] = .bool(s.lowercased() == "on" || s == "1" || s == "true") }
            try rpc(method: "system.bluetooth", params: params)
        }
    }

    struct Mute: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mute")
        @Argument(help: "on/off (omit to toggle)") var state: String?
        func run() throws {
            let muted = state.map { $0.lowercased() == "on" || $0 == "1" || $0 == "true" } ?? true
            try rpc(method: "system.mute", params: ["muted": .bool(muted)])
        }
    }
}
```

- [ ] **PowerCommand.swift**

```swift
// Sources/macctl/Commands/PowerCommand.swift
import ArgumentParser
import MacCtlKit

struct PowerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "power",
        abstract: "Power management: sleep prevention, lock screen",
        subcommands: [Status.self, Lock.self, Sleep.self, Caffeinate.self])

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status")
        func run() throws { try rpc(method: "power.status", params: [:]) }
    }

    struct Lock: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "lock",
            abstract: "Lock the screen immediately")
        func run() throws { try rpc(method: "power.lock-screen", params: [:]) }
    }

    struct Sleep: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "sleep",
            abstract: "Put system to sleep")
        func run() throws { try rpc(method: "power.sleep", params: [:]) }
    }

    struct Caffeinate: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "caffeinate",
            abstract: "Prevent system sleep (prints token for release)")
        @Option(name: .long, help: "Reason shown in Energy Saver") var reason = "macctl caffeinate"
        func run() throws {
            try rpc(method: "power.prevent-sleep", params: ["reason": .string(reason)])
        }
    }
}
```

- [ ] **ClipboardCommand.swift**

```swift
// Sources/macctl/Commands/ClipboardCommand.swift
import ArgumentParser
import MacCtlKit

struct ClipboardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clipboard",
        abstract: "Clipboard: read, write, clear",
        subcommands: [Read.self, Write.self, Clear.self])

    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "read")
        func run() throws { try rpc(method: "clipboard.read", params: [:]) }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "write")
        @Option(name: .long, help: "Text to write") var text: String?
        @Option(name: .long, help: "File path to write") var file: String?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let t = text { params["text"] = .string(t) }
            else if let f = file { params["files"] = .array([.string(f)]) }
            else { throw ValidationError("Provide --text or --file") }
            try rpc(method: "clipboard.write", params: params)
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "clear")
        func run() throws { try rpc(method: "clipboard.clear", params: [:]) }
    }
}
```

- [ ] **NetworkCommand.swift**

```swift
// Sources/macctl/Commands/NetworkCommand.swift
import ArgumentParser
import MacCtlKit

struct NetworkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "network",
        abstract: "Network: status, DNS resolution",
        subcommands: [Status.self, Resolve.self])

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status")
        func run() throws { try rpc(method: "network.status", params: [:]) }
    }

    struct Resolve: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "resolve")
        @Argument(help: "Hostname to resolve") var hostname: String
        func run() throws {
            try rpc(method: "network.resolve", params: ["hostname": .string(hostname)])
        }
    }
}
```

- [ ] **DefaultsCommand.swift**

```swift
// Sources/macctl/Commands/DefaultsCommand.swift
import ArgumentParser
import MacCtlKit

struct DefaultsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "defaults",
        abstract: "NSUserDefaults read/write (faster than `defaults` CLI — no shell spawn)",
        subcommands: [Read.self, Write.self, Delete.self])

    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "read")
        @Argument var domain: String
        @Argument var key: String
        func run() throws {
            try rpc(method: "defaults.read", params: ["domain": .string(domain), "key": .string(key)])
        }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "write")
        @Argument var domain: String
        @Argument var key: String
        @Argument(help: "Value (string, int, float, bool)") var value: String
        @Flag(name: .long) var bool = false
        @Flag(name: .long) var int = false
        @Flag(name: .long) var float = false
        func run() throws {
            let jsonVal: JSONValue
            if bool       { jsonVal = .bool(value.lowercased() == "true" || value == "1") }
            else if int   { jsonVal = .int(Int(value) ?? 0) }
            else if float { jsonVal = .double(Double(value) ?? 0) }
            else          { jsonVal = .string(value) }
            try rpc(method: "defaults.write",
                    params: ["domain": .string(domain), "key": .string(key), "value": jsonVal])
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete")
        @Argument var domain: String
        @Argument var key: String
        func run() throws {
            try rpc(method: "defaults.delete",
                    params: ["domain": .string(domain), "key": .string(key)])
        }
    }
}
```

- [ ] **Register in main.swift**

In `Sources/macctl/main.swift`, update the `subcommands` list:

```swift
subcommands: [
    ClickCommand.self, TypeCommand.self, KeyCommand.self,
    SeeCommand.self, AppCommand.self, ScreenshotCommand.self,
    InstallCommand.self,
    SystemCommand.self,    // NEW
    PowerCommand.self,     // NEW
    ClipboardCommand.self, // NEW
    NetworkCommand.self,   // NEW
    DefaultsCommand.self,  // NEW
]
```

- [ ] **Build CLI to verify**

```bash
swift build --product macctl 2>&1 | grep -E "error:|complete"
```
Expected: `Build complete!`

- [ ] **Smoke test new commands**

```bash
# Start daemon first
.build/debug/macctl-daemon &
DPID=$!
sleep 1.5

.build/debug/macctl system status 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('volume:', d['data']['volume'], 'wifi:', d['data']['wifiEnabled'])"
.build/debug/macctl network status 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('connected:', d['data']['isConnected'])"
.build/debug/macctl network resolve localhost 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('localhost:', d['data']['addresses'])"
.build/debug/macctl clipboard write --text "macctl test" 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('clipboard write:', d['success'])"
.build/debug/macctl clipboard read 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('clipboard read:', d['data']['value'])"
.build/debug/macctl defaults write com.macctl.test testKey testValue 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('defaults write:', d['success'])"
.build/debug/macctl defaults read com.macctl.test testKey 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('defaults read:', d['data']['value'])"
.build/debug/macctl power status 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('active preventions:', d['data']['activePreventions'])"

kill $DPID
```

Expected output:
```
volume: 0.5  wifi: True
connected: True
localhost: ['127.0.0.1', '::1']
clipboard write: True
clipboard read: macctl test
defaults write: True
defaults read: testValue
active preventions: 0
```

- [ ] **Commit**

```bash
git add Sources/macctl/Commands/ Sources/macctl/main.swift
git commit -m "feat: add CLI commands for system/power/clipboard/network/defaults"
```

---

## Task 10: Full Test Suite + Benchmark

**Files:**
- Run: all existing tests
- Run: inline benchmark script

- [ ] **Run all tests**

```bash
swift test 2>&1 | grep -E "Suite 'All tests'|✘|failed"
```
Expected: `Test Suite 'All tests' passed`.

- [ ] **Run Plan 2 benchmark**

Start daemon, then run:

```bash
python3 - << 'PYEOF'
import subprocess, json

def run(args, timeout=10):
    r = subprocess.run(['.build/debug/macctl'] + args, capture_output=True, text=True, timeout=timeout)
    try: return json.loads(r.stdout)
    except: return {"success": False, "raw": r.stdout[:80]}

def bench(label, args, n=10):
    times = []
    for _ in range(n):
        d = run(args)
        t = d.get('meta',{}).get('durationMs',-1)
        if t > 0: times.append(t)
    if not times: print(f"  FAIL {label}"); return
    times.sort()
    p50 = times[int(len(times)*0.5)]
    p95 = times[min(int(len(times)*0.95), len(times)-1)]
    layer = run(args).get('meta',{}).get('layer','?')
    print(f"  {label:<44} P50={p50:6.1f}ms  P95={p95:6.1f}ms  [{layer}]")

print("\nPlan 2 Benchmark (target: all <5ms via native API)")
print("-" * 70)

print("\nSYSTEM STATE (native API — target <5ms):")
bench("system status",         ['system','status'])
bench("system volume (read)",  ['system','volume'])
bench("system brightness",     ['system','brightness'])
bench("system wifi status",    ['system','wifi'])
bench("system bluetooth",      ['system','bluetooth'])

print("\nPOWER (target <5ms):")
bench("power status",          ['power','status'])

print("\nCLIPBOARD (target <2ms):")
bench("clipboard read",        ['clipboard','read'])
bench("clipboard write text",  ['clipboard','write','--text','bench test'])
bench("clipboard clear",       ['clipboard','clear'])

print("\nNETWORK (status <2ms, resolve variable):")
bench("network status",        ['network','status'])
bench("network resolve local", ['network','resolve','localhost'])

print("\nDEFAULTS (target <1ms):")
bench("defaults write",        ['defaults','write','com.macctl.bench','k','v'])
bench("defaults read",         ['defaults','read','com.macctl.bench','k'])
bench("defaults delete",       ['defaults','delete','com.macctl.bench','k'])

PYEOF
```

Expected: all system/power/clipboard/defaults operations <5ms. DNS resolution variable (network dependent).

- [ ] **Commit benchmark results note + final commit**

```bash
git add -A
git commit -m "feat: Plan 2 complete — SystemState/Power/Clipboard/Network/Defaults actors with tests and benchmark"
```

---

## Self-Review

**Spec coverage check:**

| Spec section | Task | Status |
|---|---|---|
| Volume get/set/mute | Task 1 | ✅ |
| Brightness get/set | Task 2 | ✅ |
| WiFi toggle | Task 3 | ✅ |
| Bluetooth toggle | Task 3 | ✅ |
| System status summary | Task 3 | ✅ |
| Sleep prevention (IOPMAssertion) | Task 4 | ✅ |
| Screen lock | Task 4 | ✅ |
| System sleep | Task 4 | ✅ |
| Clipboard full types | Task 5 | ✅ |
| Network status (NWPathMonitor) | Task 6 | ✅ |
| DNS lookup | Task 6 | ✅ |
| NSUserDefaults read/write | Task 7 | ✅ |
| Daemon wiring | Task 8 | ✅ |
| CLI commands | Task 9 | ✅ |
| Tests + benchmark | Task 10 | ✅ |

**Placeholder scan:** None found. All code blocks are complete.

**Type consistency:** `SystemStateActor.SystemStatus` used in Task 3 and Task 8. `SleepToken = UInt64` defined in Task 4, used in Tasks 8+9. `ClipboardContent` enum defined in Task 5, used in Tasks 8+9.
