import ArgumentParser
import MacCtlKit

struct SeeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "see",
        abstract: "Enumerate interactive UI elements with IDs")

    @Option(name: .long, help: "App bundle ID") var app: String

    func run() throws {
        try rpc(method: "see", params: ["bundleID": .string(app)])
    }
}
