@preconcurrency import AppKit
import Logging

public actor AppLifecycleActor {
    private var bundleURLCache: [String: URL] = [:]
    private var runningApps: [String: NSRunningApplication] = [:]
    private let logger = Logger(label: "macctl.lifecycle")

    public init() {
        Task { await self.refreshRunningIndex() }
        Task { await self.startPollingIndex() }
    }

    // MARK: - Running app index

    private func refreshRunningIndex() {
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier else { continue }
            if app.isTerminated { runningApps.removeValue(forKey: bid) }
            else { runningApps[bid] = app }
        }
    }

    private func startPollingIndex() async {
        // Simple polling — adequate for v1. Replace with NSWorkspace notifications in v2.
        while true {
            try? await Task.sleep(for: .seconds(2))
            refreshRunningIndex()
        }
    }

    // MARK: - Queries

    public func isRunning(_ bundleID: String) -> Bool {
        runningApps[bundleID]?.isTerminated == false
    }

    public func pid(for bundleID: String) -> pid_t? {
        guard let app = runningApps[bundleID], !app.isTerminated else { return nil }
        return app.processIdentifier
    }

    public func listRunning() -> [RunningAppInfo] {
        runningApps.values
            .filter { !$0.isTerminated }
            .compactMap { app -> RunningAppInfo? in
                guard let bid = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return RunningAppInfo(bundleID: bid, name: name, pid: app.processIdentifier,
                                     isActive: app.isActive, isHidden: app.isHidden)
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Launch

    public func launch(_ bundleID: String, background: Bool = false) async throws -> pid_t {
        // Return existing PID if already running
        if let existing = pid(for: bundleID) { return existing }
        let url = try bundleURL(for: bundleID)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !background
        config.addsToRecentItems = false
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        if let bid = app.bundleIdentifier { runningApps[bid] = app }
        return app.processIdentifier
    }

    // MARK: - Quit

    public func quit(_ bundleID: String, force: Bool = false) {
        guard let app = runningApps[bundleID], !app.isTerminated else { return }
        if force { app.forceTerminate() } else { app.terminate() }
        runningApps.removeValue(forKey: bundleID)
    }

    // MARK: - Hide / Show

    public func hide(_ bundleID: String) throws {
        guard let app = runningApps[bundleID], !app.isTerminated else {
            throw LifecycleError.appNotRunning(bundleID)
        }
        app.hide()
    }

    public func show(_ bundleID: String) throws {
        guard let app = runningApps[bundleID], !app.isTerminated else {
            throw LifecycleError.appNotRunning(bundleID)
        }
        app.unhide()
        app.activate(options: .activateIgnoringOtherApps)
    }

    // MARK: - Wait until AX-ready

    public func waitUntilReady(_ bundleID: String, timeout: Duration = .seconds(15)) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while true {
                    if let pid = await self.pid(for: bundleID) {
                        var value: CFTypeRef?
                        if AXUIElementCopyAttributeValue(
                            AXUIElementCreateApplication(pid), kAXRoleAttribute as CFString, &value) == .success {
                            return
                        }
                    }
                    try await Task.sleep(for: .milliseconds(150))
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LifecycleError.timeout(bundleID)
            }
            try await group.next()!
            group.cancelAll()
        }
    }

    // MARK: - Pre-warm bundle URLs

    public func preResolveBundleURLs(for bundleIDs: [String]) {
        for bid in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                bundleURLCache[bid] = url
            }
        }
    }

    // MARK: - Internal

    private func bundleURL(for bundleID: String) throws -> URL {
        if let cached = bundleURLCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw LifecycleError.bundleNotFound(bundleID)
        }
        bundleURLCache[bundleID] = url
        return url
    }
}

// MARK: - Supporting types

public struct RunningAppInfo: Sendable {
    public let bundleID: String
    public let name: String
    public let pid: pid_t
    public let isActive: Bool
    public let isHidden: Bool
}

public enum LifecycleError: Error, Sendable {
    case appNotRunning(String)
    case bundleNotFound(String)
    case timeout(String)
}
