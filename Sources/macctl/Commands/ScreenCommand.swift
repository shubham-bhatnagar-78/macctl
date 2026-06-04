import ArgumentParser
import MacCtlKit

struct ScreenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screen",
        abstract: "Display info: list screens, set brightness",
        subcommands: [List.self, Brightness.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list",
            abstract: "List all displays with resolution, scale, and brightness")
        func run() throws { try rpc(method: "screen.list", params: [:]) }
    }

    struct Brightness: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "brightness",
            abstract: "Set display brightness (0.0-1.0)")
        @Argument var value: Double
        @Option(name: .long, help: "Display index (default 0)") var screen: Int = 0
        func run() throws {
            try rpc(method: "screen.set-brightness",
                    params: ["value":.double(value),"screenIndex":.int(screen)])
        }
    }
}
