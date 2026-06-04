import ArgumentParser
import MacCtlKit

struct DefaultsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "defaults",
        abstract: "NSUserDefaults read/write/delete (no shell spawn — ~0.5ms)",
        subcommands: [Read.self, Write.self, Delete.self])

    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "read")
        @Argument var domain: String
        @Argument var key: String
        func run() throws {
            try rpc(method: "defaults.read",
                    params: ["domain": .string(domain), "key": .string(key)])
        }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "write")
        @Argument var domain: String
        @Argument var key: String
        @Argument(help: "Value to write") var value: String
        @Flag(name: .long, help: "Write as bool") var bool = false
        @Flag(name: .long, help: "Write as int")  var int  = false
        @Flag(name: .long, help: "Write as float") var float = false
        func run() throws {
            let jsonVal: JSONValue
            if bool        { jsonVal = .bool(["true","1","yes"].contains(value.lowercased())) }
            else if int    { jsonVal = .int(Int(value) ?? 0) }
            else if float  { jsonVal = .double(Double(value) ?? 0) }
            else           { jsonVal = .string(value) }
            try rpc(method: "defaults.write",
                    params: ["domain": .string(domain), "key": .string(key), "value": jsonVal])
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete")
        @Argument var domain: String
        @Argument var key: String
        func run() throws {
            try rpc(method: "defaults.delete",
                    params: ["domain": .string(domain), "key": .string(key)])
        }
    }
}
