import Foundation

public enum LaunchAgent {
    public static let label = "com.macctl.daemon"

    public static var plistPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.macctl.daemon.plist")
    }

    public static func plistContent(daemonPath: String) -> String {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/macctl-daemon.log").path
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.macctl.daemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(daemonPath)</string>
            </array>
            <key>KeepAlive</key>
            <true/>
            <key>RunAtLoad</key>
            <true/>
            <key>HardResourceLimits</key>
            <dict>
                <key>NumberOfFiles</key>
                <integer>4096</integer>
            </dict>
            <key>SoftResourceLimits</key>
            <dict>
                <key>NumberOfFiles</key>
                <integer>4096</integer>
            </dict>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
        </dict>
        </plist>
        """
    }

    public static func install(daemonPath: String) throws {
        let content = plistContent(daemonPath: daemonPath)
        try content.write(to: plistPath, atomically: true, encoding: .utf8)
        launchctl("load", plistPath.path)
    }

    public static func uninstall() {
        launchctl("unload", plistPath.path)
        try? FileManager.default.removeItem(at: plistPath)
    }

    @discardableResult
    private static func launchctl(_ command: String, _ path: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [command, path]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public enum LaunchAgentError: Error, Sendable {
    case loadFailed
    case daemonNotFound(String)
}
