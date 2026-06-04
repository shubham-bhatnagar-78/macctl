import ArgumentParser
import MacCtlKit

struct TypeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into an app (AX setValue > paste > CGEvent)")

    @Argument(help: "Text to type") var text: String
    @Option(name: .long, help: "App bundle ID") var app: String
    @Option(name: .long, help: "Target element query (enables AX setValue fast path)") var into: String?

    func run() throws {
        var params: [String: JSONValue] = ["bundleID": .string(app), "text": .string(text)]
        if let q = into { params["query"] = .string(q) }
        try rpc(method: "type", params: params)
    }
}
