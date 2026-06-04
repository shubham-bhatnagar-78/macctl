import ArgumentParser
import MacCtlKit

struct ContactsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contacts",
        abstract: "Contacts via ContactsKit (faster than AppleScript)",
        subcommands: [Search.self, Get.self, Create.self])

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "search",
            abstract: "Search contacts by name")
        @Argument var query: String
        @Option(name: .long, help: "Max results") var limit: Int = 25
        func run() throws {
            try rpc(method: "contact.search",
                    params: ["query": .string(query), "limit": .int(limit)])
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get",
            abstract: "Get contact details by ID")
        @Argument var id: String
        func run() throws {
            try rpc(method: "contact.get", params: ["id": .string(id)])
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create",
            abstract: "Create a new contact")
        @Option(name: .long) var givenName: String = ""
        @Option(name: .long) var familyName: String = ""
        @Option(name: .long) var email: String?
        @Option(name: .long) var phone: String?
        @Option(name: .long) var organization: String?
        func run() throws {
            var params: [String: JSONValue] = [
                "givenName": .string(givenName), "familyName": .string(familyName)
            ]
            if let e = email        { params["email"]        = .string(e) }
            if let p = phone        { params["phone"]        = .string(p) }
            if let o = organization { params["organization"] = .string(o) }
            try rpc(method: "contact.create", params: params)
        }
    }
}
