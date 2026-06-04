import Foundation

public typealias DispatchNext = @Sendable (String, [String: JSONValue]) async throws -> [String: JSONValue]
public typealias MiddlewareFn = @Sendable (String, [String: JSONValue], @escaping DispatchNext) async throws -> [String: JSONValue]

/// Builds a middleware chain. Middlewares wrap left-to-right: first is outermost.
public func buildMiddlewareChain(
    middlewares: [MiddlewareFn],
    base: @escaping DispatchNext
) -> DispatchNext {
    middlewares.reversed().reduce(base) { next, mw in
        let capturedNext = next
        return { method, params in
            try await mw(method, params, capturedNext)
        }
    }
}
