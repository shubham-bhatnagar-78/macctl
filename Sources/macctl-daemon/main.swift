import Foundation
import MacCtlKit
import Logging

LoggingSystem.bootstrap(StreamLogHandler.standardOutput)
let logger = Logger(label: "macctl.daemon")

// Actor instances — one per subsystem, shared for daemon lifetime
let daemonLifecycle = DaemonLifecycle()
let axActor         = AXActor()
let inputActor      = InputActor()
let keyboardActor   = KeyboardActor()
let lifecycleActor  = AppLifecycleActor()
let captureActor    = CaptureActor()

await daemonLifecycle.start()

// Pre-warm bundle URLs for frequently-used Apple apps
let appleApps = [
    "com.apple.finder", "com.apple.Safari", "com.apple.Notes", "com.apple.mail",
    "com.apple.iCal", "com.apple.reminders", "com.apple.Terminal", "com.apple.TextEdit",
    "com.apple.dt.Xcode", "com.apple.systempreferences",
]
await lifecycleActor.preResolveBundleURLs(for: appleApps)

let sessionID = daemonLifecycle.sessionID
let server = SocketServer()

await server.setMessageHandler { data in
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
        let resultData = try await dispatch(
            method: request.method,
            params: request.params ?? [:],
            ax: axActor, input: inputActor, keyboard: keyboardActor,
            lifecycle: lifecycleActor, capture: captureActor,
            sessionID: sessionID
        )
        let durationMs = Date().timeIntervalSince(start) * 1000
        let layer = resultData["layer"]?.stringValue ?? "unknown"
        var data = resultData
        data.removeValue(forKey: "layer")
        data.removeValue(forKey: "sessionID")
        data.removeValue(forKey: "daemonVersion")
        let payload: [String: JSONValue] = [
            "jsonrpc": .string("2.0"),
            "id": .string(request.id),
            "success": .bool(true),
            "data": .object(data),
            "meta": .object([
                "durationMs": .double(durationMs),
                "layer": .string(layer),
                "sessionID": .string(sessionID),
                "daemonVersion": .string("1.0.0"),
                "retries": .int(0),
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
}

try await server.start()
logger.info("macctl-daemon ready. Socket: \(SocketServer.defaultSocketPath)")

// Run forever
try await Task.sleep(for: .seconds(Double.infinity))
