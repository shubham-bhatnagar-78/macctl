import Foundation
import Logging

public actor DaemonLifecycle {
    private var activityToken: NSObjectProtocol?
    private let logger = Logger(label: "macctl.lifecycle")
    public nonisolated let sessionID = UUID().uuidString
    public nonisolated let version = "1.0.0"

    public init() {}

    public func start() {
        // Prevent App Nap — critical for consistent latency on battery
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "macctl daemon — active automation"
        )
        ProcessInfo.processInfo.disableAutomaticTermination("macctl daemon running")
        logger.info("macctl-daemon started. session=\(sessionID) version=\(version)")
    }

    public func stop() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
        ProcessInfo.processInfo.enableAutomaticTermination("macctl daemon running")
        logger.info("macctl-daemon stopped.")
    }
}
