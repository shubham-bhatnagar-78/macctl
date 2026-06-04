import Testing
import Foundation
@testable import MacCtlKit

@Suite("SystemStateActor")
struct SystemStateActorTests {
    @Test func getVolumeReturnsValidRange() async throws {
        let actor = SystemStateActor()
        let vol = await actor.volume()
        #expect(vol >= 0.0 && vol <= 1.0)
    }

    @Test func setAndGetVolumeRoundTrip() async throws {
        let actor = SystemStateActor()
        let original = await actor.volume()
        await actor.setVolume(0.42)
        try await Task.sleep(for: .milliseconds(50))
        let after = await actor.volume()
        #expect(abs(after - 0.42) < 0.1)
        await actor.setVolume(original)
    }

    @Test func muteToggle() async throws {
        let actor = SystemStateActor()
        let wasMuted = await actor.isMuted()
        await actor.setMuted(!wasMuted)
        let now = await actor.isMuted()
        #expect(now == !wasMuted)
        await actor.setMuted(wasMuted)
    }
}
