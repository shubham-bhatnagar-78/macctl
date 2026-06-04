import Testing
import Foundation
@testable import MacCtlKit

@Suite("DefaultsActor")
struct DefaultsActorTests {
    private let domain = "com.macctl.test.defaults"

    @Test func writeReadDeleteString() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: domain, key: "strKey", stringValue: "testValue")
        let val = await actor.readString(domain: domain, key: "strKey")
        #expect(val == "testValue")
        await actor.delete(domain: domain, key: "strKey")
        let gone = await actor.readString(domain: domain, key: "strKey")
        #expect(gone == nil)
    }

    @Test func writeReadBool() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: domain, key: "boolKey", boolValue: true)
        let val = await actor.readBool(domain: domain, key: "boolKey")
        #expect(val == true)
        await actor.delete(domain: domain, key: "boolKey")
    }

    @Test func writeReadInt() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: domain, key: "intKey", intValue: 42)
        let val = await actor.readInt(domain: domain, key: "intKey")
        #expect(val == 42)
        await actor.delete(domain: domain, key: "intKey")
    }

    @Test func existsAfterWrite() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: domain, key: "existKey", stringValue: "yes")
        #expect(await actor.exists(domain: domain, key: "existKey"))
        await actor.delete(domain: domain, key: "existKey")
        #expect(!(await actor.exists(domain: domain, key: "existKey")))
    }

    @Test func readAllReturnsStringMap() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: domain, key: "k1", stringValue: "v1")
        let all = await actor.readAll(domain: domain)
        #expect(all["k1"] == "v1")
        await actor.delete(domain: domain, key: "k1")
    }
}
