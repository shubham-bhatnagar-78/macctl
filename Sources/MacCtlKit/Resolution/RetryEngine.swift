import Foundation

public struct RetryResult<T: Sendable>: Sendable {
    public let value: T
    public let attempts: Int  // 1 = succeeded first try
}

/// Retry an async operation with exponential backoff.
/// Stops immediately on non-retryable errors (permissions, invalid args).
public enum RetryEngine {
    @discardableResult
    public static func run<T: Sendable>(
        attempts: Int = 3,
        delays: [Duration] = [.milliseconds(50), .milliseconds(150)],
        operation: @Sendable () async throws -> T
    ) async throws -> RetryResult<T> {
        var lastError: Error = RPCError.operationFailed("no attempts")
        for attempt in 1...attempts {
            do {
                let value = try await operation()
                return RetryResult(value: value, attempts: attempt)
            } catch let rpcError as RPCError {
                // Don't retry permission errors (code 1) or invalid argument errors (code 5)
                if rpcError.code == 1 || rpcError.code == 5 { throw rpcError }
                lastError = rpcError
            } catch {
                lastError = error
            }
            let delayIndex = attempt - 1
            if delayIndex < delays.count {
                try await Task.sleep(for: delays[delayIndex])
            }
        }
        throw lastError
    }
}
