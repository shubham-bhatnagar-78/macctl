import Foundation

public struct InputSourceInfo: Sendable {
    public let id: String
    public let localizedName: String
    public let isSelected: Bool
    public let category: String
}

public actor InputSourceActor {
    public init() {}

    /// Current keyboard input source — read from preferences (no TIS, no crash risk).
    public func current() -> InputSourceInfo? {
        guard let prefs = UserDefaults(suiteName: "com.apple.HIToolbox"),
              let id = prefs.string(forKey: "AppleCurrentKeyboardLayoutInputSourceID")
        else { return nil }
        // Extract display name from ID: "com.apple.keylayout.US" → "U.S."
        let name = id.components(separatedBy: ".").last?
                   .replacingOccurrences(of: "-", with: " ") ?? id
        return InputSourceInfo(id: id, localizedName: name, isSelected: true, category: "keyboard")
    }

    /// List enabled input sources from preferences.
    public func list() -> [InputSourceInfo] {
        let currentID = current()?.id
        guard let prefs = UserDefaults(suiteName: "com.apple.HIToolbox"),
              let enabled = prefs.array(forKey: "AppleEnabledInputSources") as? [[String: Any]]
        else { return current().map { [$0] } ?? [] }

        return enabled.compactMap { dict -> InputSourceInfo? in
            guard let id = dict["InputSourceKind"] as? String
                       ?? dict["Bundle ID"] as? String
            else { return nil }
            let name = id.components(separatedBy: ".").last?
                       .replacingOccurrences(of: "-", with: " ") ?? id
            return InputSourceInfo(id: id, localizedName: name,
                                   isSelected: id == currentID, category: "keyboard")
        }
    }

    /// Switch input source via AppleScript (reliable, works in daemon context).
    public func select(id: String) throws {
        let script = "tell application \"System Events\" to set the input source to \"\(id)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 { throw InputSourceError.selectFailed(id) }
    }

    public func selectByName(_ name: String) throws {
        guard let src = list().first(where: {
            $0.localizedName.localizedCaseInsensitiveContains(name) })
        else { throw InputSourceError.notFound(name) }
        try select(id: src.id)
    }
}

public enum InputSourceError: Error, Sendable {
    case notFound(String)
    case selectFailed(String)
}
