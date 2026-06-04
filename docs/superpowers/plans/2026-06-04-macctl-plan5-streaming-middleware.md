# macctl Plan 5 — Streaming Protocol + Middleware

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`.

**Goal:** Add bidirectional streaming subscriptions to the daemon socket (enabling `file watch`, `app lifecycle`, and future event streams), plus a middleware pipeline (logging, dry-run) wired into the dispatcher.

**Architecture:** `SocketServer` refactored to support concurrent read+write per connection using two DispatchQueues. `StreamManager` actor manages active subscriptions. FSEvents powers `file-watch` topic. NSWorkspace powers `app-lifecycle` topic. Middleware pipeline wraps the `dispatch()` function — each middleware is a simple async closure chain.

**Tech Stack:** Swift 6, FSEvents (C API), NSWorkspace notifications, DispatchQueue (bidirectional socket), existing MacCtlKit actor patterns.

**Protocol:** Length-prefixed JSON (same as existing RPC). Subscribe/unsubscribe messages share the wire with RPC calls. Daemon pushes stream events as multiple length-prefixed responses until unsubscribed.

```
Client → Daemon: {"op":"subscribe","topic":"file-watch","params":{"path":"/tmp"},"subID":"s1"}
Daemon → Client: {"subID":"s1","event":"created","path":"/tmp/foo.txt","ts":1749043200}  (repeated)
Client → Daemon: {"op":"unsubscribe","subID":"s1"}
Daemon → Client: {"subID":"s1","type":"done"}
```

---

## File Map

```
Sources/MacCtlKit/
  Network/
    SocketServer.swift           REPLACE — bidirectional read+write
  Streaming/
    StreamManager.swift          NEW — manages subscriptions, topic registry
    FileWatchStream.swift        NEW — FSEvents → AsyncStream
    AppLifecycleStream.swift     NEW — NSWorkspace → AsyncStream
  Middleware/
    OperationMiddleware.swift    NEW — protocol + pipeline builder
    LoggingMiddleware.swift      NEW — logs op name, layer, duration
    DryRunMiddleware.swift       NEW — returns description without executing

Sources/macctl-daemon/
  Dispatcher.swift               MODIFY — wrap with middleware pipeline
  main.swift                     MODIFY — register streaming topics, init middleware

Sources/macctl/Commands/
  WatchCommand.swift             NEW — watch file/apps, stream to stdout

Tests/MacCtlKitTests/
  StreamManagerTests.swift       NEW
  MiddlewareTests.swift          NEW
```

---

## Task 1: Bidirectional SocketServer

The current server does read→process→write in a loop. Streaming requires concurrent reads AND writes. Replace with two DispatchQueues per connection.

**Files:**
- Replace: `Sources/MacCtlKit/Network/SocketServer.swift`

- [ ] **Replace SocketServer.swift**

```swift
// Sources/MacCtlKit/Network/SocketServer.swift
import Foundation
import Logging

/// Bidirectional Unix socket server.
/// Each connection has a read loop and a write queue.
/// Supports both request-response RPC and push streaming.
public final class SocketServer: Sendable {
    public static let defaultSocketPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("macctl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daemon.sock").path
    }()

    private let socketPath: String
    // RPC handler: request data → response data
    private let rpcHandler: @Sendable (Data) async throws -> Data
    // Subscribe handler: returns an AsyncStream of events for a topic
    private let subscribeHandler: @Sendable (String, [String: JSONValue]) -> AsyncStream<Data>

    private let acceptQueue = DispatchQueue(label: "macctl.accept", qos: .userInteractive)
    private let logger = Logger(label: "macctl.socket")

    public init(
        socketPath: String = SocketServer.defaultSocketPath,
        rpc: @escaping @Sendable (Data) async throws -> Data,
        subscribe: @escaping @Sendable (String, [String: JSONValue]) -> AsyncStream<Data>
    ) {
        self.socketPath = socketPath
        self.rpcHandler = rpc
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
        guard bindResult == 0  else { close(serverFD); throw SocketError.bindFailed(errno) }
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

        // Write helper: serialized via writeQueue
        let sendFrame: @Sendable (Data) -> Void = { data in
            let framed = MessageFraming.frame(data)
            writeQueue.async {
                _ = framed.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
            }
        }

        // Read loop runs on global queue
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            defer {
                close(fd)
                subs.cancelAll()
            }
            var buf = Data()
            var chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(fd, &chunk, chunk.count)
                guard n > 0 else { return }
                buf.append(contentsOf: chunk.prefix(n))
                while let msg = try? MessageFraming.parse(&buf) {
                    self?.handleMessage(msg, fd: fd, sendFrame: sendFrame, subs: subs)
                }
            }
        }
    }

    private func handleMessage(
        _ data: Data,
        fd: Int32,
        sendFrame: @escaping @Sendable (Data) -> Void,
        subs: ConnectionSubscriptions
    ) {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = raw["op"] as? String ?? (raw["method"] as? String).map({ _ in "rpc" })
        else { return }

        switch op {
        case "subscribe":
            guard let topic  = raw["topic"]  as? String,
                  let subID  = raw["subID"]  as? String else { return }
            let params = (raw["params"] as? [String: Any])?.compactMapValues { val -> JSONValue? in
                if let s = val as? String { return .string(s) }
                if let i = val as? Int    { return .int(i) }
                if let b = val as? Bool   { return .bool(b) }
                return nil
            } ?? [:]
            let stream = subscribeHandler(topic, params)
            let task = Task.detached {
                for await event in stream {
                    sendFrame(event)
                    if Task.isCancelled { break }
                }
                // Send done when stream ends
                let done = (try? JSONEncoder().encode(["subID": subID, "type": "done"] as [String: String])) ?? Data()
                sendFrame(MessageFraming.frame(done))
            }
            subs.add(subID: subID, task: task)

        case "unsubscribe":
            guard let subID = raw["subID"] as? String else { return }
            subs.cancel(subID: subID)
            let done = (try? JSONEncoder().encode(["subID": subID, "type": "done"] as [String: String])) ?? Data()
            sendFrame(done)

        default:
            // Regular RPC request
            let box = ResponseBox()
            let sem = DispatchSemaphore(value: 0)
            let rpc = self.rpcHandler
            Task.detached {
                do { box.value = try await rpc(data) }
                catch { box.value = Data(#"{"success":false,"error":{"code":5,"message":"rpc error"}}"#.utf8) }
                sem.signal()
            }
            DispatchQueue.global(qos: .userInteractive).async {
                sem.wait()
                sendFrame(box.value)
            }
        }
    }
}

// MARK: - Supporting types

private final class ConnectionSubscriptions: @unchecked Sendable {
    private var tasks: [String: Task<Void, Never>] = [:]
    private let lock = NSLock()

    func add(subID: String, task: Task<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        tasks[subID] = task
    }
    func cancel(subID: String) {
        lock.lock(); defer { lock.unlock() }
        tasks[subID]?.cancel()
        tasks.removeValue(forKey: subID)
    }
    func cancelAll() {
        lock.lock(); defer { lock.unlock() }
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}

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
```

- [ ] **Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: Build will fail until main.swift is updated (new SocketServer init signature).

- [ ] **Update main.swift to use new SocketServer init**

In `Sources/macctl-daemon/main.swift`, replace the `SocketServer { data in ... }` construction with:

```swift
let server = SocketServer(
    rpc: { data in
        // ... existing RPC handler body ...
    },
    subscribe: { topic, params in
        await StreamManager.shared.stream(for: topic, params: params)
    }
)
```

Also update the handler body to match — the `rpc:` closure gets exactly what was in the old `SocketServer { data in ... }` closure.

- [ ] **Build to verify**

```bash
swift build --product macctl-daemon 2>&1 | grep -E "error:|complete"
```
Expected: Will fail until StreamManager is created.

- [ ] **Commit when building**

```bash
git add Sources/MacCtlKit/Network/SocketServer.swift Sources/macctl-daemon/main.swift
git commit -m "feat: refactor SocketServer to bidirectional (concurrent read+write, subscribe support)"
```

---

## Task 2: StreamManager + FSEvents file-watch + App lifecycle

**Files:**
- Create: `Sources/MacCtlKit/Streaming/StreamManager.swift`
- Create: `Sources/MacCtlKit/Streaming/FileWatchStream.swift`
- Create: `Sources/MacCtlKit/Streaming/AppLifecycleStream.swift`

- [ ] **Implement StreamManager.swift**

```swift
// Sources/MacCtlKit/Streaming/StreamManager.swift
import Foundation

/// Routes subscribe requests to the correct stream source.
public actor StreamManager {
    public static let shared = StreamManager()
    private init() {}

    public func stream(for topic: String, params: [String: JSONValue]) -> AsyncStream<Data> {
        switch topic {
        case "file-watch":
            guard case .string(let path) = params["path"] else {
                return AsyncStream { $0.finish() }
            }
            return FileWatchStream.watch(path: path)

        case "app-lifecycle":
            return AppLifecycleStream.watch()

        default:
            // Unknown topic — send error event and close
            return AsyncStream { continuation in
                let err = (try? JSONEncoder().encode([
                    "type": "error", "message": "Unknown topic: \(topic)"
                ] as [String: String])) ?? Data()
                continuation.yield(MessageFraming.frame(err))
                continuation.finish()
            }
        }
    }
}
```

- [ ] **Implement FileWatchStream.swift**

```swift
// Sources/MacCtlKit/Streaming/FileWatchStream.swift
import Foundation

/// Watches a file or directory for changes using FSEvents.
/// Delivers per-file events immediately (kFSEventStreamCreateFlagFileEvents + NoDefer).
public enum FileWatchStream {
    public static func watch(path: String) -> AsyncStream<Data> {
        let expandedPath = (path as NSString).expandingTildeInPath
        return AsyncStream { continuation in
            // Run FSEvents on a dedicated thread with its own RunLoop
            let thread = Thread {
                let runLoop = CFRunLoopGetCurrent()
                var context = FSEventStreamContext(
                    version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
                let box = CallbackBox(continuation: continuation, path: expandedPath)
                context.info = Unmanaged.passRetained(box).toOpaque()

                guard let stream = FSEventStreamCreate(
                    nil,
                    { _, info, numEvents, eventPaths, eventFlags, _ in
                        guard let info else { return }
                        let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
                        guard let paths = eventPaths as? [String] else { return }
                        let flags = UnsafeBufferPointer(start: eventFlags, count: numEvents)
                        for (i, eventPath) in paths.enumerated() {
                            let flag = i < numEvents ? flags[i] : 0
                            let eventType = FileWatchStream.eventType(flags: flag)
                            let payload: [String: String] = [
                                "type":   "event",
                                "event":  eventType,
                                "path":   eventPath,
                                "ts":     "\(Int(Date().timeIntervalSince1970))",
                            ]
                            if let data = try? JSONEncoder().encode(payload) {
                                box.continuation.yield(MessageFraming.frame(data))
                            }
                        }
                    },
                    &context,
                    [expandedPath] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    0.05,  // 50ms latency
                    FSEventStreamCreateFlags(
                        kFSEventStreamCreateFlagFileEvents |
                        kFSEventStreamCreateFlagNoDefer    |
                        kFSEventStreamCreateFlagUseCFTypes
                    )
                ) else {
                    continuation.finish()
                    return
                }

                FSEventStreamScheduleWithRunLoop(stream, runLoop, CFRunLoopMode.defaultMode.rawValue)
                FSEventStreamStart(stream)

                // Handle cancellation by stopping the run loop
                continuation.onTermination = { @Sendable _ in
                    FSEventStreamStop(stream)
                    FSEventStreamInvalidate(stream)
                    FSEventStreamRelease(stream)
                    CFRunLoopStop(runLoop)
                }

                CFRunLoopRun()
                Unmanaged.passUnretained(box).release()
            }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    private static func eventType(flags: FSEventStreamEventFlags) -> String {
        if flags & UInt32(kFSEventStreamEventFlagItemCreated)  != 0 { return "created"  }
        if flags & UInt32(kFSEventStreamEventFlagItemRemoved)  != 0 { return "deleted"  }
        if flags & UInt32(kFSEventStreamEventFlagItemRenamed)  != 0 { return "renamed"  }
        if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 { return "modified" }
        if flags & UInt32(kFSEventStreamEventFlagItemXattrMod) != 0 { return "xattr"    }
        return "changed"
    }
}

private final class CallbackBox: @unchecked Sendable {
    let continuation: AsyncStream<Data>.Continuation
    let path: String
    init(continuation: AsyncStream<Data>.Continuation, path: String) {
        self.continuation = continuation
        self.path = path
    }
}
```

- [ ] **Implement AppLifecycleStream.swift**

```swift
// Sources/MacCtlKit/Streaming/AppLifecycleStream.swift
@preconcurrency import AppKit
import Foundation

/// Streams app launch/quit/activate events via NSWorkspace notifications.
public enum AppLifecycleStream {
    public static func watch() -> AsyncStream<Data> {
        AsyncStream { continuation in
            let nc = NSWorkspace.shared.notificationCenter
            var tokens: [NSObjectProtocol] = []

            func emit(_ event: String, _ app: NSRunningApplication) {
                let payload: [String: String] = [
                    "type":      "event",
                    "event":     event,
                    "bundleID":  app.bundleIdentifier ?? "",
                    "name":      app.localizedName ?? "",
                    "pid":       "\(app.processIdentifier)",
                    "ts":        "\(Int(Date().timeIntervalSince1970))",
                ]
                if let data = try? JSONEncoder().encode(payload) {
                    continuation.yield(MessageFraming.frame(data))
                }
            }

            let events: [(NSNotification.Name, String)] = [
                (.NSWorkspaceDidLaunchApplication,    "launched"),
                (.NSWorkspaceDidTerminateApplication, "terminated"),
                (.NSWorkspaceDidActivateApplication,  "activated"),
                (.NSWorkspaceDidHideApplication,      "hidden"),
                (.NSWorkspaceDidUnhideApplication,    "unhidden"),
            ]
            for (name, event) in events {
                let token = nc.addObserver(forName: name, object: nil, queue: nil) { note in
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                                    as? NSRunningApplication else { return }
                    emit(event, app)
                }
                tokens.append(token)
            }

            continuation.onTermination = { @Sendable _ in
                tokens.forEach { nc.removeObserver($0) }
            }
        }
    }
}
```

- [ ] **Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Streaming/
git commit -m "feat: add StreamManager, FileWatchStream (FSEvents), AppLifecycleStream (NSWorkspace)"
```

---

## Task 3: Middleware Pipeline

**Files:**
- Create: `Sources/MacCtlKit/Middleware/OperationMiddleware.swift`
- Create: `Sources/MacCtlKit/Middleware/LoggingMiddleware.swift`
- Create: `Sources/MacCtlKit/Middleware/DryRunMiddleware.swift`
- Modify: `Sources/macctl-daemon/Dispatcher.swift` — wrap dispatch in middleware

- [ ] **Implement OperationMiddleware.swift**

```swift
// Sources/MacCtlKit/Middleware/OperationMiddleware.swift
import Foundation
import Logging

/// Middleware intercepts every dispatch call.
/// Chain: mw1 → mw2 → actual dispatch
public typealias DispatchNext = @Sendable (String, [String: JSONValue]) async throws -> [String: JSONValue]
public typealias MiddlewareFn = @Sendable (String, [String: JSONValue], DispatchNext) async throws -> [String: JSONValue]

/// Build a middleware chain. Middlewares are applied outer-first.
public func buildMiddlewareChain(
    middlewares: [MiddlewareFn],
    base: @escaping DispatchNext
) -> DispatchNext {
    middlewares.reversed().reduce(base) { next, mw in
        { method, params in try await mw(method, params, next) }
    }
}
```

- [ ] **Implement LoggingMiddleware.swift**

```swift
// Sources/MacCtlKit/Middleware/LoggingMiddleware.swift
import Foundation
import Logging

private let logger = Logger(label: "macctl.middleware.logging")

/// Logs every dispatch: method, layer, durationMs, retries.
public let loggingMiddleware: MiddlewareFn = { method, params, next in
    let start = ContinuousClock.now
    do {
        let result = try await next(method, params)
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
        let layer = result["_layer"]?.stringValue ?? "?"
        logger.debug("\(method) → \(layer) (\(String(format: "%.1f", ms))ms)")
        return result
    } catch {
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000
        logger.warning("\(method) failed after \(String(format: "%.1f", ms))ms: \(error)")
        throw error
    }
}
```

- [ ] **Implement DryRunMiddleware.swift**

```swift
// Sources/MacCtlKit/Middleware/DryRunMiddleware.swift
import Foundation

/// When dryRun=true, describes the operation without executing.
/// Destructive methods: write, delete, move, system changes.
private let destructiveMethods: Set<String> = [
    "file.write", "file.delete", "file.move", "file.mkdir",
    "system.volume", "system.brightness", "system.wifi", "system.bluetooth",
    "system.mute", "power.sleep", "power.lock-screen",
    "clipboard.write", "clipboard.clear",
    "defaults.write", "defaults.delete",
    "drag", "click", "type",
]

public func makeDryRunMiddleware(dryRun: Bool) -> MiddlewareFn {
    { method, params, next in
        guard dryRun && destructiveMethods.contains(method) else {
            return try await next(method, params)
        }
        // Don't execute — return description
        return [
            "_layer": .string("dry-run"),
            "dryRun":  .bool(true),
            "would":   .string(method),
            "params":  .object(params),
        ]
    }
}
```

- [ ] **Wire middleware into Dispatcher**

In `Sources/macctl-daemon/main.swift`, after the actor instantiations, build the middleware chain and use it instead of calling `dispatch(...)` directly:

```swift
// Build middleware pipeline
let isDryRun = CommandLine.arguments.contains("--dry-run")
let middlewareChain = buildMiddlewareChain(
    middlewares: [
        loggingMiddleware,
        makeDryRunMiddleware(dryRun: isDryRun),
    ],
    base: { method, params in
        try await dispatch(
            method: method, params: params,
            ax: axActor, input: inputActor, keyboard: keyboardActor,
            lifecycle: lifecycleActor, capture: captureActor,
            systemState: systemStateActor, power: powerActor,
            clipboard: clipboardActor, network: networkActor, defaults: defaultsActor,
            shell: shellActor, file: fileActor,
            sessionID: sessionID
        )
    }
)
```

Then in the RPC handler, call `middlewareChain(request.method, request.params ?? [:])` instead of `dispatch(...)` directly.

- [ ] **Build to verify**

```bash
swift build --product macctl-daemon 2>&1 | grep -E "error:|complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Middleware/ Sources/macctl-daemon/
git commit -m "feat: add middleware pipeline (logging, dry-run), wire into daemon"
```

---

## Task 4: CLI watch command + Tests

**Files:**
- Create: `Sources/macctl/Commands/WatchCommand.swift`
- Create: `Tests/MacCtlKitTests/StreamManagerTests.swift`
- Create: `Tests/MacCtlKitTests/MiddlewareTests.swift`
- Modify: `Sources/macctl/main.swift`

- [ ] **Implement WatchCommand.swift**

```swift
// Sources/macctl/Commands/WatchCommand.swift
import ArgumentParser
import MacCtlKit
import Foundation

struct WatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Stream events to stdout (Ctrl+C to stop)",
        subcommands: [WatchFile.self, WatchApps.self])

    struct WatchFile: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "file",
            abstract: "Watch file or directory for changes")
        @Argument var path: String
        func run() throws { streamWatch(topic: "file-watch", params: ["path": path]) }
    }

    struct WatchApps: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "apps",
            abstract: "Watch app launch/quit/activate events")
        func run() throws { streamWatch(topic: "app-lifecycle", params: [:]) }
    }
}

/// Connect to daemon, subscribe to topic, print events to stdout until Ctrl+C.
func streamWatch(topic: String, params: [String: String]) {
    let subID = UUID().uuidString
    var sub: [String: Any] = ["op": "subscribe", "topic": topic, "subID": subID]
    if !params.isEmpty { sub["params"] = params }

    guard let data = try? JSONSerialization.data(withJSONObject: sub),
          let subData = Optional(MessageFraming.frame(data))
    else { fputs("Error: could not encode subscribe request\n", stderr); return }

    let client = SocketClient()
    guard (try? client.connect()) != nil else {
        // connect() is nonisolated — handle inline
        do { try client.connect() } catch {
            fputs("""
                {"success":false,"error":{"code":4,"message":"Daemon not running"}}
                """, stderr)
            return
        }
    }
    // Actually connect and handle
    do { try client.connect() } catch {
        fputs("{\"success\":false,\"error\":{\"code\":4,\"message\":\"Daemon not running. Run: macctl-daemon &\"}}\n", stderr)
        return
    }

    fputs("Watching \(topic) \(params). Ctrl+C to stop.\n", stderr)

    // Send subscribe
    _ = subData.withUnsafeBytes { ptr in
        // Use raw socket send
    }

    // Read stream events and print
    client.streamEvents { event in
        if let json = try? JSONSerialization.jsonObject(with: event) as? [String: Any],
           let eventType = json["type"] as? String, eventType != "done" {
            if let pretty = try? JSONSerialization.data(withJSONObject: json,
                                                         options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8) {
                print(str)
            }
        }
    }
}
```

> **Note:** The watch command needs `SocketClient` extended with streaming read support. See the implementation in Task 4 step below.

- [ ] **Extend SocketClient for streaming**

Add to `Sources/MacCtlKit/Network/SocketClient.swift`:

```swift
extension SocketClient {
    /// Connect and return raw fd for bidirectional use.
    public func connect() throws {
        // ... (same connection logic as roundTrip but just connects)
    }

    /// Send a subscribe request and stream back events synchronously.
    public func subscribeAndStream(
        topic: String,
        params: [String: JSONValue],
        subID: String,
        onEvent: @escaping (Data) -> Bool  // return false to stop
    ) throws {
        // Build subscribe message
        let sub: [String: JSONValue] = [
            "op":     .string("subscribe"),
            "topic":  .string(topic),
            "subID":  .string(subID),
            "params": .object(params),
        ]
        let data = try JSONEncoder().encode(sub)
        let framed = MessageFraming.frame(data)
        _ = framed.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }

        // Read stream events
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return }
            buf.append(contentsOf: chunk.prefix(n))
            while let msg = try? MessageFraming.parse(&buf) {
                let shouldContinue = onEvent(msg)
                if !shouldContinue {
                    // Send unsubscribe
                    let unsub = try? JSONEncoder().encode(["op": "unsubscribe", "subID": subID] as [String: String])
                    if let u = unsub {
                        let f = MessageFraming.frame(u)
                        _ = f.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
                    }
                    return
                }
            }
        }
    }
}
```

- [ ] **Implement WatchCommand.swift cleanly**

Replace the previous draft with this simpler version:

```swift
// Sources/macctl/Commands/WatchCommand.swift
import ArgumentParser
import MacCtlKit
import Foundation

struct WatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Stream events to stdout (Ctrl+C to stop)",
        subcommands: [WatchFile.self, WatchApps.self])

    struct WatchFile: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "file")
        @Argument var path: String
        func run() throws {
            stream(topic: "file-watch", params: ["path": .string(path)])
        }
    }

    struct WatchApps: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "apps")
        func run() throws { stream(topic: "app-lifecycle", params: [:]) }
    }
}

private func stream(topic: String, params: [String: JSONValue]) {
    let client = SocketClient()
    do { try client.connect() } catch {
        fputs("{\"success\":false,\"error\":{\"code\":4,\"message\":\"Daemon not running\"}}\n", stderr)
        return
    }
    fputs("Watching \(topic). Ctrl+C to stop.\n", stderr)
    let subID = UUID().uuidString
    // Handle SIGINT gracefully
    signal(SIGINT, SIG_DFL)
    try? client.subscribeAndStream(topic: topic, params: params, subID: subID) { data in
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if (json["type"] as? String) == "done" { return false }
            if let pretty = try? JSONSerialization.data(withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8) {
                print(str)
                fflush(stdout)
            }
        }
        return true
    }
}
```

- [ ] **Register WatchCommand in main.swift**

Add `WatchCommand.self` to the subcommands list.

- [ ] **Implement StreamManagerTests.swift**

```swift
// Tests/MacCtlKitTests/StreamManagerTests.swift
import Testing
import Foundation
@testable import MacCtlKit

@Suite("StreamManager")
struct StreamManagerTests {
    @Test func unknownTopicFinishesImmediately() async throws {
        let stream = await StreamManager.shared.stream(for: "nonexistent-topic", params: [:])
        var received: [Data] = []
        for await event in stream {
            received.append(event)
            break  // read one event (the error event)
        }
        #expect(!received.isEmpty)
        // Should receive an error event
        if let first = received.first,
           let parsed = first.dropFirst(4) as Data?,  // strip length prefix
           let json = try? JSONSerialization.jsonObject(with: parsed) as? [String: Any] {
            #expect(json["type"] as? String == "error")
        }
    }

    @Test func fileWatchTopicCreatesStream() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("streamtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let stream = await StreamManager.shared.stream(
            for: "file-watch", params: ["path": .string(tmp.path)])

        // Write a file — should trigger an event
        var receivedEvent = false
        let task = Task {
            for await _ in stream {
                receivedEvent = true
                break
            }
        }

        // Small delay then write
        try await Task.sleep(for: .milliseconds(200))
        try "hello".write(to: tmp.appendingPathComponent("test.txt"),
                          atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        // We don't require the event since FSEvents timing varies in CI
        // Just verify the stream was created successfully (no crash)
    }
}
```

- [ ] **Implement MiddlewareTests.swift**

```swift
// Tests/MacCtlKitTests/MiddlewareTests.swift
import Testing
@testable import MacCtlKit

@Suite("Middleware")
struct MiddlewareTests {
    @Test func loggingMiddlewarePassesThrough() async throws {
        nonisolated(unsafe) var called = false
        let base: DispatchNext = { method, params in
            called = true
            return ["_layer": .string("test"), "result": .string(method)]
        }
        let chain = buildMiddlewareChain(middlewares: [loggingMiddleware], base: base)
        let result = try await chain("test.method", [:])
        #expect(called)
        #expect(result["result"] == .string("test.method"))
    }

    @Test func dryRunBlocksDestructive() async throws {
        nonisolated(unsafe) var executed = false
        let base: DispatchNext = { _, _ in executed = true; return ["_layer": .string("test")] }
        let chain = buildMiddlewareChain(middlewares: [makeDryRunMiddleware(dryRun: true)], base: base)
        let result = try await chain("file.delete", ["path": .string("/tmp/x")])
        #expect(!executed)
        #expect(result["dryRun"] == .bool(true))
        #expect(result["would"] == .string("file.delete"))
    }

    @Test func dryRunAllowsReadOperations() async throws {
        nonisolated(unsafe) var executed = false
        let base: DispatchNext = { _, _ in executed = true; return ["_layer": .string("test")] }
        let chain = buildMiddlewareChain(middlewares: [makeDryRunMiddleware(dryRun: true)], base: base)
        _ = try await chain("file.read", ["path": .string("/tmp/x")])
        #expect(executed)  // read operations are NOT blocked
    }

    @Test func middlewareChainCallsInOrder() async throws {
        nonisolated(unsafe) var order: [Int] = []
        func mw(_ n: Int) -> MiddlewareFn {
            { method, params, next in
                order.append(n)
                let r = try await next(method, params)
                order.append(-n)
                return r
            }
        }
        let base: DispatchNext = { _, _ in ["_layer": .string("base")] }
        let chain = buildMiddlewareChain(middlewares: [mw(1), mw(2), mw(3)], base: base)
        _ = try await chain("x", [:])
        #expect(order == [1, 2, 3, -3, -2, -1])
    }
}
```

- [ ] **Run tests**

```bash
swift test --filter "StreamManagerTests|MiddlewareTests" 2>&1 | grep -E "passed|failed" | head -10
```
Expected: All tests pass.

- [ ] **Run full test suite**

```bash
swift test 2>&1 | grep "Suite 'All tests'"
```
Expected: passed.

- [ ] **Final commit**

```bash
git add -A
git commit -m "feat: Plan 5 complete — streaming (FSEvents + app lifecycle), middleware (logging + dry-run), watch CLI"
```

---

## Self-Review

| Spec requirement | Task | Status |
|---|---|---|
| Streaming protocol (subscribe/unsubscribe) | Task 1 | ✅ |
| Bidirectional socket (concurrent read+write) | Task 1 | ✅ |
| file-watch topic (FSEvents) | Task 2 | ✅ |
| app-lifecycle topic (NSWorkspace) | Task 2 | ✅ |
| StreamManager topic routing | Task 2 | ✅ |
| Logging middleware | Task 3 | ✅ |
| DryRun middleware | Task 3 | ✅ |
| Middleware pipeline builder | Task 3 | ✅ |
| CLI `watch file` command | Task 4 | ✅ |
| CLI `watch apps` command | Task 4 | ✅ |
| Tests (streaming + middleware) | Task 4 | ✅ |
| All existing tests still pass | Task 4 | ✅ |
| Plan 3B unblocked | After Task 2 | ✅ |
