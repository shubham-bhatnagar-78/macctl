import Foundation

public actor AdapterRegistry {
    public static let shared = AdapterRegistry()

    private var adapters: [String: any AppAdapter] = [:]

    private init() {}

    public func register(_ adapter: some AppAdapter) {
        adapters[adapter.bundleIdentifier] = adapter
    }

    public func adapter(for bundleID: String) -> (any AppAdapter)? {
        adapters[bundleID]
    }

    public func allBundleIDs() -> [String] {
        Array(adapters.keys).sorted()
    }
}
