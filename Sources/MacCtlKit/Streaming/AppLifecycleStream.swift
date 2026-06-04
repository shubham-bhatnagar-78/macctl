@preconcurrency import AppKit
import Foundation

/// Streams app launch/quit/activate/hide/unhide events via NSWorkspace notifications.
public enum AppLifecycleStream {
    public static func watch() -> AsyncStream<Data> {
        AsyncStream { continuation in
            let nc = NSWorkspace.shared.notificationCenter
            let tokenBox = TokenBox()

            func emit(_ event: String, _ app: NSRunningApplication) {
                let payload: [String: String] = [
                    "type":     "event",
                    "event":    event,
                    "bundleID": app.bundleIdentifier ?? "",
                    "name":     app.localizedName ?? "",
                    "pid":      "\(app.processIdentifier)",
                    "ts":       "\(Int(Date().timeIntervalSince1970))",
                ]
                if let data = try? JSONEncoder().encode(payload) {
                    continuation.yield(MessageFraming.frame(data))
                }
            }

            let events: [(NSNotification.Name, String)] = [
                (NSWorkspace.didLaunchApplicationNotification,    "launched"),
                (NSWorkspace.didTerminateApplicationNotification, "terminated"),
                (NSWorkspace.didActivateApplicationNotification,  "activated"),
                (NSWorkspace.didHideApplicationNotification,      "hidden"),
                (NSWorkspace.didUnhideApplicationNotification,    "unhidden"),
            ]

            for (name, event) in events {
                let token = nc.addObserver(forName: name, object: nil, queue: nil) { note in
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                                    as? NSRunningApplication else { return }
                    emit(event, app)
                }
                tokenBox.tokens.append(token)
            }

            continuation.onTermination = { @Sendable _ in
                tokenBox.tokens.forEach { nc.removeObserver($0) }
            }
        }
    }
}

private final class TokenBox: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
}
