import Foundation

/// Retry an async operation with exponential backoff.
/// Stops immediately on non-retryable errors (permissions, invalid args).
public enum RetryEngine {
    public static func run<T: Sendable>(
        attempts: Int = 3,
        delays: [Duration] = [.milliseconds(50), .milliseconds(150)],
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error = RPCError.operationFailed("no attempts")
        for attempt in 0..<attempts {
            do {
                return try await operation()
            } catch let rpcError as RPCError {
                // Don't retry permission errors or invalid argument errors
                if rpcError.code == 1 || rpcError.code == 5 { throw rpcError }
                lastError = rpcError
            } catch {
                lastError = error
            }
            if attempt < delays.count {
                try await Task.sleep(for: delays[attempt])
            }
        }
        throw lastError
    }
}
