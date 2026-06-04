import Foundation

/// 4-byte big-endian length-prefix framing for JSON-RPC messages over Unix socket.
public enum MessageFraming {
    public static func frame(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var result = Data(bytes: &length, count: 4)
        result.append(data)
        return result
    }

    /// Parse one message from buffer. Consumes bytes on success. Returns nil if incomplete.
    public static func parse(_ buffer: inout Data) throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer[0..<4].withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }
        guard length > 0, length <= 16_000_000 else {
            throw MessageFramingError.invalidLength(length)
        }
        let total = Int(4 + length)
        guard buffer.count >= total else { return nil }
        let message = Data(buffer[4..<total])
        buffer.removeFirst(total)
        return message
    }
}

public enum MessageFramingError: Error, Sendable {
    case invalidLength(UInt32)
}
