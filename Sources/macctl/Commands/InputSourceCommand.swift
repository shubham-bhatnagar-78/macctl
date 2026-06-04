import ArgumentParser
import MacCtlKit

struct InputSourceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "input-source",
        abstract: "Keyboard input source (layout) switching",
        subcommands: [Current.self, List.self, Select.self])

    struct Current: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "current")
        func run() throws { try rpc(method: "input-source.current", params: [:]) }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        func run() throws { try rpc(method: "input-source.list", params: [:]) }
    }

    struct Select: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "select",
            abstract: "Select input source by ID or name")
        @Argument(help: "Input source ID or partial name (e.g. 'U.S.', 'Japanese')") var id: String
        func run() throws { try rpc(method: "input-source.select", params: ["id":.string(id)]) }
    }
}
