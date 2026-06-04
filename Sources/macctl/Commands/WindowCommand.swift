import ArgumentParser
import MacCtlKit

struct WindowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window",
        abstract: "Window management: list/move/resize/tile/focus/minimize/fullscreen",
        subcommands: [List.self, Move.self, Resize.self, SetBounds.self,
                      Focus.self, Minimize.self, Unminimize.self, Fullscreen.self,
                      TileLeft.self, TileRight.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        @Option(name: .long, help: "Filter by app bundle ID") var app: String?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let a = app { params["bundleID"] = .string(a) }
            try rpc(method: "window.list", params: params)
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "move")
        @Option(name: .long, help: "Window ID from window list") var id: Int
        @Option(name: .long) var x: Double
        @Option(name: .long) var y: Double
        func run() throws { try rpc(method: "window.move", params: ["windowID":.int(id),"x":.double(x),"y":.double(y)]) }
    }

    struct Resize: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "resize")
        @Option(name: .long, help: "Window ID") var id: Int
        @Option(name: .long) var width: Double
        @Option(name: .long) var height: Double
        func run() throws { try rpc(method: "window.resize", params: ["windowID":.int(id),"width":.double(width),"height":.double(height)]) }
    }

    struct SetBounds: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set-bounds")
        @Option(name: .long, help: "Window ID") var id: Int
        @Option(name: .long) var x: Double; @Option(name: .long) var y: Double
        @Option(name: .long) var width: Double; @Option(name: .long) var height: Double
        func run() throws { try rpc(method: "window.set-bounds", params: ["windowID":.int(id),"x":.double(x),"y":.double(y),"width":.double(width),"height":.double(height)]) }
    }

    struct Focus: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "focus")
        @Option(name: .long, help: "App PID") var pid: Int
        func run() throws { try rpc(method: "window.focus", params: ["pid":.int(pid)]) }
    }

    struct Minimize: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "minimize")
        @Option(name: .long, help: "Window ID") var id: Int
        func run() throws { try rpc(method: "window.minimize", params: ["windowID":.int(id)]) }
    }

    struct Unminimize: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "unminimize")
        @Option(name: .long, help: "Window ID") var id: Int
        func run() throws { try rpc(method: "window.unminimize", params: ["windowID":.int(id)]) }
    }

    struct Fullscreen: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "fullscreen")
        @Option(name: .long, help: "Window ID") var id: Int
        @Flag(name: .long, help: "Exit fullscreen") var exit = false
        func run() throws { try rpc(method: "window.fullscreen", params: ["windowID":.int(id),"enabled":.bool(!exit)]) }
    }

    struct TileLeft: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "tile-left")
        @Option(name: .long, help: "Window ID") var id: Int
        func run() throws { try rpc(method: "window.tile-left", params: ["windowID":.int(id)]) }
    }

    struct TileRight: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "tile-right")
        @Option(name: .long, help: "Window ID") var id: Int
        func run() throws { try rpc(method: "window.tile-right", params: ["windowID":.int(id)]) }
    }
}
