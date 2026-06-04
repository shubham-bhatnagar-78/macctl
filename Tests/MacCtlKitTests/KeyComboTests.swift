import Testing
import CoreGraphics
@testable import MacCtlKit

@Suite("KeyCombo")
struct KeyComboTests {
    @Test func cmdS() {
        let combo = KeyCombo("s", .maskCommand)
        #expect(combo.key == "s")
        #expect(combo.modifiers == .maskCommand)
    }

    @Test func cmdShiftN() {
        let combo = KeyCombo("n", [.maskCommand, .maskShift])
        #expect(combo.modifiers.contains(.maskCommand))
        #expect(combo.modifiers.contains(.maskShift))
    }

    @Test func noModifiers() {
        let combo = KeyCombo(" ")
        #expect(combo.key == " ")
        #expect(combo.modifiers == [])
    }

    @Test func responseMetaLayer() {
        let meta = ResponseMeta(durationMs: 1.2, layer: "keyboard",
                                sessionID: "s1", daemonVersion: "1.0.0")
        #expect(meta.layer == "keyboard")
        #expect(meta.durationMs == 1.2)
        #expect(meta.retries == 0)
    }

    @Test func operationResultSuccess() {
        let meta = ResponseMeta(durationMs: 2.0, layer: "ax", sessionID: "s1")
        let result = OperationResult(data: ["elementId": .string("E1")], meta: meta)
        #expect(result.data["elementId"] == .string("E1"))
        #expect(result.meta.layer == "ax")
    }
}
