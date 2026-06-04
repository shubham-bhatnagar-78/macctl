import Foundation
import Logging

/// Unix domain socket server.
/// Blocking accept()/read()/write() run on dedicated DispatchQueue threads —
/// NOT on Swift's cooperative thread pool (which blocking calls would starve).
public final class SocketServer: Sendable {
    public static let defaultSocketPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("macctl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daemon.sock").path
    }()

    private let socketPath: String
    private let messageHandler: @Sendable (Data) async throws -> Data
    private let logger = Logger(label: "macctl.socket-server")
    private let acceptQueue = DispatchQueue(label: "macctl.accept", qos: .userInteractive)
    private let clientQueue = DispatchQueue(label: "macctl.clients", qos: .userInteractive,
                                            attributes: .concurrent)

    public init(socketPath: String = SocketServer.defaultSocketPath,
                handler: @escaping @Sendable (Data) async throws -> Data) {
        self.socketPath = socketPath
        self.messageHandler = handler
    }

    public func start() throws {
        try? FileManager.default.removeItem(atPath: socketPath)

        let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw SocketError.createFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cStr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 104) {
                    _ = strlcpy($0, cStr, 104)
                }
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { close(serverFD); throw SocketError.bindFailed(errno) }
        guard listen(serverFD, 128) == 0 else { close(serverFD); throw SocketError.listenFailed(errno) }

        logger.info("Listening on \(socketPath)")

        // Accept loop on dedicated thread — never touches Swift cooperative pool
        acceptQueue.async { [weak self] in
            guard let self else { return }
            while true {
                let clientFD = accept(serverFD, nil, nil)
                guard clientFD >= 0 else { continue }
                self.clientQueue.async { self.handleClient(fd: clientFD) }
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)

        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return }
            buf.append(contentsOf: chunk.prefix(n))

            guard let message = try? MessageFraming.parse(&buf) else { continue }

            // Bridge blocking DispatchQueue thread → async handler → back.
            // ResponseBox is protected by semaphore — single-writer, safe.
            let box = ResponseBox()
            let sem = DispatchSemaphore(value: 0)
            let captured = message
            let handler = self.messageHandler
            Task.detached {
                do { box.value = try await handler(captured) }
                catch { box.value = Data(#"{"success":false,"error":{"code":5}}"#.utf8) }
                sem.signal()
            }
            sem.wait()
            let response = box.value

            let framed = MessageFraming.frame(response)
            _ = framed.withUnsafeBytes { ptr in write(fd, ptr.baseAddress!, ptr.count) }
        }
    }
}

/// Mutable container that is @unchecked Sendable — safe because access is
/// serialized by the DispatchSemaphore in handleClient.
private final class ResponseBox: @unchecked Sendable {
    var value: Data = Data()
}

public enum SocketError: Error, Sendable {
    case createFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case disconnected
}
