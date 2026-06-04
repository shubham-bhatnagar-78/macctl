import ArgumentParser
import MacCtlKit
import Foundation

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install macctl daemon as a launchd login-item service")

    @Flag(name: .long, help: "Remove daemon launchd service") var uninstall = false

    func run() throws {
        if uninstall {
            LaunchAgent.uninstall()
            print(#"{"success":true,"data":{"message":"macctl daemon uninstalled"}}"#)
            return
        }

        // Find daemon binary alongside this CLI binary
        let selfURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardized
        let dir = selfURL.deletingLastPathComponent()
        let daemonURL = dir.appendingPathComponent("macctl-daemon")

        guard FileManager.default.fileExists(atPath: daemonURL.path) else {
            print("""
                {"success":false,"error":{"code":5,"message":"macctl-daemon not found at \(daemonURL.path). Build first: swift build"}}
                """)
            throw ExitCode(1)
        }

        try LaunchAgent.install(daemonPath: daemonURL.path)

        let perms = PermissionBootstrap()
        let status = perms.status()
        var warnings: [String] = []
        if !status.accessibility   { warnings.append("Accessibility permission missing — run: macctl permissions") }
        if !status.screenRecording { warnings.append("Screen Recording permission missing — run: macctl permissions") }

        let result: [String: Any] = [
            "success": true,
            "data": [
                "message": "macctl daemon installed and started",
                "plist": LaunchAgent.plistPath.path,
                "daemon": daemonURL.path,
                "warnings": warnings,
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
