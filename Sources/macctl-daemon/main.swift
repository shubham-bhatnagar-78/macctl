import Foundation
import MacCtlKit
import Logging

LoggingSystem.bootstrap(StreamLogHandler.standardOutput)
let logger = Logger(label: "macctl.daemon")

// Actor instances — one per subsystem, shared for daemon lifetime
let daemonLifecycle  = DaemonLifecycle()
let axActor          = AXActor()
let inputActor       = InputActor()
let keyboardActor    = KeyboardActor()
let lifecycleActor   = AppLifecycleActor()
let captureActor     = CaptureActor()
let systemStateActor = SystemStateActor()
let powerActor       = PowerActor()
let clipboardActor   = ClipboardActor()
let networkActor     = NetworkActor()
let defaultsActor    = DefaultsActor()
let shellActor       = ShellActor()
let fileActor        = FileActor()
let eventKitActor    = EventKitActor()
let contactsActor    = ContactsActor()

await daemonLifecycle.start()

// Register all Apple app adapters (O(59), ~2ms)
await AppleAdapterRegistry.registerAll()

// Pre-warm bundle URLs for frequently-used Apple apps
let appleApps = [
    "com.apple.finder", "com.apple.Safari", "com.apple.Notes", "com.apple.mail",
    "com.apple.iCal", "com.apple.reminders", "com.apple.Terminal", "com.apple.TextEdit",
    "com.apple.dt.Xcode", "com.apple.systempreferences",
]
await lifecycleActor.preResolveBundleURLs(for: appleApps)

let sessionID = daemonLifecycle.sessionID

// Build middleware pipeline: logging (outermost) → dry-run → dispatch (base)
let isDryRun = CommandLine.arguments.contains("--dry-run")
let middlewarePipeline = buildMiddlewareChain(
    middlewares: [loggingMiddleware, makeDryRunMiddleware(dryRun: isDryRun)],
    base: { method, params in
        try await dispatch(
            method: method, params: params,
            ax: axActor, input: inputActor, keyboard: keyboardActor,
            lifecycle: lifecycleActor, capture: captureActor,
            systemState: systemStateActor, power: powerActor,
            clipboard: clipboardActor, network: networkActor, defaults: defaultsActor,
            shell: shellActor, file: fileActor,
            eventKit: eventKitActor, contacts: contactsActor,
            sessionID: sessionID
        )
    }
)

let server = SocketServer(rpc: { data in
    guard let request = try? JSONDecoder().decode(RPCRequest.self, from: data) else {
        let errPayload: [String: JSONValue] = [
            "jsonrpc": .string("2.0"), "id": .string("?"),
            "success": .bool(false),
            "error": .object(["code": .int(5), "message": .string("Invalid JSON-RPC request")])
        ]
        return try! JSONEncoder().encode(errPayload)
    }

    let start = Date()
    do {
        let resultData = try await middlewarePipeline(request.method, request.params ?? [:])
        let durationMs = Date().timeIntervalSince(start) * 1000
        let layer = resultData["_layer"]?.stringValue ?? "unknown"
        let retries = resultData["_retries"]?.intValue ?? 0
        var cleanData = resultData
        cleanData.removeValue(forKey: "_layer")
        cleanData.removeValue(forKey: "_retries")
        let payload: [String: JSONValue] = [
            "jsonrpc": .string("2.0"),
            "id": .string(request.id),
            "success": .bool(true),
            "data": .object(cleanData),
            "meta": .object([
                "durationMs": .double(durationMs),
                "layer": .string(layer),
                "sessionID": .string(sessionID),
                "daemonVersion": .string("1.0.0"),
                "retries": .int(retries),
            ])
        ]
        return try JSONEncoder().encode(payload)
    } catch let rpcError as RPCError {
        let payload: [String: JSONValue] = [
            "jsonrpc": .string("2.0"),
            "id": .string(request.id),
            "success": .bool(false),
            "error": .object([
                "code": .int(rpcError.code),
                "message": .string(rpcError.message),
            ])
        ]
        return try! JSONEncoder().encode(payload)
    } catch {
        let payload: [String: JSONValue] = [
            "jsonrpc": .string("2.0"),
            "id": .string(request.id),
            "success": .bool(false),
            "error": .object(["code": .int(5), "message": .string("\(error)")])
        ]
        return try! JSONEncoder().encode(payload)
    }
}, subscribe: { topic, params in
    StreamManager.stream(for: topic, params: params)
})

try server.start()
logger.info("macctl-daemon ready. Socket: \(SocketServer.defaultSocketPath)")

// Keep alive until SIGTERM
try await Task.sleep(nanoseconds: .max)
