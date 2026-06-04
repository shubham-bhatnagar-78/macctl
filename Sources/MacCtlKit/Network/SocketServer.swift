import Foundation
import Logging

public actor SocketServer {
    public static let defaultSocketPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("macctl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daemon.sock").path
    }()

    private let socketPath: String
    private var serverFD: Int32 = -1
    private let logger = Logger(label: "macctl.socket-server")
    private var messageHandler: (@Sendable (Data) async throws -> Data)?

    public init(socketPath: String = SocketServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public func setMessageHandler(_ handler: @escaping @Sendable (Data) async throws -> Data) {
        self.messageHandler = handler
    }

    public func start() throws {
        try? FileManager.default.removeItem(atPath: socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw SocketError.createFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cPath in
                ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    _ = strlcpy(dest, cPath, 104)
                }
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw SocketError.bindFailed(errno) }
        guard listen(serverFD, 128) == 0 else { throw SocketError.listenFailed(errno) }

        logger.info("Listening on \(socketPath)")
        let fd = serverFD
        let handler = messageHandler
        Task.detached { await self.acceptLoop(serverFD: fd, handler: handler) }
    }

    private func acceptLoop(serverFD: Int32, handler: (@Sendable (Data) async throws -> Data)?) async {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { continue }
            Task.detached { await self.handleClient(fd: clientFD, handler: handler) }
        }
    }

    private func handleClient(fd: Int32, handler: (@Sendable (Data) async throws -> Data)?) async {
        defer { close(fd) }
        var readBuffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)

        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return }
            readBuffer.append(contentsOf: chunk.prefix(n))

            while let message = try? MessageFraming.parse(&readBuffer) {
                guard let h = handler else { continue }
                do {
                    let response = try await h(message)
                    let framed = MessageFraming.frame(response)
                    _ = framed.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
                } catch {
                    let errData = Data("""
                        {"jsonrpc":"2.0","id":"?","success":false,"error":{"code":5,"message":"\(error)"}}
                        """.utf8)
                    let framed = MessageFraming.frame(errData)
                    _ = framed.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
                }
            }
        }
    }

    public func stop() {
        if serverFD >= 0 { close(serverFD); serverFD = -1 }
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}

public enum SocketError: Error, Sendable {
    case createFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case disconnected
    case timeout
}
