@preconcurrency import AppKit
import ScreenCaptureKit

public actor PermissionBootstrap {
    public struct Status: Sendable {
        public let accessibility: Bool
        public let screenRecording: Bool
        public var allGranted: Bool { accessibility && screenRecording }
    }

    public init() {}

    public nonisolated func status() -> Status {
        Status(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    public func requestAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    public func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    public func waitForPermissions(timeout: Duration = .seconds(120)) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while true {
                    if await self.status().allGranted { return }
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw PermissionError.timeout
            }
            try await group.next()!
            group.cancelAll()
        }
    }
}

public enum PermissionError: Error, Sendable {
    case timeout
    case denied(String)
}
