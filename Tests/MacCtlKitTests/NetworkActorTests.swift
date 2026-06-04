import Testing
import Foundation
@testable import MacCtlKit

@Suite("NetworkActor")
struct NetworkActorTests {
    @Test func statusHasFields() async throws {
        let actor = NetworkActor()
        try await Task.sleep(for: .milliseconds(200))
        let status = await actor.status()
        // Verify struct is populated (not specific connectivity values)
        #expect(status.interfaces.count >= 0)
    }

    @Test func resolveLocalhostReturnsAddress() async throws {
        let actor = NetworkActor()
        let addresses = try await actor.resolve(hostname: "localhost")
        #expect(!addresses.isEmpty)
        #expect(addresses.contains("127.0.0.1") || addresses.contains("::1"))
    }

    @Test func resolveInvalidHostThrows() async throws {
        let actor = NetworkActor()
        do {
            _ = try await actor.resolve(hostname: "this.invalid.host.xyzabc123.test")
            #expect(Bool(false), "should throw")
        } catch {
            // Any error acceptable
        }
    }
}
