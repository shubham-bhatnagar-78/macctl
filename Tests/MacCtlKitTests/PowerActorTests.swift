import Testing
import Foundation
@testable import MacCtlKit

@Suite("PowerActor")
struct PowerActorTests {
    @Test func caffeinateAndRelease() async throws {
        let actor = PowerActor()
        let token = try await actor.preventSleep(reason: "test")
        await actor.releaseSleep(token: token)
    }

    @Test func preventSleepTokenIsUnique() async throws {
        let actor = PowerActor()
        let t1 = try await actor.preventSleep(reason: "test1")
        let t2 = try await actor.preventSleep(reason: "test2")
        #expect(t1 != t2)
        await actor.releaseSleep(token: t1)
        await actor.releaseSleep(token: t2)
    }

    @Test func activeSleepPreventionsCount() async throws {
        let actor = PowerActor()
        let before = await actor.activePreventionCount()
        let t1 = try await actor.preventSleep(reason: "test")
        let during = await actor.activePreventionCount()
        #expect(during == before + 1)
        await actor.releaseSleep(token: t1)
        let after = await actor.activePreventionCount()
        #expect(after == before)
    }

    @Test func releaseAllClearsAll() async throws {
        let actor = PowerActor()
        let _ = try await actor.preventSleep(reason: "t1")
        let _ = try await actor.preventSleep(reason: "t2")
        await actor.releaseAllSleep()
        #expect(await actor.activePreventionCount() == 0)
    }
}
