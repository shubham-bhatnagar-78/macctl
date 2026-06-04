import ArgumentParser
import MacCtlKit

struct ClipboardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clipboard",
        abstract: "Clipboard: read, write text/files, clear",
        subcommands: [Read.self, Write.self, Clear.self])

    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "read",
            abstract: "Read current clipboard content")
        func run() throws { try rpc(method: "clipboard.read", params: [:]) }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "write",
            abstract: "Write to clipboard")
        @Option(name: .long, help: "Text to write") var text: String?
        @Option(name: .long, help: "File path to write") var file: String?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let t = text       { params["text"]  = .string(t) }
            else if let f = file  { params["files"] = .array([.string(f)]) }
            else { throw ValidationError("Provide --text or --file") }
            try rpc(method: "clipboard.write", params: params)
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "clear",
            abstract: "Clear clipboard")
        func run() throws { try rpc(method: "clipboard.clear", params: [:]) }
    }
}
