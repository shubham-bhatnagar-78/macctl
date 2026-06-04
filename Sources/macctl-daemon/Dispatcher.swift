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
        // Smart routing with retry: AX setValue (1-2ms) → paste (3-5ms) → CGEvent (slow)
        if case .string(let query) = params["query"] {
            let eid = try? await RetryEngine.run {
                let axApp = await ax.appElement(pid: pid)
                guard let id = await ax.findElementID(query: query, in: axApp) else {
                    throw RPCError.elementNotFound(query, app: bid)
                }
                return id
            }
            if let eid, await ax.isSettable(id: eid, attribute: kAXValueAttribute) {
                try await ax.setValue(text, forID: eid)
                return layer("ax-setvalue", ["chars": .int(text.count)])
            }
        }
        if text.count > 20 {
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
            // RetryEngine: retry on element-not-found (UI may still be loading)
            let eid = try await RetryEngine.run(attempts: 3) {
                let axApp = await ax.appElement(pid: pid)
                guard let id = await ax.findElementID(query: query, in: axApp) else {
                    throw RPCError.elementNotFound(query, app: bid)
                }
                return id
            }
            try await RetryEngine.run(attempts: 2) {
                try await ax.press(id: eid)
            }
            return layer("ax-press", ["elementId": .string(eid)])
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

    default:
        throw RPCError(code: 5, message: "Unknown method: \(method)")
    }
}
