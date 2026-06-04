import Foundation

/// Synchronous Unix socket client. Used by CLI binary — one request, one response, disconnect.
public final class SocketClient: Sendable {
    private let socketPath: String

    public init(socketPath: String = SocketServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// Connect, send framed request, read framed response, disconnect. Synchronous.
    public func roundTrip(_ data: Data) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.createFailed(errno) }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cPath in
                ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    _ = strlcpy(dest, cPath, 104)
                }
            }
        }
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw SocketError.connectFailed(errno) }

        // Send
        let framed = MessageFraming.frame(data)
        _ = framed.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }

        // Read until full response
        var readBuffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { throw SocketError.disconnected }
            readBuffer.append(contentsOf: chunk.prefix(n))
            if let msg = try MessageFraming.parse(&readBuffer) { return msg }
        }
    }
}
