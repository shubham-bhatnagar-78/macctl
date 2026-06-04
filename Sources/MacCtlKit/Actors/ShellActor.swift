import Foundation

public actor ShellActor {
    public init() {}

    public struct ShellResult: Sendable {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int32
        public let durationMs: Double
    }

    /// Run a shell command via /bin/zsh with timeout. Returns stdout/stderr/exitCode.
    public func run(
        _ command: String,
        workingDirectory: String? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> ShellResult {
        try await withThrowingTaskGroup(of: ShellResult.self) { group in
            group.addTask {
                let start = Date()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]
                if let wd = workingDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: wd)
                }
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError  = errPipe
                try process.run()
                process.waitUntilExit()
                let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return ShellResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus,
                    durationMs: Date().timeIntervalSince(start) * 1000
                )
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ShellError.timeout(command)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

public enum ShellError: Error, Sendable {
    case timeout(String)
}
