import Foundation

// MARK: - JSON-RPC wire types

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID?
    let method: String
    let params: [String: AnyCodable]?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCID?
    var result: AnyCodable?
    var error: JSONRPCError?

    init(id: JSONRPCID?, result: Any) {
        self.jsonrpc = "2.0"; self.id = id
        self.result = AnyCodable(result); self.error = nil
    }
    init(id: JSONRPCID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"; self.id = id
        self.result = nil; self.error = error
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
}

enum JSONRPCID: Codable, Equatable {
    case string(String), int(Int), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                           { self = .null;    return }
        if let s = try? c.decode(String.self)      { self = .string(s); return }
        if let i = try? c.decode(Int.self)         { self = .int(i);  return }
        self = .null
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i):    try c.encode(i)
        case .null:          try c.encodeNil()
        }
    }
}

// Heterogeneous JSON value — bridges Swift ↔ JSON for MCP messages
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                                { value = NSNull(); return }
        if let b = try? c.decode(Bool.self)             { value = b; return }
        if let i = try? c.decode(Int.self)              { value = i; return }
        if let d = try? c.decode(Double.self)           { value = d; return }
        if let s = try? c.decode(String.self)           { value = s; return }
        if let a = try? c.decode([AnyCodable].self)     { value = a.map(\.value); return }
        if let o = try? c.decode([String: AnyCodable].self) { value = o.mapValues(\.value); return }
        value = NSNull()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull:         try c.encodeNil()
        case let b as Bool:     try c.encode(b)
        case let i as Int:      try c.encode(i)
        case let d as Double:   try c.encode(d)
        case let s as String:   try c.encode(s)
        case let a as [Any]:    try c.encode(a.map { AnyCodable($0) })
        case let o as [String: Any]: try c.encode(o.mapValues { AnyCodable($0) })
        default:                try c.encode(String(describing: value))
        }
    }
}

enum MCPError: Error {
    case unknownTool(String)
    case daemonError(String)
    case daemonNotRunning
}
