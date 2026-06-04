import ArgumentParser
import MacCtlKit
import Foundation

struct WatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Stream live events to stdout (Ctrl+C to stop)",
        subcommands: [WatchFile.self, WatchApps.self])

    struct WatchFile: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "file",
            abstract: "Watch file or directory for changes (create/modify/delete/rename)")
        @Argument(help: "File or directory path to watch") var path: String
        func run() throws {
            streamEvents(topic: "file-watch", params: ["path": .string(path)])
        }
    }

    struct WatchApps: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "apps",
            abstract: "Watch app launch/quit/activate events")
        func run() throws {
            streamEvents(topic: "app-lifecycle", params: [:])
        }
    }
}

private func streamEvents(topic: String, params: [String: JSONValue]) {
    let client = SocketClient()
    do {
        fputs("Watching \(topic). Ctrl+C to stop.\n", stderr)
        let subID = UUID().uuidString
        try client.subscribeAndStream(topic: topic, params: params, subID: subID) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return true
            }
            // Stop on "done" event
            if (json["type"] as? String) == "done" { return false }
            // Print each event as pretty JSON
            if let pretty = try? JSONSerialization.data(withJSONObject: json,
                                                         options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8) {
                print(str)
                fflush(stdout)
            }
            return true
        }
    } catch SocketError.connectFailed {
        print(#"{"success":false,"error":{"code":4,"message":"Daemon not running. Run: macctl-daemon &"}}"#)
    } catch {
        print(#"{"success":false,"error":{"code":5,"message":"\#(error)"}}"#)
    }
}
