import ArgumentParser
import MacCtlKit

struct SystemCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "system",
        abstract: "System state: volume, brightness, WiFi, Bluetooth",
        subcommands: [Status.self, Volume.self, Brightness.self, Wifi.self, Bluetooth.self, Mute.self])

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status",
            abstract: "Show all system state")
        func run() throws { try rpc(method: "system.status", params: [:]) }
    }

    struct Volume: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "volume",
            abstract: "Get or set volume 0.0-1.0")
        @Argument(help: "Volume 0.0-1.0 (omit to read)") var value: Double?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let v = value { params["value"] = .double(v) }
            try rpc(method: "system.volume", params: params)
        }
    }

    struct Brightness: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "brightness",
            abstract: "Get or set brightness 0.0-1.0")
        @Argument(help: "Brightness 0.0-1.0 (omit to read)") var value: Double?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let v = value { params["value"] = .double(v) }
            try rpc(method: "system.brightness", params: params)
        }
    }

    struct Wifi: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "wifi",
            abstract: "Get or set WiFi power (on/off)")
        @Argument(help: "on/off (omit to read)") var state: String?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let s = state { params["enabled"] = .bool(parseOnOff(s)) }
            try rpc(method: "system.wifi", params: params)
        }
    }

    struct Bluetooth: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "bluetooth",
            abstract: "Get or set Bluetooth power (on/off)")
        @Argument(help: "on/off (omit to read)") var state: String?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let s = state { params["enabled"] = .bool(parseOnOff(s)) }
            try rpc(method: "system.bluetooth", params: params)
        }
    }

    struct Mute: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mute",
            abstract: "Set audio mute (on/off, default on)")
        @Argument(help: "on/off") var state: String?
        func run() throws {
            let muted = state.map { parseOnOff($0) } ?? true
            try rpc(method: "system.mute", params: ["muted": .bool(muted)])
        }
    }
}

private func parseOnOff(_ s: String) -> Bool {
    ["on", "1", "true", "yes", "enable", "enabled"].contains(s.lowercased())
}
