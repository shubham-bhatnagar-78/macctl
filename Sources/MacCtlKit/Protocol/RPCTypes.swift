import Foundation

// MARK: - JSONValue

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                                   { self = .null;           return }
        if let b = try? c.decode(Bool.self)                { self = .bool(b);        return }
        if let i = try? c.decode(Int.self)                 { self = .int(i);         return }
        if let d = try? c.decode(Double.self)              { self = .double(d);      return }
        if let s = try? c.decode(String.self)              { self = .string(s);      return }
        if let a = try? c.decode([JSONValue].self)         { self = .array(a);       return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o);      return }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown JSON type"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let v):   try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

// MARK: - Request

public struct RPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: String
    public let method: String
    public let params: [String: JSONValue]?

    public init(id: String, method: String, params: [String: JSONValue]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

// MARK: - Response meta + error

public struct ResponseMeta: Codable, Sendable {
    public let durationMs: Double
    public let layer: String
    public let retries: Int
    public let sessionID: String
    public let daemonVersion: String

    public init(durationMs: Double, layer: String, retries: Int = 0,
                sessionID: String, daemonVersion: String = "1.0.0") {
        self.durationMs = durationMs
        self.layer = layer
        self.retries = retries
        self.sessionID = sessionID
        self.daemonVersion = daemonVersion
    }
}

public struct RPCErrorData: Codable, Sendable {
    public let hint: String
    public let recoverable: Bool
    public let errorCode: String

    public init(hint: String, recoverable: Bool, errorCode: String) {
        self.hint = hint
        self.recoverable = recoverable
        self.errorCode = errorCode
    }
}

public struct RPCError: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: RPCErrorData?

    public init(code: Int, message: String, data: RPCErrorData? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - JSONValue helpers

public extension JSONValue {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }
    var doubleValue: Double? {
        if case .double(let d) = self { return d }
        if case .int(let i) = self { return Double(i) }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

// MARK: - Convenience constructors

public extension RPCError {
    static func elementNotFound(_ query: String, app: String) -> RPCError {
        RPCError(code: 2, message: "Element '\(query)' not found in \(app)",
                 data: RPCErrorData(hint: "Run 'macctl see --app \(app)'",
                                    recoverable: true, errorCode: "elementNotFound"))
    }
    static func appNotRunning(_ bundleID: String) -> RPCError {
        RPCError(code: 4, message: "App '\(bundleID)' is not running",
                 data: RPCErrorData(hint: "Run 'macctl app launch \(bundleID)'",
                                    recoverable: true, errorCode: "appNotRunning"))
    }
    static func timeout(_ operation: String) -> RPCError {
        RPCError(code: 3, message: "Timeout: \(operation)",
                 data: RPCErrorData(hint: "Increase --timeout or check app responsiveness",
                                    recoverable: true, errorCode: "timeout"))
    }
    static func operationFailed(_ msg: String) -> RPCError {
        RPCError(code: 5, message: msg,
                 data: RPCErrorData(hint: "Check arguments and try again",
                                    recoverable: false, errorCode: "operationFailed"))
    }
}
