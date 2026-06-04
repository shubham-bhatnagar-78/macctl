import ArgumentParser
import MacCtlKit

struct NotesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notes",
        abstract: "Apple Notes: list/get/find/create/append/delete",
        subcommands: [Folders.self, List.self, Get.self, Find.self,
                      Create.self, Append.self, Delete.self])

    struct Folders: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "folders")
        func run() throws { try rpc(method: "notes.folders", params: [:]) }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        @Option(name: .long, help: "Filter by folder name") var folder: String?
        @Option(name: .long) var limit: Int = 50
        func run() throws {
            var params: [String: JSONValue] = ["limit": .int(limit)]
            if let f = folder { params["folder"] = .string(f) }
            try rpc(method: "notes.list", params: params)
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get",
            abstract: "Get note body by ID")
        @Argument var id: String
        func run() throws { try rpc(method: "notes.get", params: ["id": .string(id)]) }
    }

    struct Find: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "find",
            abstract: "Find note by name (returns body)")
        @Argument var name: String
        func run() throws { try rpc(method: "notes.find", params: ["name": .string(name)]) }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create")
        @Argument var title: String
        @Option(name: .long) var body: String = ""
        @Option(name: .long) var folder: String?
        func run() throws {
            var params: [String: JSONValue] = ["title": .string(title), "body": .string(body)]
            if let f = folder { params["folder"] = .string(f) }
            try rpc(method: "notes.create", params: params)
        }
    }

    struct Append: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "append",
            abstract: "Append text to an existing note")
        @Argument var id: String
        @Argument var text: String
        func run() throws {
            try rpc(method: "notes.append", params: ["id": .string(id), "text": .string(text)])
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete")
        @Argument var id: String
        func run() throws { try rpc(method: "notes.delete", params: ["id": .string(id)]) }
    }
}
