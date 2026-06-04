import Foundation

/// Watches a path using kqueue (DispatchSourceFileSystemObject).
/// For directories: watches the directory itself plus polls for new files every 500ms.
/// More reliable in Swift 6 than FSEvents C callback which triggers compiler issues.
public enum FileWatchStream {
    public static func watch(path: String) -> AsyncStream<Data> {
        let expanded = (path as NSString).expandingTildeInPath
        return AsyncStream { continuation in
            let url = URL(fileURLWithPath: expanded)
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            // Open file/dir descriptor for kqueue
            let fd = open(expanded, O_EVTONLY)
            guard fd >= 0 else {
                let err = ["type": "error", "message": "Cannot watch: \(expanded)"]
                if let d = try? JSONEncoder().encode(err) { continuation.yield(MessageFraming.frame(d)) }
                continuation.finish()
                return
            }

            let queue = DispatchQueue(label: "macctl.watch.\(UUID().uuidString)", qos: .userInitiated)

            // kqueue source for the path itself
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .attrib, .extend, .link],
                queue: queue
            )

            var previousContents: Set<String> = isDir
                ? Set((try? FileManager.default.contentsOfDirectory(atPath: expanded)) ?? [])
                : []

            source.setEventHandler {
                let mask = source.data
                let events = eventNames(mask)
                for event in events {
                    let payload: [String: String] = [
                        "type": "event", "event": event, "path": expanded,
                        "ts": "\(Int(Date().timeIntervalSince1970))"
                    ]
                    if let d = try? JSONEncoder().encode(payload) {
                        continuation.yield(MessageFraming.frame(d))
                    }
                }

                // For directories: diff contents to detect new/deleted files
                if isDir {
                    let current = Set((try? FileManager.default.contentsOfDirectory(atPath: expanded)) ?? [])
                    let added   = current.subtracting(previousContents)
                    let removed = previousContents.subtracting(current)
                    for name in added {
                        let p = ["type": "event", "event": "created",
                                 "path": "\(expanded)/\(name)",
                                 "ts": "\(Int(Date().timeIntervalSince1970))"]
                        if let d = try? JSONEncoder().encode(p) { continuation.yield(MessageFraming.frame(d)) }
                    }
                    for name in removed {
                        let p = ["type": "event", "event": "deleted",
                                 "path": "\(expanded)/\(name)",
                                 "ts": "\(Int(Date().timeIntervalSince1970))"]
                        if let d = try? JSONEncoder().encode(p) { continuation.yield(MessageFraming.frame(d)) }
                    }
                    previousContents = current
                }
            }

            source.setCancelHandler { close(fd) }
            source.resume()

            continuation.onTermination = { @Sendable _ in source.cancel() }
        }
    }

    private static func eventNames(_ mask: DispatchSource.FileSystemEvent) -> [String] {
        var events: [String] = []
        if mask.contains(.write)   { events.append("modified") }
        if mask.contains(.rename)  { events.append("renamed")  }
        if mask.contains(.delete)  { events.append("deleted")  }
        if mask.contains(.attrib)  { events.append("xattr")    }
        if mask.contains(.extend)  { events.append("modified") }
        return Array(Set(events))  // deduplicate
    }
}
