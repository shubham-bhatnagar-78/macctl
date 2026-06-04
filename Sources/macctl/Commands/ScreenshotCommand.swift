import ArgumentParser
import MacCtlKit

struct ScreenshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture screen or app window to PNG")

    @Option(name: .long, help: "App bundle ID (omit for full screen)") var app: String?

    func run() throws {
        var params: [String: JSONValue] = [:]
        if let a = app { params["bundleID"] = .string(a) }
        try rpc(method: "screenshot", params: params)
    }
}
