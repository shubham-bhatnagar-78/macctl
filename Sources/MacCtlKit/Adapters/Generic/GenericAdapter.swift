@preconcurrency import AppKit

/// Fallback adapter for any app not in the builtin registry.
/// Uses keyboard shortcut discovery (runtime AX menu scan — future) + AX element actions.
public actor GenericAdapter: AppAdapter {
    public nonisolated let bundleIdentifier: String
    public nonisolated let displayName: String
    public nonisolated var builtinShortcuts: [String: KeyCombo]? { nil }
    public nonisolated var capabilities: AdapterCapabilities { [.keyboard, .accessibility] }

    public init(bundleID: String, displayName: String? = nil) {
        self.bundleIdentifier = bundleID
        self.displayName = displayName ?? bundleID
    }

    public func isAvailable() async -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    public func perform(_ operation: MacOperation) async throws -> OperationResult {
        // GenericAdapter defers to OperationRouter — declares capabilities, doesn't execute
        throw RPCError.operationFailed("Use OperationRouter for dispatch, not GenericAdapter.perform directly")
    }
}
