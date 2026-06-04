import ArgumentParser
import MacCtlKit

struct FileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file",
        abstract: "File operations: read/write/copy/move/delete/list/stat/tags/reveal/open",
        subcommands: [
            Read.self, Write.self, Copy.self, Move.self, Delete.self,
            List.self, Stat.self, Mkdir.self, Exists.self,
            Tags.self, SetTags.self, AddTags.self,
            Reveal.self, Open.self, ResolveICloud.self,
        ])

    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "read",
            abstract: "Read file contents as text")
        @Argument var path: String
        func run() throws { try rpc(method: "file.read", params: ["path": .string(path)]) }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "write",
            abstract: "Write text content to file (use - to read from stdin)")
        @Argument var path: String
        @Argument(help: "Content to write (use - for stdin)") var content: String
        func run() throws {
            let c = content == "-" ? (readLine(strippingNewline: false) ?? "") : content
            try rpc(method: "file.write", params: ["path": .string(path), "content": .string(c)])
        }
    }

    struct Copy: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "copy")
        @Argument var from: String
        @Argument var to:   String
        func run() throws {
            try rpc(method: "file.copy", params: ["from": .string(from), "to": .string(to)])
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "move",
            abstract: "Move file (handles cross-volume moves safely)")
        @Argument var from: String
        @Argument var to:   String
        func run() throws {
            try rpc(method: "file.move", params: ["from": .string(from), "to": .string(to)])
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete")
        @Argument var path: String
        @Flag(name: .long, help: "Move to Trash (recoverable)") var trash = false
        func run() throws {
            try rpc(method: "file.delete", params: ["path": .string(path), "trash": .bool(trash)])
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list",
            abstract: "List directory contents (hidden files excluded)")
        @Argument var path: String = "."
        func run() throws { try rpc(method: "file.list", params: ["path": .string(path)]) }
    }

    struct Stat: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "stat",
            abstract: "File info: size, dates, permissions, iCloud status")
        @Argument var path: String
        func run() throws { try rpc(method: "file.stat", params: ["path": .string(path)]) }
    }

    struct Mkdir: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mkdir",
            abstract: "Create directory (including parents)")
        @Argument var path: String
        func run() throws { try rpc(method: "file.mkdir", params: ["path": .string(path)]) }
    }

    struct Exists: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "exists")
        @Argument var path: String
        func run() throws { try rpc(method: "file.exists", params: ["path": .string(path)]) }
    }

    struct Tags: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "tags",
            abstract: "List Finder tags on a file (reads xattr directly, 1ms)")
        @Argument var path: String
        func run() throws { try rpc(method: "file.tags", params: ["path": .string(path)]) }
    }

    struct SetTags: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set-tags",
            abstract: "Replace all Finder tags (writes xattr directly, 1ms)")
        @Argument var path: String
        @Argument(help: "Space-separated tags") var tags: [String]
        func run() throws {
            try rpc(method: "file.set-tags",
                    params: ["path": .string(path), "tags": .array(tags.map { .string($0) })])
        }
    }

    struct AddTags: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add-tags",
            abstract: "Add Finder tags without removing existing ones")
        @Argument var path: String
        @Argument(help: "Tags to add") var tags: [String]
        func run() throws {
            try rpc(method: "file.add-tags",
                    params: ["path": .string(path), "tags": .array(tags.map { .string($0) })])
        }
    }

    struct Reveal: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "reveal",
            abstract: "Reveal file in Finder (NSWorkspace, ~5ms)")
        @Argument var path: String
        func run() throws { try rpc(method: "file.reveal", params: ["path": .string(path)]) }
    }

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "open",
            abstract: "Open file with default or specified app")
        @Argument var path: String
        @Option(name: .long, help: "App bundle ID") var app: String?
        func run() throws {
            var params: [String: JSONValue] = ["path": .string(path)]
            if let a = app { params["app"] = .string(a) }
            try rpc(method: "file.open", params: params)
        }
    }

    struct ResolveICloud: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "resolve-icloud",
            abstract: "Download evicted iCloud file and return local path")
        @Argument var path: String
        @Option(name: .long, help: "Download timeout in seconds") var timeout: Int = 30
        func run() throws {
            try rpc(method: "file.resolve-icloud",
                    params: ["path": .string(path), "timeout": .int(timeout)])
        }
    }
}
