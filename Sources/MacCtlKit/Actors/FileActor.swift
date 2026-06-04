@preconcurrency import AppKit
import Foundation

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
        public let permissions: Int
        public let isICloud: Bool
        public let iCloudDownloaded: Bool
    }

    public struct DirectoryEntry: Sendable {
        public let name: String
        public let path: String
        public let isDirectory: Bool
        public let size: Int64
    }

    // MARK: - Tier 1: POSIX / FileManager

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
        try await writeData(path: path, data: Data(content.utf8))
    }

    public func writeData(path: String, data: Data) async throws {
        let url = URL(fileURLWithPath: expandPath(path))
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        if isSharedLocation(url) {
            try writeWithCoordinator(url: url, data: data)
        } else {
            // Atomic write: write to temp file, then rename
            let tmp = parent.appendingPathComponent(".\(UUID().uuidString).tmp")
            try data.write(to: tmp, options: .atomic)
            do {
                // replaceItem preserves metadata and does atomic swap
                _ = try FileManager.default.replaceItem(
                    at: url, withItemAt: tmp,
                    backupItemName: nil, options: [], resultingItemURL: nil)
            } catch {
                // Fallback: just rename (also atomic on same volume)
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        }
    }

    public func copy(from srcPath: String, to dstPath: String) async throws {
        let src = URL(fileURLWithPath: expandPath(srcPath))
        let dst = URL(fileURLWithPath: expandPath(dstPath))
        try assertNotEvicted(src)
        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.copyItem(at: src, to: dst)
    }

    /// Move file. Cross-volume: copy + verify checksum + delete source.
    public func move(from srcPath: String, to dstPath: String) async throws {
        let src = URL(fileURLWithPath: expandPath(srcPath))
        let dst = URL(fileURLWithPath: expandPath(dstPath))
        try assertNotEvicted(src)
        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        do {
            try FileManager.default.moveItem(at: src, to: dst)
        } catch {
            // Cross-volume or rename not supported — copy+verify+delete
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
        try FileManager.default.removeItem(at: URL(fileURLWithPath: expandPath(path)))
    }

    public func trash(path: String) async throws {
        try FileManager.default.trashItem(
            at: URL(fileURLWithPath: expandPath(path)), resultingItemURL: nil)
    }

    public func mkdir(path: String) async throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: expandPath(path)), withIntermediateDirectories: true)
    }

    public nonisolated func exists(path: String) -> Bool {
        FileManager.default.fileExists(atPath: expandPath(path))
    }

    public func stat(path: String) async throws -> FileInfo {
        let url = URL(fileURLWithPath: expandPath(path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)

        let resKeys: Set<URLResourceKey> = [
            .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]
        let resVals = (try? url.resourceValues(forKeys: resKeys)) ?? URLResourceValues()

        let rawSize = attrs[.size]
        let size: Int64
        if let n = rawSize as? NSNumber { size = n.int64Value }
        else { size = 0 }

        let dlStatus = resVals.ubiquitousItemDownloadingStatus
        return FileInfo(
            path: url.path,
            name: url.lastPathComponent,
            size: size,
            isDirectory: (attrs[.type] as? FileAttributeType) == .typeDirectory,
            isSymlink: resVals.isSymbolicLink ?? false,
            exists: true,
            createdAt: attrs[.creationDate] as? Date,
            modifiedAt: attrs[.modificationDate] as? Date,
            permissions: (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0,
            isICloud: resVals.isUbiquitousItem ?? false,
            iCloudDownloaded: dlStatus == .current || dlStatus == nil
        )
    }

    public func list(path: String) async throws -> [DirectoryEntry] {
        let url = URL(fileURLWithPath: expandPath(path))
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
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

    /// Resolve an iCloud file — triggers download if evicted, polls until downloaded.
    /// Uses 200ms polling (iCloud downloads take seconds, poll interval is negligible).
    public func resolveICloud(path: String, timeoutSecs: Int = 30) async throws -> String {
        let url = URL(fileURLWithPath: expandPath(path))
        let resKeys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let resVals = try? url.resourceValues(forKeys: resKeys),
              resVals.isUbiquitousItem == true else { return url.path }
        let status = resVals.ubiquitousItemDownloadingStatus
        if status == .current { return url.path }

        // Trigger download
        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        // Poll every 200ms until downloaded or timeout
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSecs))
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
            // Re-resolve to get fresh status (URLResourceValues are cached)
            var freshURL = URL(fileURLWithPath: url.path)
            freshURL.removeAllCachedResourceValues()
            if let fresh = try? freshURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               fresh.ubiquitousItemDownloadingStatus == .current {
                return url.path
            }
        }
        throw FileError.iCloudDownloadTimeout(url.path)
    }

    /// Read iCloud file — auto-downloads if evicted.
    public func readICloud(path: String, timeoutSecs: Int = 30) async throws -> String {
        let resolved = try await resolveICloud(path: path, timeoutSecs: timeoutSecs)
        return try await read(path: resolved)
    }

    // MARK: - Tier 3: Finder / xattr

    /// Tags via xattr (1ms — no Scripting Bridge). Key: com.apple.metadata:_kMDItemUserTags
    public nonisolated func tags(path: String) throws -> [String] {
        let url = URL(fileURLWithPath: expandPath(path))
        guard let data = try? url.extendedAttribute(forName: XattrKeys.tags) else { return [] }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]) ?? []
    }

    public nonisolated func setTags(_ tags: [String], path: String) throws {
        let url = URL(fileURLWithPath: expandPath(path))
        if tags.isEmpty {
            url.removeExtendedAttribute(forName: XattrKeys.tags)
        } else {
            let data = try PropertyListSerialization.data(
                fromPropertyList: tags, format: .binary, options: 0)
            try url.setExtendedAttribute(data, forName: XattrKeys.tags)
        }
    }

    public nonisolated func addTags(_ newTags: [String], path: String) throws {
        var existing = (try? tags(path: path)) ?? []
        for tag in newTags where !existing.contains(tag) { existing.append(tag) }
        try setTags(existing, path: path)
    }

    public nonisolated func removeTags(_ toRemove: [String], path: String) throws {
        let existing = (try? tags(path: path)) ?? []
        try setTags(existing.filter { !toRemove.contains($0) }, path: path)
    }

    /// Reveal in Finder — async because NSWorkspace may need event processing
    public func revealInFinder(path: String) async {
        let url = URL(fileURLWithPath: expandPath(path))
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    public func open(path: String, withApp bundleID: String? = nil) async throws {
        let url = URL(fileURLWithPath: expandPath(path))
        if let bid = bundleID {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            else { throw FileError.appNotFound(bid) }
            let config = NSWorkspace.OpenConfiguration()
            await MainActor.run {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
            }
        } else {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Private helpers

    nonisolated func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func assertNotEvicted(_ url: URL) throws {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let resVals = try? url.resourceValues(forKeys: keys),
              resVals.isUbiquitousItem == true else { return }
        let status = resVals.ubiquitousItemDownloadingStatus
        if status != .current && status != nil {
            throw FileError.iCloudFileEvicted(url.path)
        }
    }

    private func isSharedLocation(_ url: URL) -> Bool {
        let sharedPaths = ["/Library/Application Support/", "/Containers/", "/Group Containers/"]
        return sharedPaths.contains { url.path.contains($0) }
    }

    private func writeWithCoordinator(url: URL, data: Data) throws {
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        var nsError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &nsError) { resolvedURL in
            do { try data.write(to: resolvedURL, options: .atomic) }
            catch { writeError = error }
        }
        if let e = writeError { throw e }
        if let e = nsError { throw e }
    }
}

// MARK: - xattr helpers

private enum XattrKeys {
    static let tags = "com.apple.metadata:_kMDItemUserTags"
}

extension URL {
    func extendedAttribute(forName name: String) throws -> Data {
        let path = self.path
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { throw FileError.xattrReadFailed(name) }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { ptr in
            getxattr(path, name, ptr.baseAddress, length, 0, 0)
        }
        guard read == length else { throw FileError.xattrReadFailed(name) }
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
