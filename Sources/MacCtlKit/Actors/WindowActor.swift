@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation
import Logging

public struct WindowInfo: Sendable {
    public let windowID: CGWindowID
    public let title: String
    public let appName: String
    public let bundleID: String
    public let pid: pid_t
    public let frame: CGRect
    public let isMinimized: Bool
    public let isFullScreen: Bool
    public let screenIndex: Int
}

public actor WindowActor {
    private let logger = Logger(label: "macctl.window")
    public init() {}

    public func listWindows(app bundleID: String? = nil) -> [WindowInfo] {
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var pidToBID: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier { pidToBID[app.processIdentifier] = bid }
        }
        return list.compactMap { info -> WindowInfo? in
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let bd  = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            let title   = info[kCGWindowName as String] as? String ?? ""
            let appName = info[kCGWindowOwnerName as String] as? String ?? ""
            let bid     = pidToBID[pid] ?? ""
            if let f = bundleID, bid != f { return nil }
            guard !appName.isEmpty else { return nil }
            let frame = CGRect(origin: CGPoint(x: bd["X"] ?? 0, y: bd["Y"] ?? 0),
                               size:   CGSize(width: bd["Width"] ?? 0, height: bd["Height"] ?? 0))
            return WindowInfo(windowID: wid, title: title, appName: appName, bundleID: bid,
                              pid: pid, frame: frame, isMinimized: false, isFullScreen: false,
                              screenIndex: screenIdx(frame))
        }
    }

    public func move(windowID: CGWindowID, x: Double, y: Double) {
        guard let el = firstWindow(windowID) else { return }
        var p = CGPoint(x: x, y: y)
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
        }
    }

    public func resize(windowID: CGWindowID, width: Double, height: Double) {
        guard let el = firstWindow(windowID) else { return }
        var s = CGSize(width: width, height: height)
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
        }
    }

    public func setBounds(windowID: CGWindowID, x: Double, y: Double, w: Double, h: Double) {
        move(windowID: windowID, x: x, y: y)
        resize(windowID: windowID, width: w, height: h)
    }

    public func focus(pid: pid_t) {
        NSWorkspace.shared.runningApplications
            .first { $0.processIdentifier == pid }?
            .activate(options: .activateIgnoringOtherApps)
    }

    public func minimize(windowID: CGWindowID) {
        guard let el = firstWindow(windowID) else { return }
        AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, true as CFBoolean)
    }

    public func unminimize(windowID: CGWindowID) {
        guard let el = firstWindow(windowID) else { return }
        AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, false as CFBoolean)
    }

    public func setFullScreen(windowID: CGWindowID, enabled: Bool) {
        guard let el = firstWindow(windowID) else { return }
        AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString, enabled as CFBoolean)
    }

    public func tileLeft(windowID: CGWindowID)  { tile(windowID, right: false) }
    public func tileRight(windowID: CGWindowID) { tile(windowID, right: true)  }

    private func tile(_ windowID: CGWindowID, right: Bool) {
        let windows = listWindows()
        guard let info = windows.first(where: { $0.windowID == windowID }) else { return }
        let idx = info.screenIndex
        let screen = idx < NSScreen.screens.count ? NSScreen.screens[idx] : (NSScreen.main ?? NSScreen.screens[0])
        let f = screen.visibleFrame
        setBounds(windowID: windowID,
                  x: right ? f.midX : f.minX, y: f.minY,
                  w: f.width / 2, h: f.height)
    }

    private func windowPID(_ windowID: CGWindowID) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let pid = list.first?[kCGWindowOwnerPID as String] as? Int32 else { return nil }
        return pid
    }

    private func firstWindow(_ windowID: CGWindowID) -> AXUIElement? {
        guard let pid = windowPID(windowID) else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement], !windows.isEmpty else { return nil }
        let title = (CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]])?
                    .first?[kCGWindowName as String] as? String
        if let t = title {
            for win in windows {
                var tr: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &tr) == .success,
                   tr as? String == t { return win }
            }
        }
        return windows[0]
    }

    private func screenIdx(_ frame: CGRect) -> Int {
        for (i, s) in NSScreen.screens.enumerated() { if s.frame.intersects(frame) { return i } }
        return 0
    }
}

public enum WindowError: Error, Sendable {
    case windowNotFound(CGWindowID)
    case axAccessFailed
}
