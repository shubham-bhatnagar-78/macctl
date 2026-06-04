import ArgumentParser
import MacCtlKit

struct SpotlightCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spotlight",
        abstract: "Search files and content via Spotlight (NSMetadataQuery)",
        subcommands: [Search.self, Find.self])

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "search",
            abstract: "Search Spotlight index by name or content")
        @Argument var query: String
        @Option(name: .long, help: "Max results") var limit: Int = 50
        func run() throws { try rpc(method: "spotlight.search", params: ["query":.string(query),"limit":.int(limit)]) }
    }

    struct Find: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "find",
            abstract: "Find files by name pattern")
        @Argument var name: String
        @Option(name: .long, help: "Limit search to directory") var in_: String?
        func run() throws {
            var params: [String: JSONValue] = ["name": .string(name)]
            if let d = in_ { params["directory"] = .string(d) }
            try rpc(method: "spotlight.find-files", params: params)
        }
    }
}
