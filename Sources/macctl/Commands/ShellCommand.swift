import ArgumentParser
import MacCtlKit

struct ShellCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shell",
        abstract: "Execute a shell command (via /bin/zsh), returns stdout/stderr/exitCode")

    @Argument(help: "Shell command to run") var command: [String]
    @Option(name: .long, help: "Working directory") var workingDirectory: String?
    @Option(name: .long, help: "Timeout in seconds") var timeout: Double = 30

    func run() throws {
        let cmd = command.joined(separator: " ")
        var params: [String: JSONValue] = [
            "command": .string(cmd),
            "timeout": .double(timeout),
        ]
        if let wd = workingDirectory { params["workingDirectory"] = .string(wd) }
        try rpc(method: "shell", params: params)
    }
}
