@preconcurrency import AppKit

/// Generic adapter for any Apple-shipped app.
/// All 51 Apple apps share this struct — no boilerplate per app.
/// Apps needing special paths (EventKit, ContactsKit) can be
/// replaced in the registry with a custom actor in Plan 3B.
public actor AppleAppAdapter: AppAdapter {
    public nonisolated let bundleIdentifier: String
    public nonisolated let displayName: String
    public nonisolated let capabilities: AdapterCapabilities

    public nonisolated var builtinShortcuts: [String: KeyCombo]? {
        BuiltinShortcutRegistry.allShortcuts(for: bundleIdentifier)
    }

    public init(
        bundleID: String,
        displayName: String,
        capabilities: AdapterCapabilities = [.keyboard, .accessibility]
    ) {
        self.bundleIdentifier = bundleID
        self.displayName = displayName
        self.capabilities = capabilities
    }

    public func isAvailable() async -> Bool {
        NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == bundleIdentifier }
    }

    public func perform(_ operation: MacOperation) async throws -> OperationResult {
        throw RPCError(code: 5,
            message: "AppleAppAdapter.perform not directly callable — use OperationRouter")
    }
}
