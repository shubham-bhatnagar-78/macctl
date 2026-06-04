import ArgumentParser
import MacCtlKit
import Foundation

struct RemindersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Reminders via EventKit",
        subcommands: [Lists.self, Fetch.self, Create.self, Complete.self])

    struct Lists: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "lists",
            abstract: "List reminder lists")
        func run() throws { try rpc(method: "reminder.list-lists", params: [:]) }
    }

    struct Fetch: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list",
            abstract: "List reminders (default: incomplete)")
        @Flag(name: .long, help: "Include all (completed + incomplete)") var all = false
        @Flag(name: .long, help: "Only completed reminders") var completed = false
        func run() throws {
            var params: [String: JSONValue] = [:]
            if completed     { params["completed"] = .bool(true) }
            else if !all     { params["completed"] = .bool(false) }
            try rpc(method: "reminder.fetch", params: params)
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create")
        @Argument var title: String
        @Option(name: .long, help: "Due date (ISO8601)") var due: String?
        @Option(name: .long, help: "Notes") var notes: String?
        func run() throws {
            var params: [String: JSONValue] = ["title": .string(title)]
            if let d = due, let date = ISO8601DateFormatter().date(from: d) {
                params["dueTimestamp"] = .double(date.timeIntervalSince1970)
            }
            if let n = notes { params["notes"] = .string(n) }
            try rpc(method: "reminder.create", params: params)
        }
    }

    struct Complete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "complete",
            abstract: "Mark reminder as completed")
        @Argument var id: String
        func run() throws {
            try rpc(method: "reminder.complete", params: ["id": .string(id)])
        }
    }
}
