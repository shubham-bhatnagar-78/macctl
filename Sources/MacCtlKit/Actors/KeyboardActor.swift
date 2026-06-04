import CoreGraphics
import AppKit
import Logging

public actor KeyboardActor {
    public init() {}
    private let logger = Logger(label: "macctl.keyboard")

    // Compile-time virtual key code map
    private static let keyMap: [String: CGKeyCode] = [
        "a":0x00,"s":0x01,"d":0x02,"f":0x03,"h":0x04,"g":0x05,"z":0x06,"x":0x07,
        "c":0x08,"v":0x09,"b":0x0B,"q":0x0C,"w":0x0D,"e":0x0E,"r":0x0F,"y":0x10,
        "t":0x11,"1":0x12,"2":0x13,"3":0x14,"4":0x15,"6":0x16,"5":0x17,"=":0x18,
        "9":0x19,"7":0x1A,"-":0x1B,"8":0x1C,"0":0x1D,"]":0x1E,"o":0x1F,"u":0x20,
        "[":0x21,"i":0x22,"p":0x23,"\r":0x24,"l":0x25,"j":0x26,"'":0x27,"k":0x28,
        ";":0x29,"\\":0x2A,",":0x2B,"/":0x2C,"n":0x2D,"m":0x2E,".":0x2F,"\t":0x30,
        " ":0x31,"`":0x32,"\u{7F}":0x33,"\u{1B}":0x35,
        // Arrow keys
        "\u{F700}":0x7E,"\u{F701}":0x7D,"\u{F702}":0x7B,"\u{F703}":0x7C,
        // Function keys
        "F1":0x7A,"F2":0x78,"F3":0x63,"F4":0x76,"F5":0x60,"F6":0x61,
        "F7":0x62,"F8":0x64,"F9":0x65,"F10":0x6D,"F11":0x67,"F12":0x6F,
    ]

    // MARK: - Post key combo

    public func post(combo: KeyCombo, to pid: pid_t) async throws {
        if let keyCode = Self.keyMap[combo.key] {
            try await postVirtualKey(keyCode, modifiers: combo.modifiers, pid: pid)
        } else if let scalar = combo.key.unicodeScalars.first {
            try await postUnicodeKey(scalar, modifiers: combo.modifiers, pid: pid)
        } else {
            throw KeyboardError.unknownKey(combo.key)
        }
    }

    private func postVirtualKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags, pid: pid_t) async throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { throw KeyboardError.eventCreationFailed }
        if !modifiers.isEmpty { down.flags = modifiers; up.flags = modifiers }
        down.postToPid(pid)
        try await Task.sleep(for: .milliseconds(1))  // 1ms: enough for system to register keydown
        up.postToPid(pid)
    }

    private func postUnicodeKey(_ scalar: Unicode.Scalar, modifiers: CGEventFlags, pid: pid_t) async throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up   = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else { throw KeyboardError.eventCreationFailed }
        var uc = UniChar(scalar.value & 0xFFFF)
        down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uc)
        up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uc)
        if !modifiers.isEmpty { down.flags = modifiers; up.flags = modifiers }
        down.postToPid(pid)
        try await Task.sleep(for: .milliseconds(1))
        up.postToPid(pid)
    }

    // MARK: - Builtin shortcut dispatch

    /// Post builtin shortcut for named action. Returns true if found and posted.
    public func postBuiltin(action: String, bundleID: String, pid: pid_t) async throws -> Bool {
        guard let combo = BuiltinShortcutRegistry.shortcut(for: action, app: bundleID) else {
            return false
        }
        try await post(combo: combo, to: pid)
        return true
    }

    // MARK: - Combo string parser ("cmd+shift+n" → KeyCombo)

    public static func parseCombo(_ raw: String) -> KeyCombo {
        let parts = raw.lowercased().components(separatedBy: "+")
        var mods = CGEventFlags()
        var key = ""
        for part in parts {
            switch part {
            case "cmd", "command":          mods.insert(.maskCommand)
            case "shift":                   mods.insert(.maskShift)
            case "opt", "option", "alt":    mods.insert(.maskAlternate)
            case "ctrl", "control":         mods.insert(.maskControl)
            default:                        key = part
            }
        }
        return KeyCombo(key, mods)
    }
}

public enum KeyboardError: Error, Sendable {
    case unknownKey(String)
    case eventCreationFailed
}
