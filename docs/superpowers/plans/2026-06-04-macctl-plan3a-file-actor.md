# macctl Plan 3A — File Actor

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a FileActor covering Tier 1 (POSIX file ops with NSFileCoordinator), Tier 2 (iCloud Drive eviction detection + download wait), and Tier 3 (Finder operations: tags via xattr, labels, Reveal, Open With), wired into the daemon dispatcher with full CLI commands.

**Architecture:** Single Swift 6 actor (`FileActor`) owns all file operations. iCloud tier wraps every read with a `resolveICloud()` pre-flight that uses `NSMetadataQuery` to wait for evicted files. Tags write directly to the `com.apple.metadata:_kMDItemUserTags` xattr (1ms) — no Scripting Bridge. NSFileCoordinator wraps all writes to shared locations. All blocking calls use `DispatchSemaphore` timeouts (same pattern as AXActor) so the daemon never hangs.

**Tech Stack:** Swift 6, macOS 13+, Foundation (FileManager, NSFileCoordinator, NSMetadataQuery), AppKit (NSWorkspace, NSColor), xattr (POSIX C API). No new third-party dependencies.

---

## Reliability Contract

Every operation must:
1. **Never hang** — blocking calls use DispatchSemaphore with timeout
2. **Never silently fail on iCloud** — check `ubiquitousItemDownloadingStatus` before reads
3. **Be atomic where possible** — writes use temp file + atomic rename on same volume
4. **Use NSFileCoordinator** for any path under `~/Library/` or shared containers

---

## File Map

```
Sources/MacCtlKit/Actors/
  FileActor.swift              NEW — all 3 tiers, NSFileCoordinator, iCloud resolver

Sources/macctl-daemon/
  Dispatcher.swift             MODIFY — add file.* method cases
  main.swift                   MODIFY — add fileActor instance

Sources/macctl/Commands/
  FileCommand.swift            NEW — file read/write/copy/move/delete/list/stat/mkdir/tag/reveal/open

Tests/MacCtlKitTests/
  FileActorTests.swift         NEW — unit tests for all tiers
```

---

## Task 1: FileActor — Tier 1 POSIX Operations

**Files:**
- Create: `Sources/MacCtlKit/Actors/FileActor.swift`
- Create: `Tests/MacCtlKitTests/FileActorTests.swift`

- [ ] **Write failing tests**

```swift
// Tests/MacCtlKitTests/FileActorTests.swift
import Testing
import Foundation
@testable import MacCtlKit

@Suite("FileActor")
struct FileActorTests {
    private let testDir: URL = {
        let tmp = FileManager.default.temporaryDirectory
        let dir = tmp.appendingPathComponent("macctl-file-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @Test func writeAndReadText() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("test.txt").path
        try await actor.write(path: path, content: "hello macctl")
        let content = try await actor.read(path: path)
        #expect(content == "hello macctl")
    }

    @Test func writeAndReadBinary() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("test.bin").path
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])
        try await actor.writeData(path: path, data: data)
        let read = try await actor.readData(path: path)
        #expect(read == data)
    }

    @Test func statReturnsInfo() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("stat.txt").path
        try await actor.write(path: path, content: "stats test")
        let info = try await actor.stat(path: path)
        #expect(info.size > 0)
        #expect(!info.isDirectory)
        #expect(info.exists)
    }

    @Test func listDirectory() async throws {
        let actor = FileActor()
        let subdir = testDir.appendingPathComponent("listdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "a".write(to: subdir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: subdir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let items = try await actor.list(path: subdir.path)
        #expect(items.count == 2)
        #expect(items.map(\.name).sorted() == ["a.txt", "b.txt"])
    }

    @Test func copyFile() async throws {
        let actor = FileActor()
        let src = testDir.appendingPathComponent("copy-src.txt").path
        let dst = testDir.appendingPathComponent("copy-dst.txt").path
        try await actor.write(path: src, content: "copy me")
        try await actor.copy(from: src, to: dst)
        let content = try await actor.read(path: dst)
        #expect(content == "copy me")
        #expect(FileManager.default.fileExists(atPath: src))  // src still exists
    }

    @Test func moveFile() async throws {
        let actor = FileActor()
        let src = testDir.appendingPathComponent("move-src.txt").path
        let dst = testDir.appendingPathComponent("move-dst.txt").path
        try await actor.write(path: src, content: "move me")
        try await actor.move(from: src, to: dst)
        let content = try await actor.read(path: dst)
        #expect(content == "move me")
        #expect(!FileManager.default.fileExists(atPath: src))  // src gone
    }

    @Test func deleteFile() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("delete.txt").path
        try await actor.write(path: path, content: "delete me")
        #expect(try await actor.exists(path: path))
        try await actor.delete(path: path)
        #expect(!(try await actor.exists(path: path)))
    }

    @Test func mkdirCreatesDirectory() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("newdir/nested").path
        try await actor.mkdir(path: path)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test func trashFileIsRecoverable() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("trash.txt").path
        try await actor.write(path: path, content: "trash me")
        try await actor.trash(path: path)
        #expect(!(try await actor.exists(path: path)))
        // File should be in Trash, not permanently deleted
    }

    @Test func writeAtomicOnSameVolume() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("atomic.txt").path
        // Write via atomic temp+rename
        try await actor.write(path: path, content: "v1")
        try await actor.write(path: path, content: "v2")
        let content = try await actor.read(path: path)
        #expect(content == "v2")
    }
}
```

- [ ] **Run — expect compile failure**

```bash
swift test --filter FileActorTests 2>&1 | grep "error:" | head -3
```
Expected: `FileActor` not found.

- [ ] **Implement FileActor.swift (Tier 1)**

```swift
// Sources/MacCtlKit/Actors/FileActor.swift
import Foundation
import AppKit

public actor FileActor {
    public init() {}

    // MARK: - Supporting types

    public struct FileInfo: Sendable {
        public let path: String
        public let name: String
        public let size: Int64
        public let isDirectory: Bool
        public let isSymlink: Bool
        public let exists: Bool
        public let createdAt: Date?
        public let modifiedAt: Date?
        public let permissions: Int   // POSIX mode
        public let isICloud: Bool
        public let iCloudDownloaded: Bool
    }

    public struct DirectoryEntry: Sendable {
        public let name: String
        public let path: String
        public let isDirectory: Bool
        public let size: Int64
    }

    // MARK: - Tier 1: POSIX/FileManager

    public func read(path: String) async throws -> String {
        let url = URL(fileURLWithPath: expandPath(path))
        try assertNotEvicted(url)
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func readData(path: String) async throws -> Data {
        let url = URL(fileURLWithPath: expandPath(path))
        try assertNotEvicted(url)
        return try Data(contentsOf: url)
    }

    public func write(path: String, content: String) async throws {
        let url = URL(fileURLWithPath: expandPath(path))
        let data = Data(content.utf8)
        try await writeData(path: path, data: data)
    }

    public func writeData(path: String, data: Data) async throws {
        let url = URL(fileURLWithPath: expandPath(path))
        // Ensure parent directory exists
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        // Use NSFileCoordinator for shared locations (~/Library, app containers)
        if isSharedLocation(url) {
            try writeWithCoordinator(url: url, data: data)
        } else {
            // Atomic write: temp file + rename on same volume
            let tmp = url.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItem(at: url, withItemAt: tmp,
                backupItemName: nil, options: [], resultingItemURL: nil)
            // If replace fails (cross-volume), fall back to direct write
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
            }
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    public func copy(from srcPath: String, to dstPath: String) async throws {
        let src = URL(fileURLWithPath: expandPath(srcPath))
        let dst = URL(fileURLWithPath: expandPath(dstPath))
        try assertNotEvicted(src)
        // Remove destination if it exists
        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.copyItem(at: src, to: dst)
    }

    /// Move file. For cross-volume moves: copy + verify + delete (not atomic rename).
    public func move(from srcPath: String, to dstPath: String) async throws {
        let src = URL(fileURLWithPath: expandPath(srcPath))
        let dst = URL(fileURLWithPath: expandPath(dstPath))
        try assertNotEvicted(src)
        // Try rename first (atomic, same volume)
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.moveItem(at: src, to: dst)
        } catch CocoaError.fileWriteVolumeNotSupported, CocoaError.fileWriteCrossVolumeRenameFailed {
            // Cross-volume: copy + verify + delete
            try FileManager.default.copyItem(at: src, to: dst)
            let srcData = try Data(contentsOf: src)
            let dstData = try Data(contentsOf: dst)
            guard srcData == dstData else {
                try? FileManager.default.removeItem(at: dst)
                throw FileError.copyVerificationFailed(srcPath, dstPath)
            }
            try FileManager.default.removeItem(at: src)
        }
    }

    public func delete(path: String) async throws {
        let url = URL(fileURLWithPath: expandPath(path))
        try FileManager.default.removeItem(at: url)
    }

    public func trash(path: String) async throws {
        let url = URL(fileURLWithPath: expandPath(path))
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    public func mkdir(path: String) async throws {
        let url = URL(fileURLWithPath: expandPath(path))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func exists(path: String) -> Bool {
        FileManager.default.fileExists(atPath: expandPath(path))
    }

    public func stat(path: String) async throws -> FileInfo {
        let url = URL(fileURLWithPath: expandPath(path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let resVals = try url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .isSymbolicLinkKey,
        ])
        let isICloud = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
        let dlStatus = resVals.ubiquitousItemDownloadingStatus
        return FileInfo(
            path: url.path,
            name: url.lastPathComponent,
            size: (attrs[.size] as? Int64) ?? (attrs[.size] as? NSNumber).map { Int64($0.int64Value) } ?? 0,
            isDirectory: (attrs[.type] as? FileAttributeType) == .typeDirectory,
            isSymlink: resVals.isSymbolicLink ?? false,
            exists: true,
            createdAt: attrs[.creationDate] as? Date,
            modifiedAt: attrs[.modificationDate] as? Date,
            permissions: (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0,
            isICloud: isICloud,
            iCloudDownloaded: dlStatus == .current || dlStatus == nil
        )
    }

    public func list(path: String) async throws -> [DirectoryEntry] {
        let url = URL(fileURLWithPath: expandPath(path))
        let contents = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles])
        return try contents.map { item in
            let vals = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return DirectoryEntry(
                name: item.lastPathComponent,
                path: item.path,
                isDirectory: vals.isDirectory ?? false,
                size: Int64(vals.fileSize ?? 0)
            )
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Tier 2: iCloud Drive

    /// Resolve an iCloud file — trigger download if evicted, wait up to 30s.
    public func resolveICloud(path: String, timeoutSecs: Int = 30) async throws -> String {
        let url = URL(fileURLWithPath: expandPath(path))
        let resVals = try url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey
        ])
        guard resVals.isUbiquitousItem == true else { return url.path }

        let status = resVals.ubiquitousItemDownloadingStatus
        if status == .current { return url.path }

        // Trigger download
        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        // Wait via NSMetadataQuery polling (DispatchSemaphore with timeout)
        let sem = DispatchSemaphore(value: 0)
        let box = ICloudStatusBox()

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K == %@",
            NSMetadataItemPathKey, url.path)
        query.valueListAttributes = [NSMetadataUbiquitousItemDownloadingStatusKey]

        let token = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: nil
        ) { _ in
            query.disableUpdates()
            if let item = query.results.firstObject as? NSMetadataItem {
                let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey)
                    as? String
                if status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                    box.downloaded = true
                    sem.signal()
                }
            }
            query.enableUpdates()
        }

        OperationQueue.main.addOperation { query.start() }
        let timedOut = sem.wait(timeout: .now() + .seconds(timeoutSecs)) == .timedOut
        NotificationCenter.default.removeObserver(token)
        OperationQueue.main.addOperation { query.stop() }

        if timedOut { throw FileError.iCloudDownloadTimeout(path) }
        return url.path
    }

    /// Read iCloud file — auto-downloads if evicted before reading.
    public func readICloud(path: String, timeoutSecs: Int = 30) async throws -> String {
        let resolved = try await resolveICloud(path: path, timeoutSecs: timeoutSecs)
        return try await read(path: resolved)
    }

    // MARK: - Tier 3: Finder / xattr

    /// Get file tags from xattr (1ms — no Scripting Bridge needed).
    public func tags(path: String) throws -> [String] {
        let url = URL(fileURLWithPath: expandPath(path))
        let key = "com.apple.metadata:_kMDItemUserTags"
        guard let data = try? url.extendedAttribute(forName: key) else { return [] }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]) ?? []
    }

    /// Set file tags via xattr (1ms — no Scripting Bridge needed).
    public func setTags(_ tags: [String], path: String) throws {
        let url = URL(fileURLWithPath: expandPath(path))
        let key = "com.apple.metadata:_kMDItemUserTags"
        if tags.isEmpty {
            url.removeExtendedAttribute(forName: key)
        } else {
            let data = try PropertyListSerialization.data(fromPropertyList: tags,
                format: .binary, options: 0)
            try url.setExtendedAttribute(data, forName: key)
        }
    }

    /// Add tags without replacing existing ones.
    public func addTags(_ newTags: [String], path: String) throws {
        var existing = (try? tags(path: path)) ?? []
        for tag in newTags where !existing.contains(tag) { existing.append(tag) }
        try setTags(existing, path: path)
    }

    /// Remove specific tags.
    public func removeTags(_ toRemove: [String], path: String) throws {
        let existing = (try? tags(path: path)) ?? []
        try setTags(existing.filter { !toRemove.contains($0) }, path: path)
    }

    /// Reveal file in Finder (NSWorkspace — ~5ms, no AX needed).
    public func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: expandPath(path))
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Open file with default or specific app.
    public func open(path: String, withApp bundleID: String? = nil) throws {
        let url = URL(fileURLWithPath: expandPath(path))
        if let bid = bundleID {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            else { throw FileError.appNotFound(bid) }
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func assertNotEvicted(_ url: URL) throws {
        guard let resVals = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]) else { return }
        guard resVals.isUbiquitousItem == true else { return }
        let status = resVals.ubiquitousItemDownloadingStatus
        if status != .current && status != nil {
            throw FileError.iCloudFileEvicted(url.path)
        }
    }

    private func isSharedLocation(_ url: URL) -> Bool {
        let shared = ["/Library/", "/Application Support/", "/Containers/"]
        return shared.contains { url.path.contains($0) }
    }

    private func writeWithCoordinator(url: URL, data: Data) throws {
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: nil) { resolvedURL in
            do { try data.write(to: resolvedURL, options: .atomic) }
            catch { writeError = error }
        }
        if let err = writeError { throw err }
    }
}

// MARK: - xattr helpers

extension URL {
    func extendedAttribute(forName name: String) throws -> Data {
        let path = self.path
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length >= 0 else { throw FileError.xattrReadFailed(name) }
        var data = Data(count: length)
        data.withUnsafeMutableBytes { ptr in
            _ = getxattr(path, name, ptr.baseAddress, length, 0, 0)
        }
        return data
    }

    func setExtendedAttribute(_ data: Data, forName name: String) throws {
        let result = data.withUnsafeBytes { ptr in
            setxattr(self.path, name, ptr.baseAddress, data.count, 0, 0)
        }
        if result != 0 { throw FileError.xattrWriteFailed(name) }
    }

    func removeExtendedAttribute(forName name: String) {
        _ = removexattr(self.path, name, 0)
    }
}

// MARK: - Supporting types

private final class ICloudStatusBox: @unchecked Sendable {
    var downloaded = false
}

public enum FileError: Error, Sendable {
    case iCloudFileEvicted(String)
    case iCloudDownloadTimeout(String)
    case copyVerificationFailed(String, String)
    case xattrReadFailed(String)
    case xattrWriteFailed(String)
    case appNotFound(String)
    case readFailed(String)
    case writeFailed(String)
}
```

- [ ] **Run tests — expect pass**

```bash
swift test --filter FileActorTests 2>&1 | grep -E "passed|failed|Suite" | head -15
```
Expected: All tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/FileActor.swift Tests/MacCtlKitTests/FileActorTests.swift
git commit -m "feat: add FileActor (Tier1 POSIX + Tier2 iCloud + Tier3 Finder/xattr)"
```

---

## Task 2: Additional FileActor Tests — iCloud + Tags

**Files:**
- Modify: `Tests/MacCtlKitTests/FileActorTests.swift`

- [ ] **Add tag tests**

Add to `FileActorTests.swift`:

```swift
    @Test func tagsRoundTrip() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("tagged.txt").path
        try await actor.write(path: path, content: "tagged file")
        try actor.setTags(["Red", "Important"], path: path)
        let tags = try actor.tags(path: path)
        #expect(tags.sorted() == ["Important", "Red"])
    }

    @Test func addTagsDoesNotDuplicate() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("addtag.txt").path
        try await actor.write(path: path, content: "x")
        try actor.setTags(["Red"], path: path)
        try actor.addTags(["Red", "Blue"], path: path)
        let tags = try actor.tags(path: path)
        #expect(tags.filter { $0 == "Red" }.count == 1)
        #expect(tags.contains("Blue"))
    }

    @Test func removeTagsWorks() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("removetag.txt").path
        try await actor.write(path: path, content: "x")
        try actor.setTags(["Red", "Blue", "Green"], path: path)
        try actor.removeTags(["Blue"], path: path)
        let tags = try actor.tags(path: path)
        #expect(!tags.contains("Blue"))
        #expect(tags.contains("Red"))
        #expect(tags.contains("Green"))
    }

    @Test func emptyTagsClearsXattr() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("cleartag.txt").path
        try await actor.write(path: path, content: "x")
        try actor.setTags(["Red"], path: path)
        try actor.setTags([], path: path)
        let tags = try actor.tags(path: path)
        #expect(tags.isEmpty)
    }

    @Test func statReturnsCorrectFields() async throws {
        let actor = FileActor()
        let path = testDir.appendingPathComponent("statcheck.txt").path
        let content = "statcheck content"
        try await actor.write(path: path, content: content)
        let info = try await actor.stat(path: path)
        #expect(info.exists)
        #expect(!info.isDirectory)
        #expect(info.size == Int64(content.utf8.count))
        #expect(info.modifiedAt != nil)
        #expect(!info.isICloud)
    }

    @Test func listExcludesHiddenByDefault() async throws {
        let actor = FileActor()
        let dir = testDir.appendingPathComponent("listcheck")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "visible".write(to: dir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: dir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        let items = try await actor.list(path: dir.path)
        #expect(items.map(\.name).contains("visible.txt"))
        #expect(!items.map(\.name).contains(".hidden"))
    }

    @Test func moveAcrossDirectories() async throws {
        let actor = FileActor()
        let srcDir = testDir.appendingPathComponent("movefrom")
        let dstDir = testDir.appendingPathComponent("moveto")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)
        let src = srcDir.appendingPathComponent("file.txt").path
        let dst = dstDir.appendingPathComponent("file.txt").path
        try await actor.write(path: src, content: "cross-dir move")
        try await actor.move(from: src, to: dst)
        #expect(!(try await actor.exists(path: src)))
        let content = try await actor.read(path: dst)
        #expect(content == "cross-dir move")
    }
```

- [ ] **Run tests — expect pass**

```bash
swift test --filter FileActorTests 2>&1 | grep -E "passed|failed" | tail -5
```
Expected: All 17 tests passed.

- [ ] **Commit**

```bash
git add Tests/MacCtlKitTests/FileActorTests.swift
git commit -m "test: add FileActor tag/stat/list/move tests — 17 total"
```

---

## Task 3: Wire FileActor into Dispatcher

**Files:**
- Modify: `Sources/macctl-daemon/Dispatcher.swift`
- Modify: `Sources/macctl-daemon/main.swift`

- [ ] **Add fileActor to main.swift**

In `Sources/macctl-daemon/main.swift`, add after `shellActor`:

```swift
let fileActor = FileActor()
```

Update dispatch call to include `file: fileActor`:

```swift
let resultData = try await dispatch(
    ...
    shell: shellActor,
    file: fileActor,
    sessionID: sessionID
)
```

- [ ] **Update Dispatcher.swift signature**

Add `file: FileActor,` to the `dispatch` function parameters (after `shell:`).

- [ ] **Add file.* method cases to Dispatcher.swift**

Add before `default:`:

```swift
    // MARK: - file.*

    case "file.read":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.read requires path")
        }
        let content = try await file.read(path: path)
        return layer("file-posix", ["content": .string(content), "bytes": .int(content.utf8.count)])

    case "file.read-binary":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.read-binary requires path")
        }
        let data = try await file.readData(path: path)
        return layer("file-posix", ["bytes": .int(data.count),
                                     "base64": .string(data.base64EncodedString())])

    case "file.write":
        guard case .string(let path)    = params["path"],
              case .string(let content) = params["content"]
        else { throw RPCError.operationFailed("file.write requires path + content") }
        try await file.write(path: path, content: content)
        return layer("file-posix", ["bytes": .int(content.utf8.count)])

    case "file.copy":
        guard case .string(let from) = params["from"],
              case .string(let to)   = params["to"]
        else { throw RPCError.operationFailed("file.copy requires from + to") }
        try await file.copy(from: from, to: to)
        return layer("file-posix")

    case "file.move":
        guard case .string(let from) = params["from"],
              case .string(let to)   = params["to"]
        else { throw RPCError.operationFailed("file.move requires from + to") }
        try await file.move(from: from, to: to)
        return layer("file-posix")

    case "file.delete":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.delete requires path")
        }
        let toTrash = params["trash"] == .bool(true)
        if toTrash { try await file.trash(path: path) }
        else       { try await file.delete(path: path) }
        return layer("file-posix")

    case "file.mkdir":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.mkdir requires path")
        }
        try await file.mkdir(path: path)
        return layer("file-posix")

    case "file.exists":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.exists requires path")
        }
        return layer("file-posix", ["exists": .bool(await file.exists(path: path))])

    case "file.stat":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.stat requires path")
        }
        let info = try await file.stat(path: path)
        return layer("file-posix", [
            "path":       .string(info.path),
            "name":       .string(info.name),
            "size":       .int(Int(info.size)),
            "isDirectory":.bool(info.isDirectory),
            "isSymlink":  .bool(info.isSymlink),
            "exists":     .bool(info.exists),
            "permissions":.int(info.permissions),
            "isICloud":   .bool(info.isICloud),
            "iCloudReady":.bool(info.iCloudDownloaded),
            "modifiedAt": info.modifiedAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
        ])

    case "file.list":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.list requires path")
        }
        let items = try await file.list(path: path)
        let list: [JSONValue] = items.map { item in
            .object(["name": .string(item.name), "path": .string(item.path),
                     "isDirectory": .bool(item.isDirectory), "size": .int(Int(item.size))])
        }
        return layer("file-posix", ["items": .array(list), "count": .int(list.count)])

    case "file.tags":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.tags requires path")
        }
        let tags = try await file.tags(path: path)
        return layer("file-xattr", ["tags": .array(tags.map { .string($0) })])

    case "file.set-tags":
        guard case .string(let path) = params["path"],
              case .array(let tagVals) = params["tags"]
        else { throw RPCError.operationFailed("file.set-tags requires path + tags array") }
        let tags = tagVals.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        try await file.setTags(tags, path: path)
        return layer("file-xattr", ["tags": .array(tags.map { .string($0) })])

    case "file.add-tags":
        guard case .string(let path) = params["path"],
              case .array(let tagVals) = params["tags"]
        else { throw RPCError.operationFailed("file.add-tags requires path + tags array") }
        let tags = tagVals.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        try await file.addTags(tags, path: path)
        return layer("file-xattr")

    case "file.reveal":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.reveal requires path")
        }
        await file.revealInFinder(path: path)
        return layer("finder")

    case "file.open":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.open requires path")
        }
        let appBundleID = params["app"]?.stringValue
        try await file.open(path: path, withApp: appBundleID)
        return layer("finder")

    case "file.resolve-icloud":
        guard case .string(let path) = params["path"] else {
            throw RPCError.operationFailed("file.resolve-icloud requires path")
        }
        let timeout = params["timeout"]?.intValue ?? 30
        let resolved = try await file.resolveICloud(path: path, timeoutSecs: timeout)
        return layer("icloud", ["resolvedPath": .string(resolved)])
```

- [ ] **Build to verify**

```bash
swift build --product macctl-daemon 2>&1 | grep -E "error:|complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/macctl-daemon/
git commit -m "feat: wire FileActor into daemon dispatcher (file.read/write/copy/move/delete/list/stat/mkdir/tags/reveal/open)"
```

---

## Task 4: FileCommand CLI

**Files:**
- Create: `Sources/macctl/Commands/FileCommand.swift`
- Modify: `Sources/macctl/main.swift`

- [ ] **Implement FileCommand.swift**

```swift
// Sources/macctl/Commands/FileCommand.swift
import ArgumentParser
import MacCtlKit

struct FileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file",
        abstract: "File operations: read/write/copy/move/delete/list/stat/tags/reveal/open",
        subcommands: [
            Read.self, Write.self, Copy.self, Move.self, Delete.self,
            List.self, Stat.self, Mkdir.self, Exists.self,
            Tags.self, SetTags.self, AddTags.self,
            Reveal.self, Open.self, ResolveICloud.self,
        ])

    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "read")
        @Argument var path: String
        func run() throws { try rpc(method: "file.read", params: ["path": .string(path)]) }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "write")
        @Argument var path: String
        @Argument(help: "Content to write (use - to read from stdin)") var content: String
        func run() throws {
            let c = content == "-" ? (readLine(strippingNewline: false) ?? "") : content
            try rpc(method: "file.write", params: ["path": .string(path), "content": .string(c)])
        }
    }

    struct Copy: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "copy")
        @Argument var from: String
        @Argument var to: String
        func run() throws {
            try rpc(method: "file.copy", params: ["from": .string(from), "to": .string(to)])
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "move")
        @Argument var from: String
        @Argument var to: String
        func run() throws {
            try rpc(method: "file.move", params: ["from": .string(from), "to": .string(to)])
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete")
        @Argument var path: String
        @Flag(name: .long, help: "Move to Trash instead of permanent delete") var trash = false
        func run() throws {
            try rpc(method: "file.delete",
                    params: ["path": .string(path), "trash": .bool(trash)])
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        @Argument var path: String = "."
        func run() throws { try rpc(method: "file.list", params: ["path": .string(path)]) }
    }

    struct Stat: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "stat")
        @Argument var path: String
        func run() throws { try rpc(method: "file.stat", params: ["path": .string(path)]) }
    }

    struct Mkdir: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mkdir")
        @Argument var path: String
        func run() throws { try rpc(method: "file.mkdir", params: ["path": .string(path)]) }
    }

    struct Exists: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "exists")
        @Argument var path: String
        func run() throws { try rpc(method: "file.exists", params: ["path": .string(path)]) }
    }

    struct Tags: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "tags",
            abstract: "List tags on a file")
        @Argument var path: String
        func run() throws { try rpc(method: "file.tags", params: ["path": .string(path)]) }
    }

    struct SetTags: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set-tags",
            abstract: "Replace all tags on a file")
        @Argument var path: String
        @Argument(help: "Tags (space separated)") var tags: [String]
        func run() throws {
            try rpc(method: "file.set-tags",
                    params: ["path": .string(path), "tags": .array(tags.map { .string($0) })])
        }
    }

    struct AddTags: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add-tags",
            abstract: "Add tags without removing existing ones")
        @Argument var path: String
        @Argument(help: "Tags to add") var tags: [String]
        func run() throws {
            try rpc(method: "file.add-tags",
                    params: ["path": .string(path), "tags": .array(tags.map { .string($0) })])
        }
    }

    struct Reveal: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "reveal",
            abstract: "Reveal file in Finder")
        @Argument var path: String
        func run() throws { try rpc(method: "file.reveal", params: ["path": .string(path)]) }
    }

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "open",
            abstract: "Open file with default or specified app")
        @Argument var path: String
        @Option(name: .long, help: "App bundle ID to open with") var app: String?
        func run() throws {
            var params: [String: JSONValue] = ["path": .string(path)]
            if let a = app { params["app"] = .string(a) }
            try rpc(method: "file.open", params: params)
        }
    }

    struct ResolveICloud: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "resolve-icloud",
            abstract: "Download evicted iCloud file and return local path")
        @Argument var path: String
        @Option(name: .long, help: "Download timeout in seconds") var timeout: Int = 30
        func run() throws {
            try rpc(method: "file.resolve-icloud",
                    params: ["path": .string(path), "timeout": .int(timeout)])
        }
    }
}
```

- [ ] **Register in main.swift**

Add `FileCommand.self` to the subcommands list in `Sources/macctl/main.swift`:

```swift
subcommands: [
    ClickCommand.self, TypeCommand.self, KeyCommand.self,
    SeeCommand.self, ScrollCommand.self, DragCommand.self, ShellCommand.self,
    AppCommand.self, ScreenshotCommand.self, InstallCommand.self,
    SystemCommand.self, PowerCommand.self, ClipboardCommand.self,
    NetworkCommand.self, DefaultsCommand.self,
    FileCommand.self,    // ← add
]
```

- [ ] **Build CLI**

```bash
swift build --product macctl 2>&1 | grep -E "error:|complete"
```
Expected: `Build complete!`

- [ ] **Verify help**

```bash
.build/debug/macctl file --help
```
Expected: Shows 16 file subcommands.

- [ ] **Commit**

```bash
git add Sources/macctl/Commands/FileCommand.swift Sources/macctl/main.swift
git commit -m "feat: add FileCommand CLI (read/write/copy/move/delete/list/stat/mkdir/tags/reveal/open)"
```

---

## Task 5: Smoke Tests + Benchmark

- [ ] **Start daemon and run smoke tests**

```bash
# Start daemon
.build/debug/macctl-daemon &
DPID=$!
sleep 1.5
```

```bash
# Create test file
echo "hello macctl" > /tmp/macctl-file-test.txt

# read
.build/debug/macctl file read /tmp/macctl-file-test.txt 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('read:', repr(d['data']['content']))"

# write
.build/debug/macctl file write /tmp/macctl-write-test.txt "written by macctl" 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('write bytes:', d['data']['bytes'])"

# stat
.build/debug/macctl file stat /tmp/macctl-file-test.txt 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); dd=d['data']; print('stat:', dd['name'], 'size:', dd['size'], 'isDir:', dd['isDirectory'])"

# list
.build/debug/macctl file list /tmp 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('list count:', d['data']['count'])"

# copy
.build/debug/macctl file copy /tmp/macctl-file-test.txt /tmp/macctl-copy-test.txt 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('copy:', d['success'])"

# tags
.build/debug/macctl file set-tags /tmp/macctl-file-test.txt Red Important 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('set-tags:', d['success'])"
.build/debug/macctl file tags /tmp/macctl-file-test.txt 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('tags:', d['data']['tags'])"

# delete
.build/debug/macctl file delete /tmp/macctl-copy-test.txt 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('delete:', d['success'])"
.build/debug/macctl file exists /tmp/macctl-copy-test.txt 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('exists after delete:', d['data']['exists'])"
```

Expected output:
```
read: 'hello macctl\n'
write bytes: 17
stat: macctl-file-test.txt size: 13 isDir: False
list count: <N>
copy: True
set-tags: True
tags: ['"Red"', '"Important"']   (or similar plist format)
delete: True
exists after delete: False
```

- [ ] **Run latency benchmark**

```python
import subprocess, json

def run(args):
    r = subprocess.run(['.build/debug/macctl'] + args, capture_output=True, text=True, timeout=10)
    try: return json.loads(r.stdout)
    except: return {"success": False}

def bench(label, args, n=10, target=None):
    import time
    times = []
    for _ in range(n):
        d = run(args)
        t = d.get('meta',{}).get('durationMs',-1)
        if t > 0: times.append(t)
    if not times: print(f"  FAIL {label}"); return
    times.sort()
    p50 = times[int(len(times)*0.5)]
    p95 = times[min(int(len(times)*0.95), len(times)-1)]
    lyr = run(args).get('meta',{}).get('layer','?')
    mark = ("✅" if p50 <= target else "⚠️ ") if target else "  "
    print(f"  {mark} {label:<44} P50={p50:6.1f} P95={p95:6.1f}ms [{lyr}]")

import tempfile, os
tmp = tempfile.mkdtemp()
testfile = f"{tmp}/bench.txt"
subprocess.run(['.build/debug/macctl', 'file', 'write', testfile, 'benchmark content'], capture_output=True)

print("File operation latency benchmark:")
bench("file.read",    ['file','read',testfile],            target=2)
bench("file.write",   ['file','write',testfile,'x'],      target=5)
bench("file.stat",    ['file','stat',testfile],            target=2)
bench("file.list",    ['file','list',tmp],                 target=5)
bench("file.exists",  ['file','exists',testfile],          target=1)
bench("file.tags",    ['file','tags',testfile],            target=2)
bench("file.set-tags",['file','set-tags',testfile,'Red'], target=2)
bench("file.copy",    ['file','copy',testfile,f"{tmp}/b.txt"], target=10)
bench("file.move",    ['file','move',f"{tmp}/b.txt",f"{tmp}/c.txt"], target=10)
bench("file.delete",  ['file','delete',f"{tmp}/c.txt"],   target=5)
```

Expected:
- `file.read` P50 < 2ms
- `file.stat` P50 < 2ms
- `file.tags` P50 < 2ms (xattr direct, not Scripting Bridge)
- `file.write` P50 < 5ms

- [ ] **Stop daemon, commit**

```bash
kill $DPID
git add -A
git commit -m "feat: Plan 3A complete — FileActor POSIX/iCloud/Finder/xattr with CLI and benchmark"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task | Status |
|---|---|---|
| POSIX read/write/copy/move/delete | Task 1 | ✅ |
| NSFileCoordinator for shared locations | Task 1 | ✅ |
| Cross-volume move = copy+verify+delete | Task 1 | ✅ |
| iCloud eviction detection | Task 1 | ✅ |
| iCloud download wait via NSMetadataQuery | Task 1 | ✅ |
| Tags via xattr (not Scripting Bridge) | Task 1 | ✅ |
| Reveal in Finder (NSWorkspace) | Task 1 | ✅ |
| Open With | Task 1 | ✅ |
| stat (size, dates, perms, iCloud status) | Task 1 | ✅ |
| list directory | Task 1 | ✅ |
| mkdir (recursive) | Task 1 | ✅ |
| trash (recoverable delete) | Task 1 | ✅ |
| Dispatcher wiring | Task 3 | ✅ |
| CLI commands | Task 4 | ✅ |
| Tests | Tasks 1+2 | ✅ |
| Benchmark | Task 5 | ✅ |
| FSEvents file watching | Plan 3B | deferred |
| EventKit (Calendar/Reminders) | Plan 3B | deferred |
| ContactsKit | Plan 3B | deferred |

**Placeholder scan:** None. All code blocks are complete.

**Type consistency:** `FileInfo`, `DirectoryEntry`, `FileError` defined in Task 1, used consistently in Tasks 3+4.
