@preconcurrency import AppKit
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
    shell: ShellActor,
    file: FileActor,
    eventKit: EventKitActor,
    contacts: ContactsActor,
    window: WindowActor,
    process: ProcessActor,
    spotlight: SpotlightActor,
    share: ShareActor,
    inputSource: InputSourceActor,
    screen: ScreenActor,
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
        //
        // AX setValue path: ONLY when --into query is provided.
        // focusedElementID() not used by default — it blocks >200ms on busy apps (TextEdit, etc.)
        // because AX requests process on the app's main thread.
        // For general typing, paste is always fast and always works.
        //
        // Use: macctl type "text" --into "field name" --app App  →  ax-setvalue (1-2ms)
        // Use: macctl type "text" --app App                      →  paste (12ms)
        if case .string(let query) = params["query"] {
            let result = try? await RetryEngine.run(attempts: 2) {
                let axApp = await ax.appElement(pid: pid)
                guard let id = await ax.findElementID(query: query, in: axApp) else {
                    throw RPCError.elementNotFound(query, app: bid)
                }
                return id
            }
            if let eid = result?.value,
               await ax.isSettable(id: eid, attribute: kAXValueAttribute) {
                do {
                    try await ax.setValueWithTimeout(text, forID: eid, timeoutMs: 150)
                    return layer("ax-setvalue", ["chars": .int(text.count)])
                } catch {
                    // App busy — fall through to paste
                }
            }
        }
        // Paste is always faster than CGEvent (O(1) vs O(n)) and more reliable.
        // Use paste for all text lengths. CGEvent sequence only for empty string edge case.
        if !text.isEmpty {
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
        // Fast path: click by element ID from a previous `see` call (0ms search)
        if case .string(let eid) = params["elementId"] {
            guard await ax.elementExists(id: eid) else {
                throw RPCError.elementNotFound(eid, app: "\(bid) (cache miss — run `see` first)")
            }
            let r = try await RetryEngine.run(attempts: 2) { try await ax.click(id: eid) }
            return layer("ax-press-id", ["elementId": .string(eid), "_retries": .int(r.attempts - 1)])
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
        throw RPCError.operationFailed("click requires 'query', 'elementId', or 'x'+'y'")

    // MARK: - scroll

    case "scroll":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("scroll requires bundleID")
        }
        guard let pid = await lifecycle.pid(for: bid) else {
            throw RPCError.appNotRunning(bid)
        }
        let dirStr = params["direction"]?.stringValue ?? "down"
        let direction: ScrollDirection = switch dirStr {
        case "up": .up; case "down": .down; case "left": .left; case "right": .right
        default: .down
        }
        let amount = params["amount"]?.intValue ?? 3
        try await input.scroll(direction: direction, amount: amount, pid: pid)
        return layer("input-scroll", ["direction": .string(dirStr), "amount": .int(amount)])

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

    // MARK: - shell

    case "shell":
        guard case .string(let command) = params["command"] else {
            throw RPCError.operationFailed("shell requires 'command'")
        }
        let wd = params["workingDirectory"]?.stringValue
        let timeoutSecs = params["timeout"]?.doubleValue ?? 30.0
        let result = try await shell.run(command, workingDirectory: wd,
                                         timeout: .seconds(timeoutSecs))
        return layer("shell", [
            "stdout":   .string(result.stdout),
            "stderr":   .string(result.stderr),
            "exitCode": .int(Int(result.exitCode)),
        ])

    // MARK: - drag

    case "drag":
        guard case .string(let bid) = params["bundleID"] else {
            throw RPCError.operationFailed("drag requires bundleID")
        }
        guard let pid = await lifecycle.pid(for: bid) else {
            throw RPCError.appNotRunning(bid)
        }
        guard case .double(let fx) = params["fromX"],
              case .double(let fy) = params["fromY"],
              case .double(let tx) = params["toX"],
              case .double(let ty) = params["toY"]
        else { throw RPCError.operationFailed("drag requires fromX/fromY/toX/toY") }
        let steps = params["steps"]?.intValue ?? 20
        try await input.drag(from: CGPoint(x: fx, y: fy), to: CGPoint(x: tx, y: ty),
                             pid: pid, steps: steps)
        return layer("input-drag", ["from": .object(["x":.double(fx),"y":.double(fy)]),
                                    "to":   .object(["x":.double(tx),"y":.double(ty)])])

    // MARK: - file.*

    case "file.read":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.read requires path")
        }
        let content = try await file.read(path: path)
        return layer("file-posix", ["content": .string(content), "bytes": .int(content.utf8.count)])

    case "file.write":
        guard case .string(let path)    = params["path"],
              case .string(let content) = params["content"]
        else { throw RPCError.operationFailed("file.write requires path + content") }
        try await file.write(path: path, content: content)
        return layer("file-posix", ["bytes": .int(content.utf8.count)])

    case "file.copy":
        guard case .string(let from) = params["from"],
              case .string(let to)   = params["to"]
        else { throw RPCError.operationFailed("file.copy requires from + to") }
        try await file.copy(from: from, to: to)
        return layer("file-posix")

    case "file.move":
        guard case .string(let from) = params["from"],
              case .string(let to)   = params["to"]
        else { throw RPCError.operationFailed("file.move requires from + to") }
        try await file.move(from: from, to: to)
        return layer("file-posix")

    case "file.delete":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.delete requires path")
        }
        if params["trash"] == .bool(true) { try await file.trash(path: path) }
        else                              { try await file.delete(path: path) }
        return layer("file-posix")

    case "file.mkdir":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.mkdir requires path")
        }
        try await file.mkdir(path: path)
        return layer("file-posix")

    case "file.exists":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.exists requires path")
        }
        return layer("file-posix", ["exists": .bool(file.exists(path: path))])

    case "file.stat":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.stat requires path")
        }
        let info = try await file.stat(path: path)
        let fmt = ISO8601DateFormatter()
        return layer("file-posix", [
            "path":         .string(info.path),
            "name":         .string(info.name),
            "size":         .int(Int(info.size)),
            "isDirectory":  .bool(info.isDirectory),
            "isSymlink":    .bool(info.isSymlink),
            "exists":       .bool(info.exists),
            "permissions":  .int(info.permissions),
            "isICloud":     .bool(info.isICloud),
            "iCloudReady":  .bool(info.iCloudDownloaded),
            "modifiedAt":   info.modifiedAt.map { .string(fmt.string(from: $0)) } ?? .null,
            "createdAt":    info.createdAt.map  { .string(fmt.string(from: $0)) } ?? .null,
        ])

    case "file.list":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.list requires path")
        }
        let items = try await file.list(path: path)
        let list: [JSONValue] = items.map { item in
            .object(["name": .string(item.name), "path": .string(item.path),
                     "isDirectory": .bool(item.isDirectory), "size": .int(Int(item.size))])
        }
        return layer("file-posix", ["items": .array(list), "count": .int(list.count)])

    case "file.tags":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.tags requires path")
        }
        let tags = try file.tags(path: path)
        return layer("file-xattr", ["tags": .array(tags.map { .string($0) })])

    case "file.set-tags":
        guard case .string(let path) = params["path"],
              case .array(let tagVals) = params["tags"]
        else { throw RPCError.operationFailed("file.set-tags requires path + tags array") }
        let tags = tagVals.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        try file.setTags(tags, path: path)
        return layer("file-xattr", ["tags": .array(tags.map { .string($0) })])

    case "file.add-tags":
        guard case .string(let path) = params["path"],
              case .array(let tagVals) = params["tags"]
        else { throw RPCError.operationFailed("file.add-tags requires path + tags array") }
        let tags = tagVals.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        try file.addTags(tags, path: path)
        return layer("file-xattr")

    case "file.reveal":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.reveal requires path")
        }
        await file.revealInFinder(path: path)
        return layer("finder")

    case "file.open":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.open requires path")
        }
        let appBundleID = params["app"]?.stringValue
        try await file.open(path: path, withApp: appBundleID)
        return layer("finder")

    case "file.resolve-icloud":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.resolve-icloud requires path")
        }
        let timeoutSecs = params["timeout"]?.intValue ?? 30
        let resolved = try await file.resolveICloud(path: path, timeoutSecs: timeoutSecs)
        return layer("icloud", ["resolvedPath": .string(resolved)])

    // MARK: - calendar.*

    case "calendar.list-calendars":
        try await eventKit.requestCalendarAccess()
        let cals = await eventKit.listCalendars()
        return layer("framework-api", [
            "calendars": .array(cals.map { c in
                .object(["id":.string(c.id),"title":.string(c.title),"type":.string(c.type),"color":.string(c.color)])
            }),
            "count": .int(cals.count),
        ])

    case "calendar.fetch-events":
        try await eventKit.requestCalendarAccess()
        let startTS = params["startTimestamp"]?.doubleValue ?? Date().timeIntervalSince1970
        let endTS   = params["endTimestamp"]?.doubleValue
                      ?? Date().addingTimeInterval(7 * 86400).timeIntervalSince1970
        let calIDs  = params["calendarIDs"].flatMap { if case .array(let a) = $0 { return a.compactMap { $0.stringValue } }; return nil }
        let events  = await eventKit.fetchEvents(
            from: Date(timeIntervalSince1970: startTS),
            to:   Date(timeIntervalSince1970: endTS),
            calendarIDs: calIDs)
        let fmt = ISO8601DateFormatter()
        return layer("framework-api", [
            "events": .array(events.map { e in
                var obj: [String: JSONValue] = [
                    "id":.string(e.id),"title":.string(e.title),
                    "startDate":.string(fmt.string(from: e.startDate)),
                    "endDate":.string(fmt.string(from: e.endDate)),
                    "calendarTitle":.string(e.calendarTitle),
                    "isAllDay":.bool(e.isAllDay),
                ]
                if let n = e.notes    { obj["notes"]    = .string(n) }
                if let l = e.location { obj["location"] = .string(l) }
                return .object(obj)
            }),
            "count": .int(events.count),
        ])

    case "calendar.create-event":
        try await eventKit.requestCalendarAccess()
        guard case .string(let title)  = params["title"],
              case .double(let startTS) = params["startTimestamp"],
              case .double(let endTS)   = params["endTimestamp"]
        else { throw RPCError.operationFailed("calendar.create-event requires title+startTimestamp+endTimestamp") }
        let event = try await eventKit.createEvent(
            title:      title,
            start:      Date(timeIntervalSince1970: startTS),
            end:        Date(timeIntervalSince1970: endTS),
            calendarID: params["calendarID"]?.stringValue,
            notes:      params["notes"]?.stringValue,
            isAllDay:   params["isAllDay"] == .bool(true),
            location:   params["location"]?.stringValue)
        return layer("framework-api", ["id":.string(event.id),"title":.string(event.title)])

    case "calendar.delete-event":
        try await eventKit.requestCalendarAccess()
        guard case .string(let id) = params["id"] else {
            throw RPCError.operationFailed("calendar.delete-event requires id")
        }
        try await eventKit.deleteEvent(id: id)
        return layer("framework-api")

    // MARK: - reminder.*

    case "reminder.list-lists":
        try await eventKit.requestRemindersAccess()
        let lists = await eventKit.listReminderLists()
        return layer("framework-api", [
            "lists": .array(lists.map { .object(["id":.string($0.id),"title":.string($0.title)]) }),
            "count": .int(lists.count),
        ])

    case "reminder.fetch":
        try await eventKit.requestRemindersAccess()
        let completed = params["completed"]?.boolValue
        let listIDs   = params["listIDs"].flatMap { if case .array(let a) = $0 { return a.compactMap { $0.stringValue } }; return nil }
        let reminders = try await eventKit.fetchReminders(listIDs: listIDs, completed: completed)
        return layer("framework-api", [
            "reminders": .array(reminders.map { r in
                var obj: [String: JSONValue] = [
                    "id":.string(r.id),"title":.string(r.title),
                    "isCompleted":.bool(r.isCompleted),"listTitle":.string(r.listTitle),
                ]
                if let d = r.dueDate { obj["dueDate"] = .string(ISO8601DateFormatter().string(from: d)) }
                if let n = r.notes   { obj["notes"]   = .string(n) }
                return .object(obj)
            }),
            "count": .int(reminders.count),
        ])

    case "reminder.create":
        try await eventKit.requestRemindersAccess()
        guard case .string(let title) = params["title"] else {
            throw RPCError.operationFailed("reminder.create requires title")
        }
        let dueDate = params["dueTimestamp"]?.doubleValue.map { Date(timeIntervalSince1970: $0) }
        let reminder = try await eventKit.createReminder(
            title: title, dueDate: dueDate,
            listID: params["listID"]?.stringValue,
            notes: params["notes"]?.stringValue,
            priority: params["priority"]?.intValue ?? 0)
        return layer("framework-api", ["id":.string(reminder.id),"title":.string(reminder.title)])

    case "reminder.complete":
        try await eventKit.requestRemindersAccess()
        guard case .string(let id) = params["id"] else {
            throw RPCError.operationFailed("reminder.complete requires id")
        }
        let r = try await eventKit.completeReminder(id: id)
        return layer("framework-api", ["id":.string(r.id),"isCompleted":.bool(r.isCompleted)])

    // MARK: - contact.*

    case "contact.search":
        try await contacts.requestAccess()
        guard case .string(let query) = params["query"] else {
            throw RPCError.operationFailed("contact.search requires query")
        }
        let limit   = params["limit"]?.intValue ?? 25
        let results = try await contacts.search(query: query, limit: limit)
        return layer("framework-api", [
            "contacts": .array(results.map { c in
                .object(["id":.string(c.id),"fullName":.string(c.fullName),
                         "givenName":.string(c.givenName),"familyName":.string(c.familyName),
                         "emails":.array(c.emailAddresses.map { .string($0) }),
                         "phones":.array(c.phoneNumbers.map { .string($0) }),
                         "organization":.string(c.organizationName)])
            }),
            "count": .int(results.count),
        ])

    case "contact.get":
        try await contacts.requestAccess()
        guard case .string(let id) = params["id"] else {
            throw RPCError.operationFailed("contact.get requires id")
        }
        let c = try await contacts.get(id: id)
        return layer("framework-api", [
            "id":.string(c.id),"fullName":.string(c.fullName),
            "givenName":.string(c.givenName),"familyName":.string(c.familyName),
            "emails":.array(c.emailAddresses.map { .string($0) }),
            "phones":.array(c.phoneNumbers.map { .string($0) }),
            "organization":.string(c.organizationName),"jobTitle":.string(c.jobTitle),
        ])

    case "contact.create":
        try await contacts.requestAccess()
        guard case .string(let given)  = params["givenName"],
              case .string(let family) = params["familyName"]
        else { throw RPCError.operationFailed("contact.create requires givenName+familyName") }
        let c = try await contacts.create(
            givenName: given, familyName: family,
            email: params["email"]?.stringValue,
            phone: params["phone"]?.stringValue,
            organization: params["organization"]?.stringValue)
        return layer("framework-api", ["id":.string(c.id),"fullName":.string(c.fullName)])

    // MARK: - window.*

    case "window.list":
        let bundleID = params["bundleID"]?.stringValue
        let windows = await window.listWindows(app: bundleID)
        return layer("window", [
            "windows": .array(windows.map { w in
                .object(["windowID": .int(Int(w.windowID)), "title": .string(w.title),
                         "appName": .string(w.appName), "bundleID": .string(w.bundleID),
                         "pid": .int(Int(w.pid)),
                         "x": .double(w.frame.minX), "y": .double(w.frame.minY),
                         "width": .double(w.frame.width), "height": .double(w.frame.height),
                         "screenIndex": .int(w.screenIndex)])
            }),
            "count": .int(windows.count),
        ])

    case "window.move":
        guard let wid = params["windowID"]?.intValue.map({ CGWindowID($0) }),
              case .double(let x) = params["x"], case .double(let y) = params["y"]
        else { throw RPCError.operationFailed("window.move requires windowID+x+y") }
        await window.move(windowID: wid, x: x, y: y)
        return layer("window")

    case "window.resize":
        guard let wid = params["windowID"]?.intValue.map({ CGWindowID($0) }),
              case .double(let w) = params["width"], case .double(let h) = params["height"]
        else { throw RPCError.operationFailed("window.resize requires windowID+width+height") }
        await window.resize(windowID: wid, width: w, height: h)
        return layer("window")

    case "window.set-bounds":
        guard let wid = params["windowID"]?.intValue.map({ CGWindowID($0) }),
              case .double(let x) = params["x"], case .double(let y) = params["y"],
              case .double(let w) = params["width"], case .double(let h) = params["height"]
        else { throw RPCError.operationFailed("window.set-bounds requires windowID+x+y+width+height") }
        await window.setBounds(windowID: wid, x: x, y: y, w: w, h: h)
        return layer("window")

    case "window.focus":
        guard let pid = params["pid"]?.intValue.map({ pid_t($0) }) else {
            throw RPCError.operationFailed("window.focus requires pid")
        }
        await window.focus(pid: pid)
        return layer("window")

    case "window.minimize":
        guard let wid = params["windowID"]?.intValue.map({ CGWindowID($0) }) else {
            throw RPCError.operationFailed("window.minimize requires windowID")
        }
        await window.minimize(windowID: wid)
        return layer("window")

    case "window.unminimize":
        guard let wid = params["windowID"]?.intValue.map({ CGWindowID($0) }) else {
            throw RPCError.operationFailed("window.unminimize requires windowID")
        }
        await window.unminimize(windowID: wid)
        return layer("window")

    case "window.fullscreen":
        guard let wid = params["windowID"]?.intValue.map({ CGWindowID($0) }) else {
            throw RPCError.operationFailed("window.fullscreen requires windowID")
        }
        let enabled = params["enabled"] != .bool(false)
        await window.setFullScreen(windowID: wid, enabled: enabled)
        return layer("window")

    case "window.tile-left":
        guard let wid = params["windowID"]?.intValue.map({ CGWindowID($0) }) else {
            throw RPCError.operationFailed("window.tile-left requires windowID")
        }
        await window.tileLeft(windowID: wid)
        return layer("window")

    case "window.tile-right":
        guard let wid = params["windowID"]?.intValue.map({ CGWindowID($0) }) else {
            throw RPCError.operationFailed("window.tile-right requires windowID")
        }
        await window.tileRight(windowID: wid)
        return layer("window")

    // MARK: - process.*

    case "process.list":
        let filter = params["filter"]?.stringValue
        let procs  = await process.list(filter: filter)
        return layer("native-api", [
            "processes": .array(procs.map { p in
                .object(["pid": .int(Int(p.pid)), "name": .string(p.name),
                         "status": .string(p.status), "memoryMB": .double(p.memoryMB),
                         "parentPID": .int(Int(p.parentPID)), "isApp": .bool(p.isApp)])
            }),
            "count": .int(procs.count),
        ])

    case "process.kill":
        let force = params["force"] == .bool(true)
        if case .int(let pid) = params["pid"] {
            try await process.kill(pid: pid_t(pid), force: force)
        } else if case .string(let name) = params["name"] {
            try await process.kill(name: name, force: force)
        } else { throw RPCError.operationFailed("process.kill requires pid or name") }
        return layer("native-api")

    case "process.is-running":
        guard case .string(let name) = params["name"] else {
            throw RPCError.operationFailed("process.is-running requires name")
        }
        return layer("native-api", ["isRunning": .bool(await process.isRunning(name: name))])

    // MARK: - spotlight.*

    case "spotlight.search":
        guard case .string(let query) = params["query"] else {
            throw RPCError.operationFailed("spotlight.search requires query")
        }
        let max = params["limit"]?.intValue ?? 50
        let results = await spotlight.search(query: query, maxResults: max)
        let fmt = ISO8601DateFormatter()
        return layer("spotlight", [
            "results": .array(results.map { r in
                var obj: [String: JSONValue] = [
                    "path": .string(r.path), "name": .string(r.name),
                    "kind": .string(r.kind), "size": .int(Int(r.size)),
                ]
                if let d = r.modifiedDate { obj["modifiedDate"] = .string(fmt.string(from: d)) }
                return .object(obj)
            }),
            "count": .int(results.count),
        ])

    case "spotlight.find-files":
        guard case .string(let name) = params["name"] else {
            throw RPCError.operationFailed("spotlight.find-files requires name")
        }
        let dir = params["directory"]?.stringValue
        let results = await spotlight.findFiles(name: name, in: dir)
        return layer("spotlight", [
            "results": .array(results.map { .string($0.path) }),
            "count":   .int(results.count),
        ])

    // MARK: - share.*

    case "share.list-services":
        let services = await share.availableServices()
        return layer("native-api", [
            "services": .array(services.map { .string($0.title) }),
        ])

    case "share.url":
        guard case .string(let urlStr) = params["url"],
              let url = URL(string: urlStr) ?? URL(fileURLWithPath: urlStr)
                as URL?
        else { throw RPCError.operationFailed("share.url requires url") }
        let svcName = NSSharingService.Name(params["service"]?.stringValue ?? "com.apple.share.Mail.compose")
        try await share.shareURLs([url], via: svcName)
        return layer("native-api")

    // MARK: - input-source.*

    case "input-source.current":
        let src = await inputSource.current()
        if let s = src {
            return layer("native-api", ["id":.string(s.id),"name":.string(s.localizedName)])
        }
        return layer("native-api", ["id":.null,"name":.null])

    case "input-source.list":
        let sources = await inputSource.list()
        return layer("native-api", [
            "sources": .array(sources.map { s in
                .object(["id":.string(s.id),"name":.string(s.localizedName),
                         "isSelected":.bool(s.isSelected),"category":.string(s.category)])
            }),
        ])

    case "input-source.select":
        guard case .string(let id) = params["id"] ?? params["name"] else {
            throw RPCError.operationFailed("input-source.select requires id or name")
        }
        // Try exact id first, then name match
        do { try await inputSource.select(id: id) }
        catch { try await inputSource.selectByName(id) }
        return layer("native-api")

    // MARK: - screen.*

    case "screen.list":
        let screens = await screen.list()
        let fmt2 = ISO8601DateFormatter(); _ = fmt2
        return layer("native-api", [
            "screens": .array(screens.map { s in
                .object(["index":.int(s.index),"name":.string(s.name),
                         "width":.int(s.width),"height":.int(s.height),
                         "scaleFactor":.double(s.scaleFactor),"isMain":.bool(s.isMain),
                         "brightness":.double(Double(s.brightness))])
            }),
            "count": .int(screens.count),
        ])

    case "screen.set-brightness":
        guard case .double(let value) = params["value"] else {
            throw RPCError.operationFailed("screen.set-brightness requires value 0.0-1.0")
        }
        let idx = params["screenIndex"]?.intValue ?? 0
        await screen.setBrightness(Float(value), screenIndex: idx)
        return layer("native-api", ["brightness": .double(value)])

    default:
        throw RPCError(code: 5, message: "Unknown method: \(method)")
    }
}
