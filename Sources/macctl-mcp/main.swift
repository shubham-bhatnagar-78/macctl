import Foundation
import MacCtlKit

let encoder = JSONEncoder()
let decoder = JSONDecoder()

func send(_ response: JSONRPCResponse) {
    guard let data = try? encoder.encode(response),
          let str = String(data: data, encoding: .utf8) else { return }
    print(str)
    fflush(stdout)
}

func handleRequest(_ request: JSONRPCRequest) {
    switch request.method {

    case "initialize":
        send(JSONRPCResponse(id: request.id, result: [
            "protocolVersion": "2024-11-05",
            "serverInfo": ["name": "macctl", "version": "1.0.0"],
            "capabilities": ["tools": ["listChanged": false]],
        ] as [String: Any]))

    case "tools/list":
        let list = ToolRegistry.tools.map { t -> [String: Any] in
            ["name": t.name, "description": t.description, "inputSchema": t.schemaDict]
        }
        send(JSONRPCResponse(id: request.id, result: ["tools": list] as [String: Any]))

    case "tools/call":
        let params = request.params
        guard let toolName = params?["name"]?.value as? String else {
            send(JSONRPCResponse(id: request.id,
                error: JSONRPCError(code: -32602, message: "Missing tool name")))
            return
        }
        let args = (params?["arguments"]?.value as? [String: Any]) ?? [:]
        do {
            let result = try ToolRegistry.call(name: toolName, args: args)
            let text: String
            if let data = try? JSONSerialization.data(
                withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
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
                             "text": "Error: macctl daemon not running. Run: macctl install && macctl-daemon &"]],
                "isError": true,
            ] as [String: Any]))
        } catch MCPError.unknownTool(let n) {
            send(JSONRPCResponse(id: request.id,
                error: JSONRPCError(code: -32601, message: "Unknown tool: \(n)")))
        } catch MCPError.daemonError(let msg) {
            send(JSONRPCResponse(id: request.id, result: [
                "content": [["type": "text", "text": "Error: \(msg)"]],
                "isError": true,
            ] as [String: Any]))
        } catch {
            send(JSONRPCResponse(id: request.id, result: [
                "content": [["type": "text", "text": "Error: \(error)"]],
                "isError": true,
            ] as [String: Any]))
        }

    case "ping":
        send(JSONRPCResponse(id: request.id, result: [:] as [String: Any]))

    case "notifications/initialized", "notifications/cancelled":
        break  // no response

    default:
        send(JSONRPCResponse(id: request.id,
            error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)")))
    }
}

// Main read loop: newline-delimited JSON on stdin
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }
    guard let data = line.data(using: .utf8),
          let request = try? decoder.decode(JSONRPCRequest.self, from: data)
    else { continue }
    handleRequest(request)
}
