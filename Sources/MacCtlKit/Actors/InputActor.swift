import CoreGraphics
import AppKit
@preconcurrency import ApplicationServices

/// CGEvent-based input synthesis targeting specific PIDs (background-safe).
/// Smart routing is handled by the dispatcher — InputActor is pure CGEvent.
public actor InputActor {
    public init() {}

    // MARK: - Click

    public func click(at point: CGPoint, pid: pid_t, button: CGMouseButton = .left) async throws {
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType:   CGEventType = button == .left ? .leftMouseUp   : .rightMouseUp
        guard let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                                 mouseCursorPosition: point, mouseButton: button),
              let up   = CGEvent(mouseEventSource: nil, mouseType: upType,
                                 mouseCursorPosition: point, mouseButton: button)
        else { throw InputError.eventCreationFailed }
        down.postToPid(pid)
        try await Task.sleep(for: .milliseconds(10))
        up.postToPid(pid)
    }

    // MARK: - Text input

    /// Paste text via clipboard — 3-5ms, any length.
    public func pasteText(_ text: String, pid: pid_t) async throws {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let up   = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        else { throw InputError.eventCreationFailed }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.postToPid(pid)
        try await Task.sleep(for: .milliseconds(2))   // 2ms: enough for keydown registration
        up.postToPid(pid)
        try await Task.sleep(for: .milliseconds(10))  // 10ms: app processes paste event
        pb.clearContents()
        if let prev = previous { pb.setString(prev, forType: .string) }
    }

    /// Type via CGEvent unicode string — last resort for short text, ~5ms/char.
    public func typeViaEvents(_ text: String, pid: pid_t) async throws {
        for scalar in text.unicodeScalars {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up   = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else { continue }
            var uc = UniChar(scalar.value & 0xFFFF)
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uc)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uc)
            down.postToPid(pid)
            try await Task.sleep(for: .milliseconds(2))
            up.postToPid(pid)
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    // MARK: - Scroll

    public func scroll(direction: ScrollDirection, amount: Int, pid: pid_t) throws {
        let dx: Int32 = direction == .right ? Int32(amount) : (direction == .left ? -Int32(amount) : 0)
        let dy: Int32 = direction == .up    ? Int32(amount) : (direction == .down ? -Int32(amount) : 0)
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                  wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        else { throw InputError.eventCreationFailed }
        event.postToPid(pid)
    }

    // MARK: - Drag

    public func drag(from: CGPoint, to: CGPoint, pid: pid_t, steps: Int = 20) async throws {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: from, mouseButton: .left)
        else { throw InputError.eventCreationFailed }
        down.postToPid(pid)
        try await Task.sleep(for: .milliseconds(50))
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let pos = CGPoint(x: from.x + (to.x - from.x) * t,
                              y: from.y + (to.y - from.y) * t)
            if let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                  mouseCursorPosition: pos, mouseButton: .left) {
                drag.postToPid(pid)
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: to, mouseButton: .left)
        else { throw InputError.eventCreationFailed }
        up.postToPid(pid)
    }
}

public enum InputError: Error, Sendable {
    case eventCreationFailed
}
