import ArgumentParser
import MacCtlKit

struct ProcessCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "process",
        abstract: "Process management: list all processes, kill by PID or name",
        subcommands: [List.self, Kill.self, IsRunning.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        @Argument(help: "Filter by name (optional)") var filter: String?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let f = filter { params["filter"] = .string(f) }
            try rpc(method: "process.list", params: params)
        }
    }

    struct Kill: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "kill")
        @Argument(help: "PID or process name") var target: String
        @Flag(name: .long, help: "SIGKILL (force)") var force = false
        func run() throws {
            var params: [String: JSONValue] = ["force": .bool(force)]
            if let pid = Int(target) { params["pid"] = .int(pid) }
            else { params["name"] = .string(target) }
            try rpc(method: "process.kill", params: params)
        }
    }

    struct IsRunning: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "is-running")
        @Argument var name: String
        func run() throws { try rpc(method: "process.is-running", params: ["name": .string(name)]) }
    }
}
