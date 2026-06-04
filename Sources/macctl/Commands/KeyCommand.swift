import ArgumentParser
import MacCtlKit

struct KeyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "key",
        abstract: "Send keyboard shortcut or named action")

    @Argument(help: "Named action (e.g. new-tab) or combo (e.g. cmd+shift+n)") var combo: String
    @Option(name: .long, help: "App bundle ID") var app: String

    func run() throws {
        try rpc(method: "key", params: [
            "bundleID": .string(app),
            "combo": .string(combo),
        ])
    }
}
