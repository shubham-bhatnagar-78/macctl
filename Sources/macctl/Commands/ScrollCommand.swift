import ArgumentParser
import MacCtlKit

struct ScrollCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll in an app window (up/down/left/right)")

    @Argument(help: "Direction: up, down, left, right") var direction: String = "down"
    @Option(name: .long, help: "App bundle ID") var app: String
    @Option(name: .long, help: "Scroll amount (lines)") var amount: Int = 3

    func run() throws {
        try rpc(method: "scroll", params: [
            "bundleID":  .string(app),
            "direction": .string(direction),
            "amount":    .int(amount),
        ])
    }
}
