import ArgumentParser
import MacCtlKit

struct PowerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "power",
        abstract: "Power management: sleep prevention, lock screen, system sleep",
        subcommands: [Status.self, Lock.self, Sleep.self, Caffeinate.self, ReleaseSleep.self])

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status")
        func run() throws { try rpc(method: "power.status", params: [:]) }
    }

    struct Lock: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "lock",
            abstract: "Lock the screen immediately")
        func run() throws { try rpc(method: "power.lock-screen", params: [:]) }
    }

    struct Sleep: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "sleep",
            abstract: "Put system to sleep")
        func run() throws { try rpc(method: "power.sleep", params: [:]) }
    }

    struct Caffeinate: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "caffeinate",
            abstract: "Prevent system sleep — returns token for release")
        @Option(name: .long, help: "Reason shown in Activity Monitor") var reason = "macctl caffeinate"
        func run() throws {
            try rpc(method: "power.prevent-sleep", params: ["reason": .string(reason)])
        }
    }

    struct ReleaseSleep: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "release",
            abstract: "Release a sleep prevention by token")
        @Argument(help: "Token from caffeinate command") var token: Int
        func run() throws {
            try rpc(method: "power.release-sleep", params: ["token": .int(token)])
        }
    }
}
