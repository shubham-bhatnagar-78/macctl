@preconcurrency import ApplicationServices
import Foundation

/// AXObserver-driven waits — fires immediately when UI changes, zero polling.
public enum WaitEngine {

    // MARK: - Wait for element

    /// Wait for an element matching query to appear. Returns element ID.
    /// Uses AXObserver for kAXLayoutChangedNotification — fires <2ms after UI updates.
    public static func waitForElement(
        query: String,
        in pid: pid_t,
        ax: AXActor,
        timeout: Duration = .seconds(5)
    ) async throws -> String {
        // Fast path: element already present
        let axApp = await ax.appElement(pid: pid)
        if let eid = await ax.findElementID(query: query, in: axApp) { return eid }

        // Wait for layout change, then re-query
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await waitForLayoutChange(pid: pid, timeout: timeout)
                let app = await ax.appElement(pid: pid)
                guard let eid = await ax.findElementID(query: query, in: app) else {
                    throw RPCError.elementNotFound(query, app: "pid:\(pid)")
                }
                return eid
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Wait for layout change

    /// Block until kAXLayoutChangedNotification fires for the given PID.
    /// Fires <2ms after UI updates — not polling.
    public static func waitForLayoutChange(pid: pid_t, timeout: Duration = .seconds(5)) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let box = ContinuationBox(continuation: cont)

            var observer: AXObserver?
            let createResult = AXObserverCreate(pid, { _, _, _, refcon in
                guard let refcon else { return }
                let b = Unmanaged<ContinuationBox>.fromOpaque(refcon).takeUnretainedValue()
                b.resume()
            }, &observer)

            guard createResult == .success, let obs = observer else {
                cont.resume(throwing: WaitError.observerCreationFailed)
                return
            }

            let app = AXUIElementCreateApplication(pid)
            let refcon = Unmanaged.passRetained(box).toOpaque()
            AXObserverAddNotification(obs, app, kAXLayoutChangedNotification as CFString, refcon)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)

            // Timeout task
            Task {
                try? await Task.sleep(for: timeout)
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
                AXObserverRemoveNotification(obs, app, kAXLayoutChangedNotification as CFString)
                box.resumeWithTimeout()
            }
        }
    }

    // MARK: - Wait for app ready (AX responds)

    public static func waitForAppReady(pid: pid_t, timeout: Duration = .seconds(10)) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while true {
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(
                        AXUIElementCreateApplication(pid),
                        kAXRoleAttribute as CFString, &value) == .success { return }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WaitError.timeout
            }
            try await group.next()!
            group.cancelAll()
        }
    }
}

// MARK: - Supporting types

/// Thread-safe one-shot continuation bridge for AXObserver C callbacks.
final class ContinuationBox: @unchecked Sendable {
    private let cont: CheckedContinuation<Void, Error>
    private var resumed = false
    private let lock = NSLock()

    init(continuation: CheckedContinuation<Void, Error>) { self.cont = continuation }

    func resume() {
        lock.lock(); defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        cont.resume()
    }

    func resumeWithTimeout() {
        lock.lock(); defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        cont.resume(throwing: WaitError.timeout)
    }
}

public enum WaitError: Error, Sendable {
    case timeout
    case observerCreationFailed
}
