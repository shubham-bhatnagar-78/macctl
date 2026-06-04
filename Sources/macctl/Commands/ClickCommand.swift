import ArgumentParser
import MacCtlKit

struct ClickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click a UI element by label query or coordinates")

    @Argument(help: "Element label / query to click") var query: String?
    @Option(name: .long, help: "App bundle ID (e.g. com.apple.Safari)") var app: String
    @Option(name: .long, help: "X coordinate") var x: Double?
    @Option(name: .long, help: "Y coordinate") var y: Double?
    @Flag(name: .long, help: "Bring app to foreground first") var foreground = false

    func run() throws {
        var params: [String: JSONValue] = [
            "bundleID": .string(app),
            "background": .bool(!foreground),
        ]
        if let q = query { params["query"] = .string(q) }
        if let x, let y { params["x"] = .double(x); params["y"] = .double(y) }
        try rpc(method: "click", params: params)
    }
}
