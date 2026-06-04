import Testing
import Foundation
@testable import MacCtlKit

@Suite("RPCTypes")
struct RPCTypesTests {
    @Test func requestRoundTrip() throws {
        let req = RPCRequest(id: "r1", method: "click", params: [
            "app": .string("com.apple.Safari"),
            "query": .string("Address bar"),
        ])
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(RPCRequest.self, from: data)
        #expect(decoded.id == "r1")
        #expect(decoded.method == "click")
        #expect(decoded.params?["app"] == .string("com.apple.Safari"))
    }

    @Test func errorRoundTrip() throws {
        let err = RPCError(code: 2, message: "not found", data: RPCErrorData(
            hint: "try macctl see", recoverable: true, errorCode: "elementNotFound"
        ))
        let data = try JSONEncoder().encode(err)
        let decoded = try JSONDecoder().decode(RPCError.self, from: data)
        #expect(decoded.code == 2)
        #expect(decoded.data?.errorCode == "elementNotFound")
    }

    @Test func jsonValueStringRoundTrip() throws {
        let val: JSONValue = .string("hello")
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .string("hello"))
    }

    @Test func jsonValueObjectRoundTrip() throws {
        let val: JSONValue = .object(["key": .int(42)])
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .object(["key": .int(42)]))
    }

    @Test func jsonValueBoolRoundTrip() throws {
        let val: JSONValue = .bool(true)
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .bool(true))
    }
}
