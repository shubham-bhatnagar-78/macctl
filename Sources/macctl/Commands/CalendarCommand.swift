import ArgumentParser
import MacCtlKit
import Foundation

struct CalendarCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendar",
        abstract: "Calendar events via EventKit (2-20ms vs AppleScript 30ms+)",
        subcommands: [Calendars.self, Events.self, Create.self, Delete.self])

    struct Calendars: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list",
            abstract: "List all calendars")
        func run() throws { try rpc(method: "calendar.list-calendars", params: [:]) }
    }

    struct Events: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "events",
            abstract: "Fetch events (default: next 7 days)")
        @Option(name: .long, help: "Start (unix timestamp)") var from: Double?
        @Option(name: .long, help: "End (unix timestamp)")   var to: Double?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let f = from { params["startTimestamp"] = .double(f) }
            if let t = to   { params["endTimestamp"]   = .double(t) }
            try rpc(method: "calendar.fetch-events", params: params)
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create",
            abstract: "Create calendar event")
        @Argument var title: String
        @Option(name: .long, help: "Start (ISO8601 or unix)") var start: String
        @Option(name: .long, help: "End (ISO8601 or unix)")   var end: String
        @Option(name: .long) var notes: String?
        @Option(name: .long) var location: String?
        @Flag(name: .long)   var allDay = false
        func run() throws {
            var params: [String: JSONValue] = [
                "title":          .string(title),
                "startTimestamp": .double(parseTS(start)),
                "endTimestamp":   .double(parseTS(end)),
                "isAllDay":       .bool(allDay),
            ]
            if let n = notes    { params["notes"]    = .string(n) }
            if let l = location { params["location"] = .string(l) }
            try rpc(method: "calendar.create-event", params: params)
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete")
        @Argument var id: String
        func run() throws {
            try rpc(method: "calendar.delete-event", params: ["id": .string(id)])
        }
    }
}

private func parseTS(_ s: String) -> Double {
    if let d = Double(s) { return d }
    return ISO8601DateFormatter().date(from: s)?.timeIntervalSince1970
        ?? Date().timeIntervalSince1970
}
