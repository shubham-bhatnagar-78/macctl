import CoreGraphics

/// Compile-time keyboard shortcut maps for Apple-shipped apps.
/// Lookup is O(1). Zero runtime cost — no AX menu scanning needed.
public enum BuiltinShortcutRegistry {
    public static func shortcut(for action: String, app bundleID: String) -> KeyCombo? {
        registry[bundleID]?[action]
    }

    public static func allShortcuts(for bundleID: String) -> [String: KeyCombo]? {
        registry[bundleID]
    }

    private static let cmd   = CGEventFlags.maskCommand
    private static let shift = CGEventFlags.maskShift
    private static let opt   = CGEventFlags.maskAlternate
    private static let ctrl  = CGEventFlags.maskControl

    // swiftformat:disable all
    private static let registry: [String: [String: KeyCombo]] = [

        // MARK: Finder
        "com.apple.finder": [
            "new-window":     KeyCombo("n", .maskCommand),
            "new-folder":     KeyCombo("n", [.maskCommand, .maskShift]),
            "open":           KeyCombo("\r"),
            "get-info":       KeyCombo("i", .maskCommand),
            "quick-look":     KeyCombo(" "),
            "move-to-trash":  KeyCombo("\u{7F}", .maskCommand),
            "empty-trash":    KeyCombo("\u{7F}", [.maskCommand, .maskShift]),
            "duplicate":      KeyCombo("d", .maskCommand),
            "make-alias":     KeyCombo("l", .maskCommand),
            "eject":          KeyCombo("e", .maskCommand),
            "find":           KeyCombo("f", .maskCommand),
            "go-back":        KeyCombo("[", .maskCommand),
            "go-forward":     KeyCombo("]", .maskCommand),
            "go-parent":      KeyCombo("\u{F700}", .maskCommand),
            "go-applications":KeyCombo("a", [.maskCommand, .maskShift]),
            "go-desktop":     KeyCombo("d", [.maskCommand, .maskShift]),
            "go-documents":   KeyCombo("o", [.maskCommand, .maskShift]),
            "go-downloads":   KeyCombo("l", [.maskCommand, .maskAlternate]),
            "go-home":        KeyCombo("h", [.maskCommand, .maskShift]),
            "go-icloud":      KeyCombo("i", [.maskCommand, .maskShift]),
            "go-recents":     KeyCombo("f", [.maskCommand, .maskShift]),
            "connect-server": KeyCombo("k", .maskCommand),
            "view-icons":     KeyCombo("1", .maskCommand),
            "view-list":      KeyCombo("2", .maskCommand),
            "view-columns":   KeyCombo("3", .maskCommand),
            "view-gallery":   KeyCombo("4", .maskCommand),
        ],

        // MARK: Safari
        "com.apple.Safari": [
            "new-tab":           KeyCombo("t", .maskCommand),
            "new-window":        KeyCombo("n", .maskCommand),
            "new-private":       KeyCombo("n", [.maskCommand, .maskShift]),
            "close-tab":         KeyCombo("w", .maskCommand),
            "reopen-closed-tab": KeyCombo("t", [.maskCommand, .maskShift]),
            "focus-addressbar":  KeyCombo("l", .maskCommand),
            "reload":            KeyCombo("r", .maskCommand),
            "force-reload":      KeyCombo("r", [.maskCommand, .maskAlternate]),
            "find":              KeyCombo("f", .maskCommand),
            "bookmark":          KeyCombo("d", .maskCommand),
            "sidebar":           KeyCombo("l", [.maskCommand, .maskShift]),
            "back":              KeyCombo("[", .maskCommand),
            "forward":           KeyCombo("]", .maskCommand),
            "next-tab":          KeyCombo("]", [.maskCommand, .maskShift]),
            "prev-tab":          KeyCombo("[", [.maskCommand, .maskShift]),
            "history":           KeyCombo("y", .maskCommand),
            "downloads":         KeyCombo("l", [.maskCommand, .maskAlternate]),
            "zoom-in":           KeyCombo("=", .maskCommand),
            "zoom-out":          KeyCombo("-", .maskCommand),
            "zoom-reset":        KeyCombo("0", .maskCommand),
        ],

        // MARK: Notes
        "com.apple.Notes": [
            "new-note":     KeyCombo("n", .maskCommand),
            "new-folder":   KeyCombo("n", [.maskCommand, .maskShift]),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
            "bold":         KeyCombo("b", .maskCommand),
            "italic":       KeyCombo("i", .maskCommand),
            "underline":    KeyCombo("u", .maskCommand),
            "checklist":    KeyCombo("l", [.maskCommand, .maskShift]),
            "table":        KeyCombo("t", [.maskCommand, .maskAlternate]),
        ],

        // MARK: Mail
        "com.apple.mail": [
            "new-message":  KeyCombo("n", .maskCommand),
            "reply":        KeyCombo("r", .maskCommand),
            "reply-all":    KeyCombo("r", [.maskCommand, .maskShift]),
            "forward":      KeyCombo("f", [.maskCommand, .maskShift]),
            "send":         KeyCombo("d", [.maskCommand, .maskShift]),
            "trash":        KeyCombo("\u{7F}", .maskCommand),
            "archive":      KeyCombo("a", [.maskCommand, .maskControl]),
            "mark-read":    KeyCombo("u", [.maskCommand, .maskShift]),
            "mark-junk":    KeyCombo("j", [.maskCommand, .maskShift]),
            "find":         KeyCombo("f", .maskCommand),
            "next-message": KeyCombo("]", .maskCommand),
            "prev-message": KeyCombo("[", .maskCommand),
        ],

        // MARK: Calendar
        "com.apple.iCal": [
            "new-event":    KeyCombo("n", .maskCommand),
            "new-calendar": KeyCombo("n", [.maskCommand, .maskAlternate]),
            "today":        KeyCombo("t", .maskCommand),
            "view-day":     KeyCombo("1", .maskCommand),
            "view-week":    KeyCombo("2", .maskCommand),
            "view-month":   KeyCombo("3", .maskCommand),
            "view-year":    KeyCombo("4", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "refresh":      KeyCombo("r", .maskCommand),
        ],

        // MARK: Reminders
        "com.apple.reminders": [
            "new-reminder": KeyCombo("n", .maskCommand),
            "new-list":     KeyCombo("n", [.maskCommand, .maskAlternate]),
            "delete":       KeyCombo("\u{7F}", .maskCommand),
            "toggle-done":  KeyCombo(" "),
            "find":         KeyCombo("f", .maskCommand),
            "today":        KeyCombo("t", .maskCommand),
        ],

        // MARK: TextEdit
        "com.apple.TextEdit": [
            "new":          KeyCombo("n", .maskCommand),
            "open":         KeyCombo("o", .maskCommand),
            "save":         KeyCombo("s", .maskCommand),
            "save-as":      KeyCombo("s", [.maskCommand, .maskShift]),
            "bold":         KeyCombo("b", .maskCommand),
            "italic":       KeyCombo("i", .maskCommand),
            "underline":    KeyCombo("u", .maskCommand),
            "show-fonts":   KeyCombo("t", .maskCommand),
            "show-colors":  KeyCombo("c", [.maskCommand, .maskShift]),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Terminal
        "com.apple.Terminal": [
            "new-window":   KeyCombo("n", .maskCommand),
            "new-tab":      KeyCombo("t", .maskCommand),
            "close":        KeyCombo("w", .maskCommand),
            "clear":        KeyCombo("k", .maskCommand),
            "split-pane":   KeyCombo("d", .maskCommand),
            "close-split":  KeyCombo("d", [.maskCommand, .maskShift]),
            "next-tab":     KeyCombo("]", [.maskCommand, .maskShift]),
            "prev-tab":     KeyCombo("[", [.maskCommand, .maskShift]),
            "find":         KeyCombo("f", .maskCommand),
            "select-all":   KeyCombo("a", .maskCommand),
        ],

        // MARK: Xcode
        "com.apple.dt.Xcode": [
            "build":              KeyCombo("b", .maskCommand),
            "run":                KeyCombo("r", .maskCommand),
            "test":               KeyCombo("u", .maskCommand),
            "stop":               KeyCombo(".", .maskCommand),
            "clean":              KeyCombo("k", [.maskCommand, .maskShift]),
            "open-quickly":       KeyCombo("o", [.maskCommand, .maskShift]),
            "toggle-navigator":   KeyCombo("0", .maskCommand),
            "toggle-debug":       KeyCombo("y", [.maskCommand, .maskShift]),
            "toggle-inspector":   KeyCombo("0", [.maskCommand, .maskAlternate]),
            "navigate-back":      KeyCombo("\u{F702}", [.maskCommand, .maskControl]),
            "navigate-forward":   KeyCombo("\u{F703}", [.maskCommand, .maskControl]),
            "find-in-project":    KeyCombo("f", [.maskCommand, .maskShift]),
        ],

        // MARK: System Settings
        "com.apple.systempreferences": [
            "focus-search": KeyCombo("l", .maskCommand),
            "close":        KeyCombo("w", .maskCommand),
            "hide":         KeyCombo("h", .maskCommand),
        ],
    ]
    // swiftformat:enable all
}
