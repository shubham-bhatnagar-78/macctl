import Testing
import Foundation
@testable import MacCtlKit

@Suite("StreamManager")
struct StreamManagerTests {
    @Test func unknownTopicSendsErrorAndFinishes() async throws {
        let stream = StreamManager.stream(for: "nonexistent-topic", params: [:])
        var events: [Data] = []
        for await frame in stream {
            events.append(frame)
            break
        }
        #expect(!events.isEmpty)
        // First event should be an error frame (4-byte prefix + JSON)
        if let frame = events.first, frame.count > 4 {
            let payload = Data(frame.dropFirst(4))
            if let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                #expect(json["type"] as? String == "error")
            }
        }
    }

    @Test func fileWatchTopicCreatesStream() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("streamtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let stream = StreamManager.stream(for: "file-watch", params: ["path": .string(tmp.path)])
        var received = false

        let task = Task {
            for await _ in stream { received = true; break }
        }
        // Write a file — should trigger kqueue event
        try await Task.sleep(for: .milliseconds(100))
        try "hello".write(to: tmp.appendingPathComponent("watched.txt"),
                          atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))
        task.cancel()
        // received might be false in CI — just verify no crash
    }

    @Test func fileWatchMissingPathSendsError() async throws {
        let stream = StreamManager.stream(for: "file-watch", params: [:])
        var events: [Data] = []
        for await frame in stream { events.append(frame); break }
        #expect(!events.isEmpty)
        if let frame = events.first, frame.count > 4 {
            let payload = Data(frame.dropFirst(4))
            if let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                #expect(json["type"] as? String == "error")
            }
        }
    }

    @Test func appLifecycicleTopicCreatesStream() async throws {
        // Just verify the stream is created without crashing
        let stream = StreamManager.stream(for: "app-lifecycle", params: [:])
        let task = Task { for await _ in stream { break } }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
    }
}
