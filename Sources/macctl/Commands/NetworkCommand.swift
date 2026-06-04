import ArgumentParser
import MacCtlKit

struct NetworkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "network",
        abstract: "Network: status and DNS resolution",
        subcommands: [Status.self, Resolve.self])

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status",
            abstract: "Show network connectivity status")
        func run() throws { try rpc(method: "network.status", params: [:]) }
    }

    struct Resolve: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "resolve",
            abstract: "Resolve hostname to IP addresses")
        @Argument(help: "Hostname to resolve") var hostname: String
        func run() throws {
            try rpc(method: "network.resolve", params: ["hostname": .string(hostname)])
        }
    }
}
