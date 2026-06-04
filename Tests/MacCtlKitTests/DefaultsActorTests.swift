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

    @Test func readTypedDetectsInt() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: domain, key: "typedInt", intValue: 99)
        let (val, type_) = await actor.readTyped(domain: domain, key: "typedInt")
        #expect(val == "99")
        #expect(type_ == "int")
        await actor.delete(domain: domain, key: "typedInt")
    }

    @Test func readTypedDetectsBool() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: domain, key: "typedBool", boolValue: true)
        let (val, type_) = await actor.readTyped(domain: domain, key: "typedBool")
        #expect(val == "true")
        #expect(type_ == "bool")
        await actor.delete(domain: domain, key: "typedBool")
    }

    @Test func readTypedDetectsString() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: domain, key: "typedStr", stringValue: "hello")
        let (val, type_) = await actor.readTyped(domain: domain, key: "typedStr")
        #expect(val == "hello")
        #expect(type_ == "string")
        await actor.delete(domain: domain, key: "typedStr")
    }

    @Test func readTypedMissingKeyReturnsNull() async throws {
        let actor = DefaultsActor()
        let (_, type_) = await actor.readTyped(domain: domain, key: "nonexistent_\(UUID().uuidString)")
        #expect(type_ == "null")
    }

    @Test func readAllReturnsStringMap() async throws {
        let actor = DefaultsActor()
        await actor.write(domain: domain, key: "k1", stringValue: "v1")
        let all = await actor.readAll(domain: domain)
        #expect(all["k1"] == "v1")
        await actor.delete(domain: domain, key: "k1")
    }
}
