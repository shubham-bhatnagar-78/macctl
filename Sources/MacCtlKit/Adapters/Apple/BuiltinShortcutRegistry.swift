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
            "in-point":     KeyCombo("i"),
            "out-point":    KeyCombo("o"),
            "export":       KeyCombo("e", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: GarageBand
        "com.apple.GarageBand": [
            "play-pause":   KeyCombo(" "),
            "record":       KeyCombo("r"),
            "undo":         KeyCombo("z", .maskCommand),
            "find":         KeyCombo("f", .maskCommand),
        ],

        // MARK: Screen Sharing
        "com.apple.ScreenSharing": [
            "fullscreen":   KeyCombo("f", [.maskCommand, .maskControl]),
        ],

        // MARK: iPhone Mirroring (macOS 15+)
        "com.apple.ScreenContinuity": [
            "connect":      KeyCombo("k", [.maskCommand, .maskShift]),
            "fullscreen":   KeyCombo("f", [.maskCommand, .maskControl]),
            "actual-size":  KeyCombo("0", .maskCommand),
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

        // MARK: Migration Assistant — no useful shortcuts
        "com.apple.MigrationAssistant": [:],

        // MARK: System Information
        "com.apple.SystemProfiler": [
            "find":         KeyCombo("f", .maskCommand),
        ],
    ]
    // swiftformat:enable all
}
