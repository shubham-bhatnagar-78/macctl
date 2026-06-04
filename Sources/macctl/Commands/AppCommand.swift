import ArgumentParser
import MacCtlKit

struct AppCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Manage application lifecycle",
        subcommands: [Launch.self, Quit.self, Hide.self, Show.self, List.self])

    struct Launch: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "launch")
        @Argument var bundleID: String
        @Flag(name: .long, help: "Launch without activating") var background = false
        func run() throws {
            try rpc(method: "app.launch", params: [
                "bundleID": .string(bundleID), "background": .bool(background)
            ])
        }
    }

    struct Quit: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "quit")
        @Argument var bundleID: String
        @Flag(name: .long, help: "Force quit (SIGKILL)") var force = false
        func run() throws {
            try rpc(method: "app.quit", params: [
                "bundleID": .string(bundleID), "force": .bool(force)
            ])
        }
    }

    struct Hide: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "hide")
        @Argument var bundleID: String
        func run() throws {
            try rpc(method: "app.hide", params: ["bundleID": .string(bundleID)])
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show")
        @Argument var bundleID: String
        func run() throws {
            try rpc(method: "app.show", params: ["bundleID": .string(bundleID)])
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        func run() throws {
            try rpc(method: "app.list", params: [:])
        }
    }
}
