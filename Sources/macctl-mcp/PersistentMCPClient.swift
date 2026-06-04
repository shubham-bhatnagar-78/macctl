import Foundation
import MacCtlKit

/// Persistent socket connection for MCP server.
/// Stays connected across tool calls — eliminates per-call connect overhead.
/// In a 50-op LLM loop, saves ~50 × 2ms connect = ~100ms vs fresh connections.
final class PersistentMCPClient: @unchecked Sendable {
    private let socketPath = SocketServer.defaultSocketPath
    private var fd: Int32 = -1
    private let lock = NSLock()

    func send(_ data: Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        // Ensure connected
        if fd < 0 { try connect() }
        // Send + receive
        do {
            return try roundTrip(data)
        } catch {
            // Connection dropped — reconnect once and retry
            close(fd); fd = -1
            try connect()
            return try roundTrip(data)
        }
    }

    private func connect() throws {
        let newFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard newFD >= 0 else { throw SocketError.connectFailed(errno) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cStr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, cStr, 104) }
            }
        }
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Foundation.connect(newFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { close(newFD); throw SocketError.connectFailed(errno) }
        fd = newFD
    }

    private func roundTrip(_ data: Data) throws -> Data {
        let framed = MessageFraming.frame(data)
        _ = framed.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { throw SocketError.disconnected }
            buf.append(contentsOf: chunk.prefix(n))
            if let msg = try? MessageFraming.parse(&buf) { return msg }
        }
    }

    deinit { if fd >= 0 { close(fd) } }
}
