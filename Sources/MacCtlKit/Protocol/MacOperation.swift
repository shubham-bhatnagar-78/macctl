import CoreGraphics
import Foundation

// MARK: - KeyCombo

public struct KeyCombo: Sendable, Equatable {
    public let key: String
    public let modifiers: CGEventFlags

    public init(_ key: String, _ modifiers: CGEventFlags = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

// MARK: - Supporting enums

public enum ScrollDirection: String, Sendable, Codable {
    case up, down, left, right
}

public enum ScreenshotMode: String, Sendable, Codable {
    case screen, window, focused
}

public enum ClipboardContent: Sendable {
    case text(String)
    case html(String)
    case fileURL(URL)
}

// MARK: - MacOperation

public enum MacOperation: Sendable {
    case click(query: String, app: String, background: Bool)
    case clickCoords(x: Double, y: Double, app: String, background: Bool)
    case type(text: String, app: String, elementQuery: String?)
    case key(combo: KeyCombo, app: String, background: Bool)
    case scroll(direction: ScrollDirection, amount: Int, app: String, elementQuery: String?)
    case drag(from: CGPoint, to: CGPoint, app: String, duration: Double)
    case screenshot(app: String?, mode: ScreenshotMode)
    case see(app: String)
    case appLaunch(bundleID: String, background: Bool)
    case appQuit(bundleID: String, force: Bool)
    case appHide(bundleID: String)
    case appShow(bundleID: String)
    case appList
    case windowList(app: String?)
    case clipboardRead
    case clipboardWrite(content: ClipboardContent)
    case shell(command: String, timeout: Double)
}
