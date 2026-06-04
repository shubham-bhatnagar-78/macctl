import Foundation

public struct OperationResult: Sendable {
    public let data: [String: JSONValue]
    public let meta: ResponseMeta

    public init(data: [String: JSONValue] = [:], meta: ResponseMeta) {
        self.data = data
        self.meta = meta
    }
}
