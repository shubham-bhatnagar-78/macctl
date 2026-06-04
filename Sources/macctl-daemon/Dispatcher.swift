import Foundation
import MacCtlKit
@preconcurrency import ApplicationServices

/// Routes incoming JSON-RPC method calls to the appropriate actor.
/// Smart text routing lives here: AX setValue → paste → CGEvent sequence.
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

    func meta(_ layer: String) -> [String: JSONValue] {
        ["layer": .string(layer), "sessionID": .string(sessionID), "daemonVersion": .string("1.0.0")]
    }

    switch method {

    // MARK: - app.*

    case "app.launch":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("missing bundleID")
        }
        let background = params["background"] == .bool(true)
        let pid = try await lifecycle.launch(bid, background: background)
        return ["pid": .int(Int(pid))]

    case "app.quit":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("missing bundleID")
        }
        let force = params["force"] == .bool(true)
        await lifecycle.quit(bid, force: force)
        return [:]

    case "app.hide":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("missing bundleID")
        }
        try await lifecycle.hide(bid)
        return [:]

    case "app.show":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("missing bundleID")
        }
        try await lifecycle.show(bid)
        return [:]


    case "app.list":
        let apps = await lifecycle.listRunning()
        let list: [JSONValue] = apps.map { app in
            .object([
                "bundleID": .string(app.bundleID),
                "name": .string(app.name),
                "pid": .int(Int(app.pid)),
                "isActive": .bool(app.isActive),
            ])
        }
        return ["apps": .array(list)]

    // MARK: - key

    case "key":
        guard case .string(let bid)   = params["bundleID"],
              case .string(let combo) = params["combo"]
        else { throw RPCError.operationFailed("key requires bundleID + combo") }

        guard let pid = await lifecycle.pid(for: bid) else {
            throw RPCError.appNotRunning(bid)
        }
        // Layer 0: builtin shortcut registry (O(1), 99.9% reliable)
        if try await keyboard.postBuiltin(action: combo, bundleID: bid, pid: pid) {
            return meta("keyboard-builtin")
        }
        // Layer 1: parse combo string
        let parsed = KeyboardActor.parseCombo(combo)
        try await keyboard.post(combo: parsed, to: pid)
        return meta("keyboard")

    // MARK: - type

    case "type":
        guard case .string(let bid)  = params["bundleID"],
              case .string(let text) = params["text"]
        else { throw RPCError.operationFailed("type requires bundleID + text") }

        guard let pid = await lifecycle.pid(for: bid) else {
            throw RPCError.appNotRunning(bid)
        }

        // Smart routing: AX setValue → paste → CGEvent sequence
        if case .string(let query) = params["query"] {
            let axApp = await ax.appElement(pid: pid)
            if let elementID = await ax.findElementID(query: query, in: axApp) {
                if await ax.isSettable(id: elementID, attribute: kAXValueAttribute) {
                    try await ax.setValue(text, forID: elementID)
                    return meta("ax-setvalue")
                }
            }
        }
        if text.count > 20 {
            try await input.pasteText(text, pid: pid)
            return meta("input-paste")
        }
        try await input.typeViaEvents(text, pid: pid)
        return meta("input-cgevent")

    // MARK: - click

    case "click":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("click requires bundleID")
        }
        guard let pid = await lifecycle.pid(for: bid) else {
            throw RPCError.appNotRunning(bid)
        }

        // AX element click
        if case .string(let query) = params["query"] {
            let axApp = await ax.appElement(pid: pid)
            guard let elementID = await ax.findElementID(query: query, in: axApp) else {
                throw RPCError.elementNotFound(query, app: bid)
            }
            try await ax.press(id: elementID)
            return meta("ax-press")
        }

        // Coordinate click
        if case .double(let x) = params["x"], case .double(let y) = params["y"] {
            try await input.click(at: CGPoint(x: x, y: y), pid: pid)
            return meta("input-click")
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
            var obj: [String: JSONValue] = [
                "id": .string(el.id),
                "role": .string(el.role),
                "title": .string(el.title),
            ]
            if let f = el.frame {
                obj["frame"] = .object([
                    "x": .double(f.origin.x), "y": .double(f.origin.y),
                    "w": .double(f.size.width), "h": .double(f.size.height),
                ])
            }
            return .object(obj)
        }
        return ["elements": .array(list), "count": .int(list.count)]

    // MARK: - screenshot

    case "screenshot":
        let bundleID: String?
        if case .string(let b) = params["bundleID"] { bundleID = b } else { bundleID = nil }
        let path = try await capture.screenshot(app: bundleID)
        return ["path": .string(path.path)]

    default:
        throw RPCError(code: 5, message: "Unknown method: \(method)")
    }
}
