import Testing
import Foundation
@testable import MacCtlKit

@Suite("MessageFraming")
struct MessageFramingTests {
    @Test func frameAndParse() throws {
        let original = Data("hello world".utf8)
        var buffer = MessageFraming.frame(original)
        let parsed = try MessageFraming.parse(&buffer)
        #expect(parsed == original)
    }

    @Test func incompleteFrameReturnsNil() throws {
        // 4-byte header says 11 bytes, only 1 byte of payload present
        var partial = Data([0, 0, 0, 11, 0x68])
        let parsed = try MessageFraming.parse(&partial)
        #expect(parsed == nil)
    }

    @Test func multipleMessages() throws {
        let msg1 = Data("first".utf8)
        let msg2 = Data("second".utf8)
        var buffer = MessageFraming.frame(msg1) + MessageFraming.frame(msg2)
        let p1 = try MessageFraming.parse(&buffer)
        let p2 = try MessageFraming.parse(&buffer)
        #expect(p1 == msg1)
        #expect(p2 == msg2)
        #expect(buffer.isEmpty)
    }

    @Test func emptyBufferReturnsNil() throws {
        var empty = Data()
        let result = try MessageFraming.parse(&empty)
        #expect(result == nil)
    }
}
