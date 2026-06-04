# macctl Plan 6 — MCP Server

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`.

**Goal:** Implement `macctl-mcp` — a fully functional MCP server that exposes all daemon capabilities as MCP tools, enabling Claude Code, Cursor, Codex, and any MCP client to automate macOS.

**Architecture:** `macctl-mcp` reads JSON-RPC from stdin, writes to stdout (MCP stdio transport). Tool calls translate to daemon RPC via `SocketClient.roundTrip`. The server is ~200 lines: JSON-RPC dispatcher + tool registry + result formatter. No new actors — all work happens in the daemon.

**Protocol:** MCP 2024-11-05. Handles: `initialize`, `tools/list`, `tools/call`, `notifications/cancelled`.

**Tech Stack:** Swift 6, Foundation (JSONSerialization), existing SocketClient + MessageFraming.

---

## File Map

```
Sources/macctl-mcp/
  main.swift         REPLACE stub — full MCP server
  MCPTypes.swift     NEW — JSON-RPC types + tool definitions
  ToolRegistry.swift NEW — all tool definitions + call routing
```

---

## Task 1: MCP types + tool registry

- [ ] **Create MCPTypes.swift**

```swift
// Sources/macctl-mcp/MCPTypes.swift
import Foundation

// MARK: - JSON-RPC wire types

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID?
    let method: String
    let params: [String: AnyCodable]?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCID?
    var result: AnyCodable?
    var error: JSONRPCError?

    init(id: JSONRPCID?, result: Any) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = AnyCodable(result)
        self.error = nil
    }
    init(id: JSONRPCID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
}

enum JSONRPCID: Codable, Equatable {
    case string(String)
    case int(Int)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let i = try? c.decode(Int.self)    { self = .int(i);    return }
        self = .null
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i):    try c.encode(i)
        case .null:          try c.encodeNil()
        }
    }
}

// AnyCodable for heterogeneous values
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                           { value = NSNull(); return }
        if let b = try? c.decode(Bool.self)        { value = b; return }
        if let i = try? c.decode(Int.self)         { value = i; return }
        if let d = try? c.decode(Double.self)      { value = d; return }
        if let s = try? c.decode(String.self)      { value = s; return }
        if let a = try? c.decode([AnyCodable].self){ value = a.map(\.value); return }
        if let o = try? c.decode([String: AnyCodable].self) {
            value = o.mapValues(\.value); return
        }
        value = NSNull()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull:          try c.encodeNil()
        case let b as Bool:      try c.encode(b)
        case let i as Int:       try c.encode(i)
        case let d as Double:    try c.encode(d)
        case let s as String:    try c.encode(s)
        case let a as [Any]:
            try c.encode(a.map { AnyCodable($0) })
        case let o as [String: Any]:
            try c.encode(o.mapValues { AnyCodable($0) })
        default:
            try c.encode(String(describing: value))
        }
    }
}
```

- [ ] **Create ToolRegistry.swift**

```swift
// Sources/macctl-mcp/ToolRegistry.swift
import Foundation
import MacCtlKit

// MARK: - Tool definition

struct MCPTool {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    var schemaDict: [String: Any] {
        ["type": "object",
         "properties": inputSchema["properties"] ?? [:],
         "required": inputSchema["required"] ?? []]
    }
}

// MARK: - Tool registry

enum ToolRegistry {
    static let tools: [MCPTool] = [
        MCPTool(name: "macctl_click",
                description: "Click a UI element in a macOS app by text query or element ID from macctl_see.",
                inputSchema: [
                    "properties": ["app": prop("App bundle ID (e.g. com.apple.Safari)"),
                                   "query": prop("Element label to find and click"),
                                   "id": prop("Element ID from macctl_see output (e.g. E3)"),
                                   "x": numProp("X coordinate (use with y for coordinate click)"),
                                   "y": numProp("Y coordinate")],
                    "required": ["app"]]),

        MCPTool(name: "macctl_type",
                description: "Type text into a macOS app. Use --into to specify a text field for fast AX setValue path.",
                inputSchema: [
                    "properties": ["app": prop("App bundle ID"),
                                   "text": prop("Text to type"),
                                   "into": prop("Text field label (enables fast AX setValue, optional)")],
                    "required": ["app", "text"]]),

        MCPTool(name: "macctl_key",
                description: "Send a keyboard shortcut or named action to a macOS app. Named actions: new-tab, save, find, new, close, etc.",
                inputSchema: [
                    "properties": ["app": prop("App bundle ID"),
                                   "combo": prop("Named action (e.g. new-tab) or key combo (e.g. cmd+s)")],
                    "required": ["app", "combo"]]),

        MCPTool(name: "macctl_see",
                description: "Enumerate interactive UI elements in a macOS app window. Returns element IDs for use with macctl_click.",
                inputSchema: [
                    "properties": ["app": prop("App bundle ID")],
                    "required": ["app"]]),

        MCPTool(name: "macctl_screenshot",
                description: "Capture a screenshot of a macOS app window or the full screen.",
                inputSchema: [
                    "properties": ["app": prop("App bundle ID (omit for full screen)")],
                    "required": []]),

        MCPTool(name: "macctl_scroll",
                description: "Scroll in a macOS app window.",
                inputSchema: [
                    "properties": ["app": prop("App bundle ID"),
                                   "direction": prop("Direction: up, down, left, right"),
                                   "amount": numProp("Scroll amount in lines (default 3)")],
                    "required": ["app"]]),

        MCPTool(name: "macctl_app_launch",
                description: "Launch a macOS app by bundle ID.",
                inputSchema: [
                    "properties": ["bundleID": prop("App bundle ID (e.g. com.apple.Safari)")],
                    "required": ["bundleID"]]),

        MCPTool(name: "macctl_app_quit",
                description: "Quit a macOS app.",
                inputSchema: [
                    "properties": ["bundleID": prop("App bundle ID"),
                                   "force": boolProp("Force quit (default false)")],
                    "required": ["bundleID"]]),

        MCPTool(name: "macctl_app_list",
                description: "List all running macOS applications.",
                inputSchema: ["properties": [:], "required": []]),

        MCPTool(name: "macctl_shell",
                description: "Execute a shell command via /bin/zsh. Returns stdout, stderr, and exit code.",
                inputSchema: [
                    "properties": ["command": prop("Shell command to execute"),
                                   "timeout": numProp("Timeout in seconds (default 30)")],
                    "required": ["command"]]),

        MCPTool(name: "macctl_system_status",
                description: "Get system state: volume, brightness, WiFi, Bluetooth.",
                inputSchema: ["properties": [:], "required": []]),

        MCPTool(name: "macctl_system_volume",
                description: "Get or set system volume (0.0-1.0).",
                inputSchema: [
                    "properties": ["value": numProp("Volume 0.0-1.0 (omit to read)")],
                    "required": []]),

        MCPTool(name: "macctl_file_read",
                description: "Read a file's text contents.",
                inputSchema: [
                    "properties": ["path": prop("File path (tilde expanded)")],
                    "required": ["path"]]),

        MCPTool(name: "macctl_file_write",
                description: "Write text content to a file (creates parent directories if needed).",
                inputSchema: [
                    "properties": ["path": prop("File path"), "content": prop("Content to write")],
                    "required": ["path", "content"]]),

        MCPTool(name: "macctl_file_list",
                description: "List directory contents.",
                inputSchema: [
                    "properties": ["path": prop("Directory path (default .)")],
                    "required": []]),

        MCPTool(name: "macctl_file_stat",
                description: "Get file metadata: size, dates, iCloud status.",
                inputSchema: [
                    "properties": ["path": prop("File path")],
                    "required": ["path"]]),

        MCPTool(name: "macctl_clipboard_read",
                description: "Read the current clipboard contents.",
                inputSchema: ["properties": [:], "required": []]),

        MCPTool(name: "macctl_clipboard_write",
                description: "Write text or HTML to the clipboard.",
                inputSchema: [
                    "properties": ["text": prop("Plain text to write"),
                                   "html": prop("HTML to write")],
                    "required": []]),

        MCPTool(name: "macctl_calendar_events",
                description: "Fetch calendar events for a date range.",
                inputSchema: [
                    "properties": ["startTimestamp": numProp("Start unix timestamp (default: now)"),
                                   "endTimestamp":   numProp("End unix timestamp (default: now+7d)")],
                    "required": []]),

        MCPTool(name: "macctl_calendar_create",
                description: "Create a calendar event.",
                inputSchema: [
                    "properties": ["title":          prop("Event title"),
                                   "startTimestamp": numProp("Start unix timestamp"),
                                   "endTimestamp":   numProp("End unix timestamp"),
                                   "notes":          prop("Notes (optional)"),
                                   "location":       prop("Location (optional)")],
                    "required": ["title", "startTimestamp", "endTimestamp"]]),

        MCPTool(name: "macctl_reminders_list",
                description: "List incomplete reminders.",
                inputSchema: ["properties": [:], "required": []]),

        MCPTool(name: "macctl_reminders_create",
                description: "Create a reminder.",
                inputSchema: [
                    "properties": ["title": prop("Reminder title"),
                                   "notes": prop("Notes (optional)")],
                    "required": ["title"]]),

        MCPTool(name: "macctl_contacts_search",
                description: "Search contacts by name.",
                inputSchema: [
                    "properties": ["query": prop("Name to search for"),
                                   "limit": numProp("Max results (default 25)")],
                    "required": ["query"]]),

        MCPTool(name: "macctl_defaults_read",
                description: "Read an NSUserDefaults value.",
                inputSchema: [
                    "properties": ["domain": prop("Defaults domain (e.g. com.apple.Safari)"),
                                   "key":    prop("Key name")],
                    "required": ["domain", "key"]]),

        MCPTool(name: "macctl_defaults_write",
                description: "Write an NSUserDefaults value.",
                inputSchema: [
                    "properties": ["domain": prop("Defaults domain"),
                                   "key":    prop("Key name"),
                                   "value":  prop("Value (string, number, or bool)")],
                    "required": ["domain", "key", "value"]]),
    ]

    // MARK: - Tool call routing

    static func call(name: String, args: [String: Any]) throws -> Any {
        let client = SocketClient()
        let (method, params) = try buildRPCCall(name: name, args: args)
        let request = RPCRequest(id: UUID().uuidString, method: method, params: params)
        let data = try JSONEncoder().encode(request)
        let response = try client.roundTrip(data)
        guard let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw MCPError.daemonError("Invalid response")
        }
        if let success = json["success"] as? Bool, !success {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw MCPError.daemonError(msg)
        }
        return json["data"] ?? [:]
    }

    private static func buildRPCCall(
        name: String, args: [String: Any]
    ) throws -> (String, [String: JSONValue]) {
        func s(_ key: String) -> JSONValue? { (args[key] as? String).map { .string($0) } }
        func n(_ key: String) -> JSONValue? { (args[key] as? Double).map { .double($0) }
                                              ?? (args[key] as? Int).map { .int($0) } }
        func b(_ key: String) -> JSONValue? { (args[key] as? Bool).map { .bool($0) } }

        switch name {
        case "macctl_click":
            var p: [String: JSONValue] = [:]
            if let a = s("app")   { p["bundleID"]   = a }
            if let q = s("query") { p["query"]      = q }
            if let i = s("id")    { p["elementId"]  = i }
            if let x = n("x"), let y = n("y") { p["x"] = x; p["y"] = y }
            return ("click", p)

        case "macctl_type":
            var p: [String: JSONValue] = [:]
            if let a = s("app")   { p["bundleID"] = a }
            if let t = s("text")  { p["text"]     = t }
            if let i = s("into")  { p["query"]    = i }
            return ("type", p)

        case "macctl_key":
            return ("key", ["bundleID": s("app") ?? .string(""),
                            "combo":    s("combo") ?? .string("")])

        case "macctl_see":
            return ("see", ["bundleID": s("app") ?? .string("")])

        case "macctl_screenshot":
            var p: [String: JSONValue] = [:]
            if let a = s("app") { p["bundleID"] = a }
            return ("screenshot", p)

        case "macctl_scroll":
            return ("scroll", ["bundleID":  s("app") ?? .string(""),
                               "direction": s("direction") ?? .string("down"),
                               "amount":    n("amount") ?? .int(3)])

        case "macctl_app_launch":
            return ("app.launch", ["bundleID": s("bundleID") ?? .string("")])

        case "macctl_app_quit":
            var p: [String: JSONValue] = ["bundleID": s("bundleID") ?? .string("")]
            if let f = b("force") { p["force"] = f }
            return ("app.quit", p)

        case "macctl_app_list":
            return ("app.list", [:])

        case "macctl_shell":
            var p: [String: JSONValue] = ["command": s("command") ?? .string("")]
            if let t = n("timeout") { p["timeout"] = t }
            return ("shell", p)

        case "macctl_system_status":
            return ("system.status", [:])

        case "macctl_system_volume":
            var p: [String: JSONValue] = [:]
            if let v = n("value") { p["value"] = v }
            return ("system.volume", p)

        case "macctl_file_read":
            return ("file.read", ["path": s("path") ?? .string("")])

        case "macctl_file_write":
            return ("file.write", ["path":    s("path")    ?? .string(""),
                                   "content": s("content") ?? .string("")])

        case "macctl_file_list":
            return ("file.list", ["path": s("path") ?? .string(".")])

        case "macctl_file_stat":
            return ("file.stat", ["path": s("path") ?? .string("")])

        case "macctl_clipboard_read":
            return ("clipboard.read", [:])

        case "macctl_clipboard_write":
            var p: [String: JSONValue] = [:]
            if let h = s("html") { p["html"] = h }
            else if let t = s("text") { p["text"] = t }
            return ("clipboard.write", p)

        case "macctl_calendar_events":
            var p: [String: JSONValue] = [:]
            if let s = n("startTimestamp") { p["startTimestamp"] = s }
            if let e = n("endTimestamp")   { p["endTimestamp"]   = e }
            return ("calendar.fetch-events", p)

        case "macctl_calendar_create":
            var p: [String: JSONValue] = [:]
            if let t  = s("title")          { p["title"]          = t  }
            if let st = n("startTimestamp") { p["startTimestamp"] = st }
            if let et = n("endTimestamp")   { p["endTimestamp"]   = et }
            if let n  = s("notes")          { p["notes"]          = n  }
            if let l  = s("location")       { p["location"]       = l  }
            return ("calendar.create-event", p)

        case "macctl_reminders_list":
            return ("reminder.fetch", ["completed": .bool(false)])

        case "macctl_reminders_create":
            var p: [String: JSONValue] = ["title": s("title") ?? .string("")]
            if let n = s("notes") { p["notes"] = n }
            return ("reminder.create", p)

        case "macctl_contacts_search":
            return ("contact.search", ["query": s("query") ?? .string(""),
                                       "limit": n("limit") ?? .int(25)])

        case "macctl_defaults_read":
            return ("defaults.read", ["domain": s("domain") ?? .string(""),
                                      "key":    s("key")    ?? .string("")])

        case "macctl_defaults_write":
            var p: [String: JSONValue] = ["domain": s("domain") ?? .string(""),
                                          "key":    s("key")    ?? .string("")]
            if let v = s("value")           { p["value"] = .string(v) }
            else if let v = n("value")      { p["value"] = v }
            else if let v = b("value")      { p["value"] = .bool(v) }
            return ("defaults.write", p)

        default:
            throw MCPError.unknownTool(name)
        }
    }
}

// MARK: - Helpers

private func prop(_ desc: String) -> [String: String] { ["type": "string", "description": desc] }
private func numProp(_ desc: String) -> [String: String] { ["type": "number", "description": desc] }
private func boolProp(_ desc: String) -> [String: String] { ["type": "boolean", "description": desc] }

enum MCPError: Error {
    case unknownTool(String)
    case daemonError(String)
    case daemonNotRunning
}
```

- [ ] **Build to verify**

```bash
swift build --target macctl-mcp 2>&1 | grep -E "error:|complete"
```
Will fail until main.swift is replaced.

---

## Task 2: MCP server main.swift

- [ ] **Replace Sources/macctl-mcp/main.swift**

```swift
// Sources/macctl-mcp/main.swift
import Foundation
import MacCtlKit

// MCP stdio server — reads JSON-RPC from stdin, writes to stdout.
// Newline-delimited JSON messages.

let encoder = JSONEncoder()
let decoder = JSONDecoder()

func send(_ response: JSONRPCResponse) {
    if let data = try? encoder.encode(response),
       let str = String(data: data, encoding: .utf8) {
        print(str)
        fflush(stdout)
    }
}

func sendNotification(_ method: String, _ params: Any) {
    let msg: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
    if let data = try? JSONSerialization.data(withJSONObject: msg),
       let str = String(data: data, encoding: .utf8) {
        print(str)
        fflush(stdout)
    }
}

func handleRequest(_ request: JSONRPCRequest) {
    switch request.method {

    case "initialize":
        send(JSONRPCResponse(id: request.id, result: [
            "protocolVersion": "2024-11-05",
            "serverInfo": ["name": "macctl", "version": "1.0.0"],
            "capabilities": ["tools": ["listChanged": false]],
        ] as [String: Any]))

    case "notifications/initialized":
        break  // no response needed

    case "tools/list":
        let toolList = ToolRegistry.tools.map { tool -> [String: Any] in [
            "name":        tool.name,
            "description": tool.description,
            "inputSchema": tool.schemaDict,
        ]}
        send(JSONRPCResponse(id: request.id, result: ["tools": toolList] as [String: Any]))

    case "tools/call":
        guard let params = request.params,
              let toolName = params["name"]?.value as? String
        else {
            send(JSONRPCResponse(id: request.id,
                                 error: JSONRPCError(code: -32602, message: "Missing tool name")))
            return
        }
        let args = (params["arguments"]?.value as? [String: Any]) ?? [:]
        do {
            let result = try ToolRegistry.call(name: toolName, args: args)
            // Format result as MCP content
            let text: String
            if let data = try? JSONSerialization.data(withJSONObject: result,
                                                       options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                text = str
            } else {
                text = String(describing: result)
            }
            send(JSONRPCResponse(id: request.id, result: [
                "content": [["type": "text", "text": text]],
                "isError": false,
            ] as [String: Any]))
        } catch MCPError.daemonNotRunning {
            send(JSONRPCResponse(id: request.id, result: [
                "content": [["type": "text",
                             "text": "Error: macctl daemon not running. Start it with: macctl-daemon &"]],
                "isError": true,
            ] as [String: Any]))
        } catch MCPError.unknownTool(let name) {
            send(JSONRPCResponse(id: request.id,
                                 error: JSONRPCError(code: -32601, message: "Unknown tool: \(name)")))
        } catch {
            send(JSONRPCResponse(id: request.id, result: [
                "content": [["type": "text", "text": "Error: \(error)"]],
                "isError": true,
            ] as [String: Any]))
        }

    case "notifications/cancelled":
        break  // gracefully ignore

    case "ping":
        send(JSONRPCResponse(id: request.id, result: [:] as [String: Any]))

    default:
        send(JSONRPCResponse(id: request.id,
                             error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)")))
    }
}

// Main read loop — stdin is newline-delimited JSON
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }
    guard let data = line.data(using: .utf8),
          let request = try? decoder.decode(JSONRPCRequest.self, from: data)
    else { continue }
    handleRequest(request)
}
```

- [ ] **Build to verify**

```bash
swift build --product macctl-mcp 2>&1 | grep -E "error:|complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/macctl-mcp/
git commit -m "feat: implement MCP server — 28 tools, stdio JSON-RPC, full daemon integration"
```

---

## Task 3: Test + smoke test

- [ ] **Write MCP protocol test**

Test that the server correctly handles initialize + tools/list:

```bash
# Start daemon
.build/debug/macctl-daemon &
DPID=$!
sleep 1.5

# Test MCP server with piped JSON-RPC
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test"}}}' | \
  timeout 3 .build/debug/macctl-mcp | head -1 | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
print('initialize OK:', d.get('result',{}).get('protocolVersion'))
print('server:', d.get('result',{}).get('serverInfo',{}).get('name'))
"

# Test tools/list
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | \
  timeout 3 .build/debug/macctl-mcp | tail -1 | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
tools=d.get('result',{}).get('tools',[])
print(f'tools/list: {len(tools)} tools')
print('first 5:', [t[\"name\"] for t in tools[:5]])
"

# Test tools/call (macctl_app_list)
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"macctl_app_list","arguments":{}}}\n' | \
  timeout 5 .build/debug/macctl-mcp | tail -1 | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
content=d.get('result',{}).get('content',[{}])[0].get('text','')
data=json.loads(content)
print(f'macctl_app_list: {data.get(\"count\",\"?\")} apps')
print('isError:', d.get('result',{}).get('isError',False))
"

kill $DPID
```

Expected output:
```
initialize OK: 2024-11-05
server: macctl
tools/list: 28 tools
first 5: ['macctl_click', 'macctl_type', ...]
macctl_app_list: 90 apps
isError: False
```

- [ ] **Verify Claude Code config snippet works**

```bash
# Print the config snippet users paste into Claude Code settings
cat << 'EOF'
Add to ~/.claude/settings.json mcpServers:
{
  "mcpServers": {
    "macctl": {
      "command": "/path/to/.build/release/macctl-mcp",
      "env": {}
    }
  }
}
Note: macctl-daemon must be running: macctl install
EOF
```

- [ ] **Final commit**

```bash
git add -A
git commit -m "feat: Plan 6 complete — MCP server with 28 tools verified working"
```
