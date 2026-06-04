import Foundation

public struct AdapterCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let keyboard        = AdapterCapabilities(rawValue: 1 << 0)
    public static let accessibility   = AdapterCapabilities(rawValue: 1 << 1)
    public static let scriptingBridge = AdapterCapabilities(rawValue: 1 << 2)
    public static let frameworkAPI    = AdapterCapabilities(rawValue: 1 << 3)
    public static let cdp             = AdapterCapabilities(rawValue: 1 << 4)
    public static let webInspector    = AdapterCapabilities(rawValue: 1 << 5)
    public static let iosMirroring    = AdapterCapabilities(rawValue: 1 << 6)
}

public protocol AppAdapter: Actor, Sendable {
    nonisolated var bundleIdentifier: String { get }
    nonisolated var displayName: String { get }
    nonisolated var builtinShortcuts: [String: KeyCombo]? { get }
    nonisolated var capabilities: AdapterCapabilities { get }
    func perform(_ operation: MacOperation) async throws -> OperationResult
    func isAvailable() async -> Bool
}
