import ArgumentParser
import MacCtlKit

struct DragCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drag",
        abstract: "Drag from one coordinate to another (screen coordinates, logical points)")

    @Option(name: .customLong("from-x"), help: "Start X coordinate") var fromX: Double
    @Option(name: .customLong("from-y"), help: "Start Y coordinate") var fromY: Double
    @Option(name: .customLong("to-x"),   help: "End X coordinate")   var toX: Double
    @Option(name: .customLong("to-y"),   help: "End Y coordinate")   var toY: Double
    @Option(name: .long, help: "App bundle ID") var app: String
    @Option(name: .long, help: "Drag steps (smoothness, default 20)") var steps: Int = 20

    func run() throws {
        try rpc(method: "drag", params: [
            "bundleID": .string(app),
            "fromX": .double(fromX), "fromY": .double(fromY),
            "toX":   .double(toX),   "toY":   .double(toY),
            "steps": .int(steps),
        ])
    }
}
