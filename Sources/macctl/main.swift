import ArgumentParser
import Foundation
import MacCtlKit

struct MacCtl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macctl",
        abstract: "Ultra-fast macOS automation CLI",
        version: "1.0.0",
        subcommands: [
            ClickCommand.self,
            TypeCommand.self,
            KeyCommand.self,
            SeeCommand.self,
            ScrollCommand.self,
            DragCommand.self,
            ShellCommand.self,
            AppCommand.self,
            ScreenshotCommand.self,
            InstallCommand.self,
            SystemCommand.self,
            PowerCommand.self,
            ClipboardCommand.self,
            NetworkCommand.self,
            DefaultsCommand.self,
            FileCommand.self,
            WatchCommand.self,
        ],
    )
}

// MARK: - Shared RPC helper

@discardableResult
func rpc(method: String, params: [String: JSONValue]) throws -> [String: Any] {
    let client = SocketClient()
    let request = RPCRequest(id: UUID().uuidString, method: method, params: params)
    let requestData = try JSONEncoder().encode(request)
    let responseData: Data
    do {
        responseData = try client.roundTrip(requestData)
    } catch SocketError.connectFailed {
        let msg = """
            {"success":false,"error":{"code":4,"message":"Daemon not running. Run: macctl-daemon &"}}
            """
        print(msg)
        throw ExitCode(4)
    }
    guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
        throw ExitCode(1)
    }
    // Pretty-print JSON response
    if let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: pretty, encoding: .utf8) {
        print(str)
    }
    if let success = json["success"] as? Bool, !success {
        throw ExitCode(1)
    }
    return json
}

// Entry point
MacCtl.main()
