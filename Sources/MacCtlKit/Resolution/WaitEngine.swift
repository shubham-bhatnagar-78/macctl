@preconcurrency import ApplicationServices
import Foundation

/// Reliable waits for UI state changes.
/// Primary path: 50ms polling (works in any async context).
/// AXObserver path available for callers that run their own RunLoop.
public enum WaitEngine {

    // MARK: - Wait for element (reliable polling)

    /// Wait for an element matching query to appear. Returns element ID.
    /// Polls every 50ms — max latency to detect: 50ms. Typical: 25ms average.
    public static func waitForElement(
        query: String,
        in pid: pid_t,
        ax: AXActor,
        timeout: Duration = .seconds(5)
    ) async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        // Immediate check — no sleep if already present
        let axApp = await ax.appElement(pid: pid)
        if let eid = await ax.findElementID(query: query, in: axApp) { return eid }

        // Poll until found or timeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            let app = await ax.appElement(pid: pid)
            if let eid = await ax.findElementID(query: query, in: app) { return eid }
        }
        throw WaitError.elementNotFound(query)
    }

    // MARK: - Wait for app to respond to AX

    /// Block until app AX tree responds. Uses 100ms polling.
    public static func waitForAppReady(pid: pid_t, timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                AXUIElementCreateApplication(pid),
                kAXRoleAttribute as CFString, &value) == .success { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw WaitError.timeout
    }

    // MARK: - Wait for UI to settle (no changes for N ms)

    /// Wait until the focused window stops changing layout.
    /// Useful before `see` to avoid scanning a partially-loaded UI.
    public static func waitForUISettle(pid: pid_t, settleMs: Int = 100, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var lastCount = -1
        var stableFor = 0

        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                AXUIElementCreateApplication(pid),
                kAXFocusedWindowAttribute as CFString, &ref) == .success else { continue }
            // Count children as a cheap "changed?" proxy
            var children: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(ref as! AXUIElement, kAXChildrenAttribute as CFString, &children)
            let count = (children as? [AXUIElement])?.count ?? 0
            if count == lastCount {
                stableFor += 50
                if stableFor >= settleMs { return }
            } else {
                lastCount = count
                stableFor = 0
            }
        }
        // Timeout is soft — just proceed if UI never settled
    }
}

// MARK: - Supporting types

public enum WaitError: Error, Sendable {
    case timeout
    case elementNotFound(String)
    case observerCreationFailed
}
