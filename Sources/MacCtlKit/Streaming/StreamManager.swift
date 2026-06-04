import Foundation

/// Routes subscribe topic requests to stream sources.
public struct StreamManager {
    public static func stream(for topic: String,
                              params: [String: JSONValue]) -> AsyncStream<Data> {
        switch topic {
        case "file-watch":
            if case .string(let path) = params["path"] {
                return FileWatchStream.watch(path: path)
            }
            return makeErrorStream("file-watch requires path param")

        case "app-lifecycle":
            return AppLifecycleStream.watch()

        default:
            return makeErrorStream("Unknown topic: \(topic)")
        }
    }

    public static func makeErrorStream(_ message: String) -> AsyncStream<Data> {
        let msg = message  // capture by value for @Sendable closure
        return AsyncStream { continuation in
            if let data = try? JSONEncoder().encode(["type": "error", "message": msg]),
               !data.isEmpty {
                continuation.yield(MessageFraming.frame(data))
            }
            continuation.finish()
        }
    }
}
