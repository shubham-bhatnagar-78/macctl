import Testing
@testable import MacCtlKit

@Suite("Middleware")
struct MiddlewareTests {
    @Test func loggingMiddlewarePassesThrough() async throws {
        nonisolated(unsafe) var called = false
        let base: DispatchNext = { method, _ in
            called = true
            return ["_layer": .string("test"), "result": .string(method)]
        }
        let chain = buildMiddlewareChain(middlewares: [loggingMiddleware], base: base)
        let result = try await chain("test.method", [:])
        #expect(called)
        #expect(result["result"] == .string("test.method"))
    }

    @Test func dryRunBlocksDestructiveMethod() async throws {
        nonisolated(unsafe) var executed = false
        let base: DispatchNext = { _, _ in executed = true; return ["_layer": .string("test")] }
        let chain = buildMiddlewareChain(middlewares: [makeDryRunMiddleware(dryRun: true)], base: base)
        let result = try await chain("file.delete", ["path": .string("/tmp/x")])
        #expect(!executed, "destructive method should not execute in dry-run mode")
        #expect(result["dryRun"] == .bool(true))
        #expect(result["would"] == .string("file.delete"))
    }

    @Test func dryRunAllowsReadOperations() async throws {
        nonisolated(unsafe) var executed = false
        let base: DispatchNext = { _, _ in executed = true; return ["_layer": .string("test")] }
        let chain = buildMiddlewareChain(middlewares: [makeDryRunMiddleware(dryRun: true)], base: base)
        _ = try await chain("file.read", ["path": .string("/tmp/x")])
        #expect(executed, "read operations must still execute in dry-run mode")
    }

    @Test func dryRunDisabledExecutesAll() async throws {
        nonisolated(unsafe) var executed = false
        let base: DispatchNext = { _, _ in executed = true; return ["_layer": .string("test")] }
        let chain = buildMiddlewareChain(middlewares: [makeDryRunMiddleware(dryRun: false)], base: base)
        _ = try await chain("file.delete", [:])
        #expect(executed)
    }

    @Test func middlewareChainCallsInOrder() async throws {
        nonisolated(unsafe) var order: [Int] = []
        func mw(_ n: Int) -> MiddlewareFn {
            { method, params, next in
                order.append(n)
                let r = try await next(method, params)
                order.append(-n)
                return r
            }
        }
        let base: DispatchNext = { _, _ in ["_layer": .string("base")] }
        let chain = buildMiddlewareChain(middlewares: [mw(1), mw(2), mw(3)], base: base)
        _ = try await chain("x", [:])
        #expect(order == [1, 2, 3, -3, -2, -1])
    }

    @Test func middlewareChainPropagatesError() async throws {
        let base: DispatchNext = { _, _ in throw RPCError.operationFailed("test error") }
        let chain = buildMiddlewareChain(middlewares: [loggingMiddleware], base: base)
        do {
            _ = try await chain("error.method", [:])
            #expect(Bool(false), "should have thrown")
        } catch let e as RPCError {
            #expect(e.message == "test error")
        }
    }
}
