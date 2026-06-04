import Foundation
import Logging

private let mwLogger = Logger(label: "macctl.middleware")

/// Logs method, layer, and duration for every dispatch call.
public let loggingMiddleware: MiddlewareFn = { method, params, next in
    let start = Date()
    do {
        let result = try await next(method, params)
        let ms = Date().timeIntervalSince(start) * 1000
        let layer = result["_layer"]?.stringValue ?? "?"
        mwLogger.debug("\(method) → \(layer) (\(String(format: "%.1f", ms))ms)")
        return result
    } catch {
        let ms = Date().timeIntervalSince(start) * 1000
        mwLogger.warning("\(method) failed (\(String(format: "%.1f", ms))ms): \(error)")
        throw error
    }
}
