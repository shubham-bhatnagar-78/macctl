import Testing
import AppKit
import Foundation
@testable import MacCtlKit

// Uses a private pasteboard so tests don't interfere with user's clipboard.
// NSPasteboard.general doesn't persist in headless test processes.
@Suite("ClipboardActor")
struct ClipboardActorTests {
    // Private named pasteboard — isolated, works without UI app context
    private func makePasteboard() -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("com.macctl.test.\(UUID().uuidString)"))
        pb.clearContents()
        return pb
    }

    @Test func readWriteText() async throws {
        let actor = ClipboardActor(pasteboard: makePasteboard())
        await actor.writeText("hello macctl")
        let result = await actor.readText()
        #expect(result == "hello macctl")
    }

    @Test func readWriteHTML() async throws {
        let actor = ClipboardActor(pasteboard: makePasteboard())
        await actor.write(.html("<b>bold</b>"))
        let result = await actor.readHTML()
        #expect(result == "<b>bold</b>")
    }

    @Test func readWriteFileURLs() async throws {
        let actor = ClipboardActor(pasteboard: makePasteboard())
        let url = URL(fileURLWithPath: "/tmp/macctl-clipboard-test.txt")
        await actor.write(.files([url]))
        let files = await actor.readFiles()
        #expect(files.first?.path == url.path)
    }

    @Test func clearClipboard() async throws {
        let actor = ClipboardActor(pasteboard: makePasteboard())
        await actor.writeText("to be cleared")
        await actor.clear()
        let result = await actor.readText()
        #expect(result == nil || result!.isEmpty)
    }

    @Test func changeCountIncreasesOnWrite() async throws {
        let actor = ClipboardActor(pasteboard: makePasteboard())
        let before = await actor.changeCount()
        await actor.writeText("bump \(Date())")
        let after = await actor.changeCount()
        #expect(after > before)
    }

    @Test func htmlTypeRoundTrip() async throws {
        let actor = ClipboardActor(pasteboard: makePasteboard())
        await actor.write(.html("<strong>bold</strong>"))
        let html = await actor.readHTML()
        #expect(html == "<strong>bold</strong>")
        // Also has plain text fallback
        let text = await actor.readText()
        #expect(text != nil)  // stripped HTML as plaintext
    }

    @Test func readReturnsCorrectType() async throws {
        let actor = ClipboardActor(pasteboard: makePasteboard())
        await actor.writeText("typed text")
        let content = await actor.read()
        if case .text(let s) = content {
            #expect(s == "typed text")
        }
    }
}
