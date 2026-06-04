import Foundation

/// Methods that mutate state — blocked in dry-run mode.
private let destructiveMethods: Set<String> = [
    "file.write", "file.delete", "file.move", "file.mkdir", "file.set-tags", "file.add-tags",
    "system.volume", "system.brightness", "system.wifi", "system.bluetooth", "system.mute",
    "power.sleep", "power.lock-screen", "power.prevent-sleep",
    "clipboard.write", "clipboard.clear",
    "defaults.write", "defaults.delete",
    "drag", "click", "type", "key",
    "app.launch", "app.quit",
]

/// When dryRun=true, returns a description of the operation without executing it.
public func makeDryRunMiddleware(dryRun: Bool) -> MiddlewareFn {
    { method, params, next in
        guard dryRun && destructiveMethods.contains(method) else {
            return try await next(method, params)
        }
        return [
            "_layer":  .string("dry-run"),
            "dryRun":  .bool(true),
            "would":   .string(method),
            "params":  .object(params),
        ]
    }
}
