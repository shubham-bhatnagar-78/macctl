import Foundation
import MacCtlKit

// MARK: - Tool definition

struct MCPTool {
    let name: String
    let description: String
    let properties: [String: [String: String]]
    let required: [String]

    var schemaDict: [String: Any] {
        var schema: [String: Any] = ["type": "object"]
        if !properties.isEmpty { schema["properties"] = properties }
        if !required.isEmpty   { schema["required"]   = required }
        return schema
    }
}

private func s(_ d: String) -> [String: String] { ["type": "string",  "description": d] }
private func n(_ d: String) -> [String: String] { ["type": "number",  "description": d] }
private func b(_ d: String) -> [String: String] { ["type": "boolean", "description": d] }

// MARK: - Registry

enum ToolRegistry {
    static let tools: [MCPTool] = [
        // UI automation
        MCPTool(name: "macctl_click",
                description: "Click a UI element by text query or element ID from macctl_see.",
                properties: ["app":   s("App bundle ID (e.g. com.apple.Safari)"),
                             "query": s("Element label to find and click"),
                             "id":    s("Element ID from macctl_see (e.g. E3)"),
                             "x":     n("X coordinate"), "y": n("Y coordinate")],
                required: ["app"]),

        MCPTool(name: "macctl_type",
                description: "Type text into an app. Use 'into' to target a specific text field for faster AX setValue.",
                properties: ["app":  s("App bundle ID"),
                             "text": s("Text to type"),
                             "into": s("Text field label (optional, enables AX setValue)")],
                required: ["app", "text"]),

        MCPTool(name: "macctl_key",
                description: "Send keyboard shortcut. Named actions: new-tab, save, find, new, close, build, run. Or combos: cmd+s, cmd+shift+n.",
                properties: ["app":   s("App bundle ID"),
                             "combo": s("Named action or key combo (e.g. cmd+s, new-tab)")],
                required: ["app", "combo"]),

        MCPTool(name: "macctl_see",
                description: "Enumerate interactive UI elements. Returns element IDs for macctl_click. Use before clicking to find the right element.",
                properties: ["app": s("App bundle ID")],
                required: ["app"]),

        MCPTool(name: "macctl_screenshot",
                description: "Capture screenshot as PNG. Returns file path.",
                properties: ["app": s("App bundle ID (omit for full screen)")],
                required: []),

        MCPTool(name: "macctl_scroll",
                description: "Scroll in an app window.",
                properties: ["app":       s("App bundle ID"),
                             "direction": s("Direction: up, down, left, right"),
                             "amount":    n("Lines to scroll (default 3)")],
                required: ["app"]),

        // App lifecycle
        MCPTool(name: "macctl_app_launch",
                description: "Launch a macOS app by bundle ID.",
                properties: ["bundleID": s("Bundle ID (e.g. com.apple.Safari)")],
                required: ["bundleID"]),

        MCPTool(name: "macctl_app_quit",
                description: "Quit a macOS app.",
                properties: ["bundleID": s("Bundle ID"),
                             "force":    b("Force quit (default false)")],
                required: ["bundleID"]),

        MCPTool(name: "macctl_app_list",
                description: "List all running macOS applications with bundle IDs and PIDs.",
                properties: [:], required: []),

        // Shell
        MCPTool(name: "macctl_shell",
                description: "Execute a shell command via /bin/zsh. Returns stdout, stderr, exitCode.",
                properties: ["command": s("Shell command"),
                             "timeout": n("Timeout seconds (default 30)")],
                required: ["command"]),

        // System state
        MCPTool(name: "macctl_system_status",
                description: "Get system state: volume, brightness, WiFi SSID, Bluetooth.",
                properties: [:], required: []),

        MCPTool(name: "macctl_system_volume",
                description: "Get or set volume (0.0-1.0). Omit value to read.",
                properties: ["value": n("Volume 0.0-1.0 (omit to read)")],
                required: []),

        // File operations
        MCPTool(name: "macctl_file_read",
                description: "Read a file as text.",
                properties: ["path": s("File path (tilde expanded)")],
                required: ["path"]),

        MCPTool(name: "macctl_file_write",
                description: "Write text to a file. Creates parent directories automatically.",
                properties: ["path":    s("File path"),
                             "content": s("Text content")],
                required: ["path", "content"]),

        MCPTool(name: "macctl_file_list",
                description: "List directory contents.",
                properties: ["path": s("Directory path (default: current dir)")],
                required: []),

        MCPTool(name: "macctl_file_stat",
                description: "Get file metadata: size, dates, iCloud status.",
                properties: ["path": s("File path")],
                required: ["path"]),

        // Clipboard
        MCPTool(name: "macctl_clipboard_read",
                description: "Read current clipboard (text, HTML, or files).",
                properties: [:], required: []),

        MCPTool(name: "macctl_clipboard_write",
                description: "Write to clipboard. Provide 'text' or 'html'.",
                properties: ["text": s("Plain text"), "html": s("HTML content")],
                required: []),

        // Calendar
        MCPTool(name: "macctl_calendar_events",
                description: "Fetch calendar events. Default: next 7 days.",
                properties: ["startTimestamp": n("Start (unix timestamp, default: now)"),
                             "endTimestamp":   n("End (unix timestamp, default: +7 days)")],
                required: []),

        MCPTool(name: "macctl_calendar_create",
                description: "Create a calendar event.",
                properties: ["title":          s("Event title"),
                             "startTimestamp": n("Start unix timestamp"),
                             "endTimestamp":   n("End unix timestamp"),
                             "notes":          s("Notes (optional)"),
                             "location":       s("Location (optional)")],
                required: ["title", "startTimestamp", "endTimestamp"]),

        // Reminders
        MCPTool(name: "macctl_reminders_list",
                description: "List incomplete reminders.",
                properties: [:], required: []),

        MCPTool(name: "macctl_reminders_create",
                description: "Create a new reminder.",
                properties: ["title": s("Reminder title"),
                             "notes": s("Notes (optional)")],
                required: ["title"]),

        // Contacts
        MCPTool(name: "macctl_contacts_search",
                description: "Search contacts by name.",
                properties: ["query": s("Name to search"),
                             "limit": n("Max results (default 25)")],
                required: ["query"]),

        // Defaults
        MCPTool(name: "macctl_defaults_read",
                description: "Read NSUserDefaults value. Returns value and type (string/int/bool).",
                properties: ["domain": s("Domain (e.g. com.apple.Safari)"),
                             "key":    s("Key name")],
                required: ["domain", "key"]),

        MCPTool(name: "macctl_defaults_write",
                description: "Write NSUserDefaults value.",
                properties: ["domain": s("Domain"),
                             "key":    s("Key name"),
                             "value":  s("Value (string, number, or bool as string)")],
                required: ["domain", "key", "value"]),
    ]

    // MARK: - Execute tool call

    static func call(name: String, args: [String: Any]) throws -> Any {
        let (method, params) = try buildRPC(name: name, args: args)
        let request = RPCRequest(id: UUID().uuidString, method: method, params: params)
        let data = try JSONEncoder().encode(request)
        let client = SocketClient()
        let responseData: Data
        do { responseData = try client.roundTrip(data) }
        catch SocketError.connectFailed { throw MCPError.daemonNotRunning }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else { throw MCPError.daemonError("Invalid daemon response") }

        if let success = json["success"] as? Bool, !success {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw MCPError.daemonError(msg)
        }
        return json["data"] ?? [String: Any]()
    }

    // MARK: - RPC mapping

    private static func buildRPC(
        name: String, args: [String: Any]
    ) throws -> (String, [String: JSONValue]) {
        func sv(_ k: String) -> JSONValue? { (args[k] as? String).map { .string($0) } }
        func nv(_ k: String) -> JSONValue? {
            if let d = args[k] as? Double { return .double(d) }
            if let i = args[k] as? Int    { return .int(i) }
            return nil
        }
        func bv(_ k: String) -> JSONValue? { (args[k] as? Bool).map { .bool($0) } }

        switch name {
        case "macctl_click":
            var p: [String: JSONValue] = [:]
            if let a = sv("app")   { p["bundleID"]  = a }
            if let q = sv("query") { p["query"]     = q }
            if let i = sv("id")    { p["elementId"] = i }
            if let x = nv("x"), let y = nv("y") { p["x"] = x; p["y"] = y }
            return ("click", p)

        case "macctl_type":
            var p: [String: JSONValue] = [:]
            if let a = sv("app")   { p["bundleID"] = a }
            if let t = sv("text")  { p["text"]     = t }
            if let i = sv("into")  { p["query"]    = i }
            return ("type", p)

        case "macctl_key":
            return ("key", ["bundleID": sv("app") ?? .string(""),
                            "combo":    sv("combo") ?? .string("")])

        case "macctl_see":
            return ("see", ["bundleID": sv("app") ?? .string("")])

        case "macctl_screenshot":
            var p: [String: JSONValue] = [:]
            if let a = sv("app") { p["bundleID"] = a }
            return ("screenshot", p)

        case "macctl_scroll":
            return ("scroll", ["bundleID":  sv("app") ?? .string(""),
                               "direction": sv("direction") ?? .string("down"),
                               "amount":    nv("amount") ?? .int(3)])

        case "macctl_app_launch":
            return ("app.launch", ["bundleID": sv("bundleID") ?? .string("")])

        case "macctl_app_quit":
            var p: [String: JSONValue] = ["bundleID": sv("bundleID") ?? .string("")]
            if let f = bv("force") { p["force"] = f }
            return ("app.quit", p)

        case "macctl_app_list": return ("app.list", [:])

        case "macctl_shell":
            var p: [String: JSONValue] = ["command": sv("command") ?? .string("")]
            if let t = nv("timeout") { p["timeout"] = t }
            return ("shell", p)

        case "macctl_system_status":  return ("system.status", [:])
        case "macctl_system_volume":
            var p: [String: JSONValue] = [:]
            if let v = nv("value") { p["value"] = v }
            return ("system.volume", p)

        case "macctl_file_read":
            return ("file.read", ["path": sv("path") ?? .string("")])
        case "macctl_file_write":
            return ("file.write", ["path":    sv("path")    ?? .string(""),
                                   "content": sv("content") ?? .string("")])
        case "macctl_file_list":
            return ("file.list", ["path": sv("path") ?? .string(".")])
        case "macctl_file_stat":
            return ("file.stat", ["path": sv("path") ?? .string("")])

        case "macctl_clipboard_read":  return ("clipboard.read", [:])
        case "macctl_clipboard_write":
            var p: [String: JSONValue] = [:]
            if let h = sv("html") { p["html"] = h }
            else if let t = sv("text") { p["text"] = t }
            return ("clipboard.write", p)

        case "macctl_calendar_events":
            var p: [String: JSONValue] = [:]
            if let s = nv("startTimestamp") { p["startTimestamp"] = s }
            if let e = nv("endTimestamp")   { p["endTimestamp"]   = e }
            return ("calendar.fetch-events", p)

        case "macctl_calendar_create":
            var p: [String: JSONValue] = [:]
            if let t = sv("title")          { p["title"]          = t  }
            if let s = nv("startTimestamp") { p["startTimestamp"] = s  }
            if let e = nv("endTimestamp")   { p["endTimestamp"]   = e  }
            if let n = sv("notes")          { p["notes"]          = n  }
            if let l = sv("location")       { p["location"]       = l  }
            return ("calendar.create-event", p)

        case "macctl_reminders_list":
            return ("reminder.fetch", ["completed": .bool(false)])

        case "macctl_reminders_create":
            var p: [String: JSONValue] = ["title": sv("title") ?? .string("")]
            if let n = sv("notes") { p["notes"] = n }
            return ("reminder.create", p)

        case "macctl_contacts_search":
            return ("contact.search", ["query": sv("query") ?? .string(""),
                                       "limit": nv("limit") ?? .int(25)])

        case "macctl_defaults_read":
            return ("defaults.read", ["domain": sv("domain") ?? .string(""),
                                      "key":    sv("key")    ?? .string("")])

        case "macctl_defaults_write":
            var p: [String: JSONValue] = ["domain": sv("domain") ?? .string(""),
                                          "key":    sv("key")    ?? .string("")]
            if let v = sv("value")       { p["value"] = v }
            else if let v = nv("value") { p["value"] = v }
            else if let v = bv("value") { p["value"] = v }
            return ("defaults.write", p)

        default:
            throw MCPError.unknownTool(name)
        }
    }
}
