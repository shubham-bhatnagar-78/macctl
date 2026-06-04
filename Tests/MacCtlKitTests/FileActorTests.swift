import Testing
import Foundation
@testable import MacCtlKit

@Suite("FileActor")
struct FileActorTests {
    private func makeTestDir() -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let dir = tmp.appendingPathComponent("macctl-file-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func writeAndReadText() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("test.txt").path
        try await actor.write(path: path, content: "hello macctl")
        let content = try await actor.read(path: path)
        #expect(content == "hello macctl")
    }

    @Test func writeAndReadBinary() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("test.bin").path
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])
        try await actor.writeData(path: path, data: data)
        let read = try await actor.readData(path: path)
        #expect(read == data)
    }

    @Test func statReturnsInfo() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("stat.txt").path
        try await actor.write(path: path, content: "stats test")
        let info = try await actor.stat(path: path)
        #expect(info.size > 0)
        #expect(!info.isDirectory)
        #expect(info.exists)
    }

    @Test func listDirectory() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let subdir = dir.appendingPathComponent("listdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "a".write(to: subdir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: subdir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let items = try await actor.list(path: subdir.path)
        #expect(items.count == 2)
        #expect(items.map(\.name).sorted() == ["a.txt", "b.txt"])
    }

    @Test func copyFile() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let src = dir.appendingPathComponent("copy-src.txt").path
        let dst = dir.appendingPathComponent("copy-dst.txt").path
        try await actor.write(path: src, content: "copy me")
        try await actor.copy(from: src, to: dst)
        let content = try await actor.read(path: dst)
        #expect(content == "copy me")
        #expect(FileManager.default.fileExists(atPath: src))
    }

    @Test func moveFile() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let src = dir.appendingPathComponent("move-src.txt").path
        let dst = dir.appendingPathComponent("move-dst.txt").path
        try await actor.write(path: src, content: "move me")
        try await actor.move(from: src, to: dst)
        let content = try await actor.read(path: dst)
        #expect(content == "move me")
        #expect(!FileManager.default.fileExists(atPath: src))
    }

    @Test func deleteFile() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("delete.txt").path
        try await actor.write(path: path, content: "delete me")
        #expect(await actor.exists(path: path))
        try await actor.delete(path: path)
        #expect(!(await actor.exists(path: path)))
    }

    @Test func mkdirCreatesDirectory() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("newdir/nested").path
        try await actor.mkdir(path: path)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test func writeAtomicOverwrite() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("atomic.txt").path
        try await actor.write(path: path, content: "v1")
        try await actor.write(path: path, content: "v2")
        let content = try await actor.read(path: path)
        #expect(content == "v2")
    }

    @Test func tagsRoundTrip() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("tagged.txt").path
        try await actor.write(path: path, content: "tagged file")
        try actor.setTags(["Red", "Important"], path: path)
        let tags = try actor.tags(path: path)
        #expect(tags.sorted() == ["Important", "Red"])
    }

    @Test func addTagsDoesNotDuplicate() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("addtag.txt").path
        try await actor.write(path: path, content: "x")
        try actor.setTags(["Red"], path: path)
        try actor.addTags(["Red", "Blue"], path: path)
        let tags = try actor.tags(path: path)
        #expect(tags.filter { $0 == "Red" }.count == 1)
        #expect(tags.contains("Blue"))
    }

    @Test func removeTagsWorks() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("removetag.txt").path
        try await actor.write(path: path, content: "x")
        try actor.setTags(["Red", "Blue", "Green"], path: path)
        try actor.removeTags(["Blue"], path: path)
        let tags = try actor.tags(path: path)
        #expect(!tags.contains("Blue"))
        #expect(tags.contains("Red") && tags.contains("Green"))
    }

    @Test func emptyTagsClearsXattr() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("cleartag.txt").path
        try await actor.write(path: path, content: "x")
        try actor.setTags(["Red"], path: path)
        try actor.setTags([], path: path)
        let tags = try actor.tags(path: path)
        #expect(tags.isEmpty)
    }

    @Test func statReturnsCorrectSize() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("sizefile.txt").path
        let content = "exactly 20 bytes!!"
        try await actor.write(path: path, content: content)
        let info = try await actor.stat(path: path)
        #expect(info.size == Int64(content.utf8.count))
        #expect(!info.isDirectory)
        #expect(!info.isICloud)
    }

    @Test func listExcludesHiddenByDefault() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let subdir = dir.appendingPathComponent("listcheck")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "v".write(to: subdir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "h".write(to: subdir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        let items = try await actor.list(path: subdir.path)
        #expect(items.map(\.name).contains("visible.txt"))
        #expect(!items.map(\.name).contains(".hidden"))
    }

    @Test func existsReturnsTrueAndFalse() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let path = dir.appendingPathComponent("existscheck.txt").path
        #expect(!(await actor.exists(path: path)))
        try await actor.write(path: path, content: "x")
        #expect(await actor.exists(path: path))
    }

    @Test func moveAcrossDirectories() async throws {
        let actor = FileActor()
        let dir = makeTestDir()
        let srcDir = dir.appendingPathComponent("from")
        let dstDir = dir.appendingPathComponent("to")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)
        let src = srcDir.appendingPathComponent("file.txt").path
        let dst = dstDir.appendingPathComponent("file.txt").path
        try await actor.write(path: src, content: "cross-dir")
        try await actor.move(from: src, to: dst)
        #expect(!(await actor.exists(path: src)))
        let content = try await actor.read(path: dst)
        #expect(content == "cross-dir")
    }
}
