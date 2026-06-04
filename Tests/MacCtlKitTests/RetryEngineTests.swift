import Testing
import Foundation
@testable import MacCtlKit

@Suite("RetryEngine")
struct RetryEngineTests {
    @Test func succeedsFirstAttempt() async throws {
        nonisolated(unsafe) var calls = 0
        let r = try await RetryEngine.run {
            calls += 1
            return 42
        }
        #expect(r.value == 42)
        #expect(r.attempts == 1)
        #expect(calls == 1)
    }

    @Test func retriesOnFailureThenSucceeds() async throws {
        nonisolated(unsafe) var calls = 0
        let r: RetryResult<String> = try await RetryEngine.run(
            attempts: 3, delays: [.milliseconds(1), .milliseconds(1)]
        ) {
            calls += 1
            if calls < 3 { throw RPCError.elementNotFound("btn", app: "test") }
            return "ok"
        }
        #expect(r.value == "ok")
        #expect(r.attempts == 3)
    }

    @Test func exhaustsAttemptsAndThrows() async throws {
        nonisolated(unsafe) var calls = 0
        do {
            let _: RetryResult<Int> = try await RetryEngine.run(
                attempts: 3, delays: [.milliseconds(1), .milliseconds(1)]
            ) {
                calls += 1
                throw RPCError.elementNotFound("btn", app: "test")
            }
            #expect(Bool(false), "should have thrown")
        } catch let err as RPCError {
            #expect(err.code == 2)
        }
        #expect(calls == 3)
    }

    @Test func doesNotRetryPermissionErrors() async throws {
        nonisolated(unsafe) var calls = 0
        do {
            let _: RetryResult<Int> = try await RetryEngine.run(
                attempts: 3, delays: [.milliseconds(1), .milliseconds(1)]
            ) {
                calls += 1
                throw RPCError(code: 1, message: "permission denied")
            }
        } catch { }
        #expect(calls == 1)
    }

    @Test func doesNotRetryInvalidArgErrors() async throws {
        nonisolated(unsafe) var calls = 0
        do {
            let _: RetryResult<Int> = try await RetryEngine.run(
                attempts: 3, delays: [.milliseconds(1), .milliseconds(1)]
            ) {
                calls += 1
                throw RPCError.operationFailed("bad arg")
            }
        } catch { }
        #expect(calls == 1)
    }
}
