import Foundation
import MacCtlKit
@preconcurrency import ApplicationServices

/// Routes incoming JSON-RPC method calls to the appropriate actor.
/// Every return dict MUST include "_layer" — stripped in main.swift into meta.
func dispatch(
    method: String,
    params: [String: JSONValue],
    ax: AXActor,
    input: InputActor,
    keyboard: KeyboardActor,
    lifecycle: AppLifecycleActor,
    capture: CaptureActor,
    systemState: SystemStateActor,
    power: PowerActor,
    clipboard: ClipboardActor,
    network: NetworkActor,
    defaults: DefaultsActor,
    sessionID: String
) async throws -> [String: JSONValue] {

    func layer(_ name: String, _ data: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var result = data
        result["_layer"] = .string(name)
        return result
    }

    switch method {

    // MARK: - app.*

    case "app.launch":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("missing bundleID")
        }
        let background = params["background"] == .bool(true)
        let pid = try await lifecycle.launch(bid, background: background)
        return layer("lifecycle", ["pid": .int(Int(pid))])

    case "app.quit":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("missing bundleID")
        }
        await lifecycle.quit(bid, force: params["force"] == .bool(true))
        return layer("lifecycle")

    case "app.hide":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("missing bundleID")
        }
        try await lifecycle.hide(bid)
        return layer("lifecycle")

    case "app.show":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("missing bundleID")
        }
        try await lifecycle.show(bid)
        return layer("lifecycle")

    case "app.list":
        let apps = await lifecycle.listRunning()
        let list: [JSONValue] = apps.map { app in
            .object([
                "bundleID": .string(app.bundleID),
                "name": .string(app.name),
                "pid": .int(Int(app.pid)),
                "isActive": .bool(app.isActive),
                "isHidden": .bool(app.isHidden),
            ])
        }
        return layer("lifecycle", ["apps": .array(list), "count": .int(list.count)])

    // MARK: - key

    case "key":
        guard case .string(let bid)   = params["bundleID"],
              case .string(let combo) = params["combo"]
        else { throw RPCError.operationFailed("key requires bundleID + combo") }
        guard let pid = await lifecycle.pid(for: bid) else {
            throw RPCError.appNotRunning(bid)
        }
        // Layer 0: builtin shortcut registry — O(1), 99.9% reliable
        if try await keyboard.postBuiltin(action: combo, bundleID: bid, pid: pid) {
            return layer("keyboard-builtin")
        }
        // Layer 1: parse combo string "cmd+s" → KeyCombo
        try await keyboard.post(combo: KeyboardActor.parseCombo(combo), to: pid)
        return layer("keyboard-combo")

    // MARK: - type

    case "type":
        guard case .string(let bid)  = params["bundleID"],
              case .string(let text) = params["text"]
        else { throw RPCError.operationFailed("type requires bundleID + text") }
        guard let pid = await lifecycle.pid(for: bid) else {
            throw RPCError.appNotRunning(bid)
        }
        // Smart routing: AX setValue (1-2ms) → paste (12ms) → CGEvent (slow)
        // Try focused element first (fastest: no search needed)
        var settableEID: String? = await ax.focusedElementID(pid: pid)

        // If query given and focused element not settable, search by query
        if case .string(let query) = params["query"], settableEID == nil {
            let axApp = await ax.appElement(pid: pid)
            settableEID = await ax.findElementID(query: query, in: axApp)
        }

        if let eid = settableEID,
           await ax.isSettable(id: eid, attribute: kAXValueAttribute) {
            // ax.setValue is synchronous IPC — if app is busy (autosave, redraw),
            // it blocks. Fall through to paste on failure rather than hanging.
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await ax.setValue(text, forID: eid) }
                    group.addTask {
                        try await Task.sleep(for: .milliseconds(200))
                        throw RPCError.timeout("ax setValue took >200ms")
                    }
                    try await group.next()!
                    group.cancelAll()
                }
                return layer("ax-setvalue", ["chars": .int(text.count)])
            } catch {
                // App busy — fall through to paste
            }
        }
        // Paste is faster than CGEvent for any text ≥2 chars and has O(1) length scaling
        if text.count >= 2 {
            try await input.pasteText(text, pid: pid)
            return layer("input-paste", ["chars": .int(text.count)])
        }
        try await input.typeViaEvents(text, pid: pid)
        return layer("input-cgevent", ["chars": .int(text.count)])

    // MARK: - click

    case "click":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("click requires bundleID")
        }
        guard let pid = await lifecycle.pid(for: bid) else {
            throw RPCError.appNotRunning(bid)
        }
        if case .string(let query) = params["query"] {
            let waitTimeout = Duration.seconds((params["timeout"]?.doubleValue ?? 3.0))
            // WaitEngine: polls until element appears (handles loading UIs), max 3s
            let eid: String
            do {
                eid = try await WaitEngine.waitForElement(query: query, in: pid, ax: ax, timeout: waitTimeout)
            } catch {
                throw RPCError.elementNotFound(query, app: bid)
            }
            // RetryEngine: retry click (press → click → focus fallback inside ax.click)
            let pressResult = try await RetryEngine.run(attempts: 2) {
                try await ax.click(id: eid)
            }
            return layer("ax-press", ["elementId": .string(eid),
                                      "_retries": .int(pressResult.attempts - 1)])
        }
        if case .double(let x) = params["x"], case .double(let y) = params["y"] {
            try await input.click(at: CGPoint(x: x, y: y), pid: pid)
            return layer("input-click")
        }
        throw RPCError.operationFailed("click requires 'query' or 'x'+'y'")

    // MARK: - see

    case "see":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("see requires bundleID")
        }
        guard let pid = await lifecycle.pid(for: bid) else {
            throw RPCError.appNotRunning(bid)
        }
        let axApp = await ax.appElement(pid: pid)
        let elements = await ax.listElements(in: axApp)
        let list: [JSONValue] = elements.map { el in
            var obj: [String: JSONValue] = ["id": .string(el.id), "role": .string(el.role), "title": .string(el.title)]
            if let f = el.frame {
                obj["frame"] = .object(["x": .double(f.origin.x), "y": .double(f.origin.y),
                                        "w": .double(f.size.width), "h": .double(f.size.height)])
            }
            return .object(obj)
        }
        return layer("ax-tree", ["elements": .array(list), "count": .int(list.count)])

    // MARK: - screenshot

    case "screenshot":
        let bundleID: String? = { if case .string(let b) = params["bundleID"] { return b }; return nil }()
        let path = try await capture.screenshot(app: bundleID)
        return layer("screencapturekit", ["path": .string(path.path)])

    // MARK: - system.*

    case "system.status":
        let s = await systemState.status()
        return layer("native-api", [
            "volume": .double(Double(s.volume)),
            "isMuted": .bool(s.isMuted),
            "brightness": .double(Double(s.brightness)),
            "wifiEnabled": .bool(s.wifiEnabled),
            "wifiSSID": s.wifiSSID.map { .string($0) } ?? .null,
            "bluetoothEnabled": .bool(s.bluetoothEnabled),
        ])

    case "system.volume":
        if case .double(let v) = params["value"] {
            await systemState.setVolume(Float(v))
            return layer("native-api", ["volume": .double(v)])
        }
        return layer("native-api", ["volume": .double(Double(await systemState.volume()))])

    case "system.mute":
        let muted = params["muted"] == .bool(true)
        await systemState.setMuted(muted)
        return layer("native-api", ["muted": .bool(muted)])

    case "system.brightness":
        if case .double(let v) = params["value"] {
            await systemState.setBrightness(Float(v))
            return layer("native-api", ["brightness": .double(v)])
        }
        return layer("native-api", ["brightness": .double(Double(await systemState.brightness()))])

    case "system.wifi":
        if case .bool(let enabled) = params["enabled"] {
            try await systemState.setWifiEnabled(enabled)
            return layer("native-api", ["wifiEnabled": .bool(enabled)])
        }
        return layer("native-api", [
            "wifiEnabled": .bool(await systemState.wifiEnabled()),
            "ssid": await systemState.wifiSSID().map { .string($0) } ?? .null,
        ])

    case "system.bluetooth":
        if case .bool(let enabled) = params["enabled"] {
            await systemState.setBluetoothEnabled(enabled)
            return layer("native-api", ["bluetoothEnabled": .bool(enabled)])
        }
        return layer("native-api", ["bluetoothEnabled": .bool(await systemState.bluetoothEnabled())])

    // MARK: - power.*

    case "power.prevent-sleep":
        let reason = params["reason"]?.stringValue ?? "macctl automation"
        let token = try await power.preventSleep(reason: reason)
        return layer("native-api", ["token": .int(Int(token))])

    case "power.release-sleep":
        if case .int(let t) = params["token"] { await power.releaseSleep(token: SleepToken(t)) }
        return layer("native-api")

    case "power.lock-screen":
        await power.lockScreen()
        return layer("native-api")

    case "power.sleep":
        try await power.systemSleep()
        return layer("native-api")

    case "power.status":
        return layer("native-api", ["activePreventions": .int(await power.activePreventionCount())])

    // MARK: - clipboard.*

    case "clipboard.read":
        let content = await clipboard.read()
        switch content {
        case .text(let s):   return layer("native-api", ["type": .string("text"), "value": .string(s)])
        case .html(let h):   return layer("native-api", ["type": .string("html"), "value": .string(h)])
        case .files(let us): return layer("native-api", ["type": .string("files"),
            "value": .array(us.map { .string($0.path) })])
        case .rtf:           return layer("native-api", ["type": .string("rtf")])
        case .image:         return layer("native-api", ["type": .string("image")])
        case .color:         return layer("native-api", ["type": .string("color")])
        case .empty:         return layer("native-api", ["type": .string("empty")])
        }

    case "clipboard.write":
        if case .string(let html) = params["html"] {
            await clipboard.write(.html(html))
            return layer("native-api", ["written": .string("html")])
        }
        if case .string(let text) = params["text"] {
            await clipboard.writeText(text)
            return layer("native-api", ["written": .string("text")])
        }
        if case .array(let paths) = params["files"] {
            let urls = paths.compactMap { v -> URL? in
                guard case .string(let s) = v else { return nil }
                return URL(fileURLWithPath: s)
            }
            await clipboard.writeFiles(urls)
            return layer("native-api", ["written": .string("files")])
        }
        throw RPCError.operationFailed("clipboard.write requires 'text' or 'files'")

    case "clipboard.clear":
        await clipboard.clear()
        return layer("native-api")

    // MARK: - network.*

    case "network.status":
        let s = await network.status()
        return layer("native-api", [
            "isConnected":   .bool(s.isConnected),
            "isExpensive":   .bool(s.isExpensive),
            "isConstrained": .bool(s.isConstrained),
            "interfaces":    .array(s.interfaces.map { .string($0) }),
            "hasWifi":       .bool(s.hasWifi),
            "hasCellular":   .bool(s.hasCellular),
            "hasWired":      .bool(s.hasWired),
            "hasVPN":        .bool(s.hasVPN),
        ])

    case "network.resolve":
        guard case .string(let hostname) = params["hostname"] else {
            throw RPCError.operationFailed("network.resolve requires 'hostname'")
        }
        let addresses = try await network.resolve(hostname: hostname)
        return layer("native-api", [
            "hostname":  .string(hostname),
            "addresses": .array(addresses.map { .string($0) }),
        ])

    // MARK: - defaults.*

    case "defaults.read":
        guard case .string(let domain) = params["domain"],
              case .string(let key)    = params["key"]
        else { throw RPCError.operationFailed("defaults.read requires domain + key") }
        let (valStr, typeName) = await defaults.readTyped(domain: domain, key: key)
        let jsonVal: JSONValue = switch typeName {
        case "bool":   .bool(valStr == "true")
        case "int":    .int(Int(valStr) ?? 0)
        case "double": .double(Double(valStr) ?? 0)
        case "null":   .null
        default:       .string(valStr)
        }
        return layer("native-api", ["value": jsonVal, "type": .string(typeName)])

    case "defaults.write":
        guard case .string(let domain) = params["domain"],
              case .string(let key)    = params["key"]
        else { throw RPCError.operationFailed("defaults.write requires domain + key + value") }
        switch params["value"] {
        case .string(let s):  await defaults.write(domain: domain, key: key, stringValue: s)
        case .bool(let b):    await defaults.write(domain: domain, key: key, boolValue: b)
        case .int(let i):     await defaults.write(domain: domain, key: key, intValue: i)
        case .double(let d):  await defaults.write(domain: domain, key: key, doubleValue: d)
        default: throw RPCError.operationFailed("defaults.write: unsupported value type")
        }
        return layer("native-api", ["written": .bool(true)])

    case "defaults.delete":
        guard case .string(let domain) = params["domain"],
              case .string(let key)    = params["key"]
        else { throw RPCError.operationFailed("defaults.delete requires domain + key") }
        await defaults.delete(domain: domain, key: key)
        return layer("native-api")

    default:
        throw RPCError(code: 5, message: "Unknown method: \(method)")
    }
}
