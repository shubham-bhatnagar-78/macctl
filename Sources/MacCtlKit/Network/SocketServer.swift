import Foundation
import Logging

/// Bidirectional Unix socket server.
/// Each connection supports both request-response RPC and push streaming.
/// Concurrent read+write via separate DispatchQueues per connection.
public final class SocketServer: Sendable {
    public static let defaultSocketPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("macctl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daemon.sock").path
    }()

    private let socketPath: String
    /// RPC handler: request bytes → response bytes (one-shot)
    private let rpcHandler: @Sendable (Data) async throws -> Data
    /// Subscribe handler: returns AsyncStream of length-prefixed event frames
    private let subscribeHandler: @Sendable (String, [String: JSONValue]) -> AsyncStream<Data>
    private let acceptQueue = DispatchQueue(label: "macctl.accept", qos: .userInteractive)
    private let logger = Logger(label: "macctl.socket-server")

    public init(
        socketPath: String = SocketServer.defaultSocketPath,
        rpc: @escaping @Sendable (Data) async throws -> Data,
        subscribe: @escaping @Sendable (String, [String: JSONValue]) -> AsyncStream<Data>
    ) {
        self.socketPath = socketPath
        self.rpcHandler  = rpc
        self.subscribeHandler = subscribe
    }

    public func start() throws {
        try? FileManager.default.removeItem(atPath: socketPath)
        let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw SocketError.createFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cStr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, cStr, 104) }
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

        acceptQueue.async { [weak self] in
            while true {
                let clientFD = accept(serverFD, nil, nil)
                guard clientFD >= 0 else { continue }
                self?.handleConnection(fd: clientFD)
            }
        }
    }

    private func handleConnection(fd: Int32) {
        let writeQueue = DispatchQueue(label: "macctl.write.\(fd)", qos: .userInteractive)
        let subs = ConnectionSubscriptions()
        let rpc = rpcHandler
        let sub = subscribeHandler

        // Serialized write: multiple tasks can push frames without interleaving
        let sendFrame: @Sendable (Data) -> Void = { data in
            writeQueue.async {
                _ = data.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
            }
        }

        DispatchQueue.global(qos: .userInteractive).async {
            defer { close(fd); subs.cancelAll() }
            var buf = Data()
            var chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(fd, &chunk, chunk.count)
                guard n > 0 else { return }
                buf.append(contentsOf: chunk.prefix(n))
                while let msg = try? MessageFraming.parse(&buf) {
                    Self.handleMessage(msg, fd: fd, sendFrame: sendFrame,
                                       subs: subs, rpc: rpc, sub: sub)
                }
            }
        }
    }

    private static func handleMessage(
        _ data: Data,
        fd: Int32,
        sendFrame: @escaping @Sendable (Data) -> Void,
        subs: ConnectionSubscriptions,
        rpc: @escaping @Sendable (Data) async throws -> Data,
        sub: @escaping @Sendable (String, [String: JSONValue]) -> AsyncStream<Data>
    ) {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let op = raw["op"] as? String ?? "rpc"

        switch op {
        case "subscribe":
            guard let topic = raw["topic"] as? String,
                  let subID = raw["subID"]  as? String else { return }
            let params = parseParams(raw["params"])
            let stream = sub(topic, params)
            let task = Task.detached {
                for await frame in stream {
                    sendFrame(frame)
                    if Task.isCancelled { break }
                }
            }
            subs.add(subID: subID, task: task)

        case "unsubscribe":
            guard let subID = raw["subID"] as? String else { return }
            subs.cancel(subID: subID)
            let done = frame(["subID": subID, "type": "done"])
            sendFrame(done)

        default:
            // Regular RPC — response box bridges async → DispatchQueue
            let box = FrameBox()
            let sem = DispatchSemaphore(value: 0)
            Task.detached {
                do { box.data = try await rpc(data) }
                catch { box.data = Data(#"{"success":false,"error":{"code":5,"message":"internal error"}}"#.utf8) }
                sem.signal()
            }
            DispatchQueue.global(qos: .userInteractive).async {
                sem.wait()
                sendFrame(box.data)
            }
        }
    }

    private static func parseParams(_ raw: Any?) -> [String: JSONValue] {
        guard let dict = raw as? [String: Any] else { return [:] }
        return dict.compactMapValues { val -> JSONValue? in
            if let s = val as? String  { return .string(s) }
            if let i = val as? Int     { return .int(i) }
            if let d = val as? Double  { return .double(d) }
            if let b = val as? Bool    { return .bool(b) }
            return nil
        }
    }

    private static func frame(_ dict: [String: String]) -> Data {
        let data = (try? JSONEncoder().encode(dict)) ?? Data()
        return MessageFraming.frame(data)
    }
}

// MARK: - Supporting types

private final class ConnectionSubscriptions: @unchecked Sendable {
    private var tasks: [String: Task<Void, Never>] = [:]
    private let lock = NSLock()
    func add(subID: String, task: Task<Void, Never>) {
        lock.withLock { tasks[subID] = task }
    }
    func cancel(subID: String) {
        lock.withLock { tasks[subID]?.cancel(); tasks.removeValue(forKey: subID) }
    }
    func cancelAll() {
        lock.withLock { tasks.values.forEach { $0.cancel() }; tasks.removeAll() }
    }
}

private final class FrameBox: @unchecked Sendable {
    var data: Data = Data()
}

public enum SocketError: Error, Sendable {
    case createFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case disconnected
}
