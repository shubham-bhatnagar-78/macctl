import Testing
@testable import MacCtlKit

@Suite("AppleAdapterRegistry")
struct AppleAdapterRegistryTests {
    @Test func registryHasAllAppleApps() async throws {
        await AppleAdapterRegistry.registerAll()
        let ids = await AdapterRegistry.shared.allBundleIDs()
        #expect(ids.count >= 59)
    }

    @Test func finderAdapterRegistered() async throws {
        await AppleAdapterRegistry.registerAll()
        let adapter = await AdapterRegistry.shared.adapter(for: "com.apple.finder")
        #expect(adapter != nil)
        #expect(adapter?.bundleIdentifier == "com.apple.finder")
        #expect(adapter?.displayName == "Finder")
    }

    @Test func safariHasKeyboardCapability() async throws {
        await AppleAdapterRegistry.registerAll()
        let adapter = await AdapterRegistry.shared.adapter(for: "com.apple.Safari")
        #expect(adapter?.capabilities.contains(.keyboard) == true)
        #expect(adapter?.capabilities.contains(.scriptingBridge) == true)
    }

    @Test func calendarHasFrameworkAPICapability() async throws {
        await AppleAdapterRegistry.registerAll()
        let adapter = await AdapterRegistry.shared.adapter(for: "com.apple.iCal")
        #expect(adapter?.capabilities.contains(.frameworkAPI) == true)
    }

    @Test func iPhoneMirroringHasIOSMirroringCapability() async throws {
        await AppleAdapterRegistry.registerAll()
        let adapter = await AdapterRegistry.shared.adapter(for: "com.apple.ScreenContinuity")
        #expect(adapter?.capabilities.contains(.iosMirroring) == true)
    }

    @Test func unknownAppReturnsNilFromRegistry() async throws {
        let adapter = await AdapterRegistry.shared.adapter(for: "com.unknown.NotReal")
        #expect(adapter == nil)
    }

    @Test func shortcutRegistryCoversAllApps() async throws {
        await AppleAdapterRegistry.registerAll()
        let ids = await AdapterRegistry.shared.allBundleIDs()
        var withShortcuts = 0
        for id in ids where id.hasPrefix("com.apple.") {
            if let shortcuts = BuiltinShortcutRegistry.allShortcuts(for: id), !shortcuts.isEmpty {
                withShortcuts += 1
            }
        }
        #expect(withShortcuts >= 55)
    }

    // Shortcut spot checks
    @Test func safariNewTabShortcut() {
        let c = BuiltinShortcutRegistry.shortcut(for: "new-tab", app: "com.apple.Safari")
        #expect(c?.key == "t" && c?.modifiers == .maskCommand)
    }

    @Test func xcodeRunShortcut() {
        let c = BuiltinShortcutRegistry.shortcut(for: "run", app: "com.apple.dt.Xcode")
        #expect(c?.key == "r" && c?.modifiers == .maskCommand)
    }

    @Test func calendarTodayShortcut() {
        let c = BuiltinShortcutRegistry.shortcut(for: "today", app: "com.apple.iCal")
        #expect(c?.key == "t" && c?.modifiers == .maskCommand)
    }

    @Test func remindersNewShortcut() {
        let c = BuiltinShortcutRegistry.shortcut(for: "new-reminder", app: "com.apple.reminders")
        #expect(c?.key == "n" && c?.modifiers == .maskCommand)
    }

    @Test func iMoviePlayPauseShortcut() {
        let c = BuiltinShortcutRegistry.shortcut(for: "play-pause", app: "com.apple.iMovieApp")
        #expect(c?.key == " " && c?.modifiers == [])
    }

    @Test func messagesNewMessageShortcut() {
        let c = BuiltinShortcutRegistry.shortcut(for: "new-message", app: "com.apple.MobileSMS")
        #expect(c?.key == "n" && c?.modifiers == .maskCommand)
    }

    @Test func keychainFindShortcut() {
        let c = BuiltinShortcutRegistry.shortcut(for: "find", app: "com.apple.keychainaccess")
        #expect(c?.key == "f" && c?.modifiers == .maskCommand)
    }
}
