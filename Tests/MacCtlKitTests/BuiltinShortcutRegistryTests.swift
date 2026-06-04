import Testing
import CoreGraphics
@testable import MacCtlKit

@Suite("BuiltinShortcutRegistry")
struct BuiltinShortcutRegistryTests {
    @Test func safariNewTab() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "new-tab", app: "com.apple.Safari")
        #expect(combo?.key == "t")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func safariAddressBar() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "focus-addressbar", app: "com.apple.Safari")
        #expect(combo?.key == "l")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func finderNewWindow() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "new-window", app: "com.apple.finder")
        #expect(combo?.key == "n")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func unknownAppReturnsNil() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "new-tab", app: "com.unknown.App")
        #expect(combo == nil)
    }

    @Test func terminalNewTab() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "new-tab", app: "com.apple.Terminal")
        #expect(combo?.key == "t")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func xcodeRun() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "run", app: "com.apple.dt.Xcode")
        #expect(combo?.key == "r")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func xcodeBuild() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "build", app: "com.apple.dt.Xcode")
        #expect(combo?.key == "b")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func notesNewNote() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "new-note", app: "com.apple.Notes")
        #expect(combo?.key == "n")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func calendarToday() {
        let combo = BuiltinShortcutRegistry.shortcut(for: "today", app: "com.apple.iCal")
        #expect(combo?.key == "t")
        #expect(combo?.modifiers == .maskCommand)
    }

    @Test func allShortcutsForSafari() {
        let all = BuiltinShortcutRegistry.allShortcuts(for: "com.apple.Safari")
        #expect((all?.count ?? 0) > 10)
    }
}
