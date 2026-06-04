@preconcurrency import AppKit
import Foundation

public struct SpotlightResult: Sendable {
    public let path: String
    public let name: String
    public let kind: String        // "file", "directory", "image", "document", etc.
    public let contentType: String
    public let modifiedDate: Date?
    public let size: Int64
}

public actor SpotlightActor {
    public init() {}

    // MARK: - Search

    /// Search using NSMetadataQuery run on a background thread.
    /// Returns within timeout seconds with whatever results are found.
    public func search(
        query: String,
        scope: [String] = [NSMetadataQueryLocalComputerScope],
        maxResults: Int = 50,
        timeout: TimeInterval = 5.0
    ) async -> [SpotlightResult] {
        let predicate = buildPredicate(query: query)
        return await withCheckedContinuation { continuation in
            let box = ResultsBox()
            let sem = DispatchSemaphore(value: 0)

            // NSMetadataQuery MUST run on a thread with a RunLoop
            let thread = Thread {
                let mq = NSMetadataQuery()
                mq.predicate = predicate
                mq.searchScopes = scope
                mq.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]

                var token: NSObjectProtocol?
                token = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: mq, queue: nil) { _ in
                    mq.stop()
                    mq.disableUpdates()
                    let items = (0..<min(mq.resultCount, maxResults)).compactMap { i in
                        mq.result(at: i) as? NSMetadataItem
                    }
                    box.results = items.compactMap { item in
                        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
                        else { return nil }
                        let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String ?? ""
                        let kind = item.value(forAttribute: NSMetadataItemKindKey) as? String ?? "file"
                        let uti  = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String ?? ""
                        let mod  = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
                        let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0
                        return SpotlightResult(
                            path: path, name: name, kind: kind,
                            contentType: uti, modifiedDate: mod, size: size)
                    }
                    if let t = token { NotificationCenter.default.removeObserver(t) }
                    sem.signal()
                }

                mq.start()
                CFRunLoopRunInMode(.defaultMode, timeout, false)
                mq.stop()
                sem.signal()  // in case query never finished
                if let t = token { NotificationCenter.default.removeObserver(t) }
            }
            thread.qualityOfService = .userInitiated
            thread.start()

            DispatchQueue.global(qos: .userInitiated).async {
                _ = sem.wait(timeout: .now() + timeout + 0.5)
                continuation.resume(returning: box.results)
            }
        }
    }

    /// Find files by name pattern.
    public func findFiles(name: String, in directory: String? = nil) async -> [SpotlightResult] {
        var scope: [String] = [NSMetadataQueryLocalComputerScope]
        if let dir = directory { scope = [dir] }
        return await search(query: name, scope: scope)
    }

    // MARK: - Predicate building

    private func buildPredicate(query: String) -> NSPredicate {
        // If query looks like a file extension, search by type
        if query.hasPrefix(".") || query.contains("*") {
            return NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(query)*")
        }
        // Otherwise search name + content
        let namePred = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, query)
        let displayPred = NSPredicate(format: "%K CONTAINS[cd] %@",
                                      NSMetadataItemDisplayNameKey, query)
        return NSCompoundPredicate(orPredicateWithSubpredicates: [namePred, displayPred])
    }
}

private final class ResultsBox: @unchecked Sendable {
    var results: [SpotlightResult] = []
}
