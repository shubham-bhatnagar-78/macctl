import Foundation
import Logging

public struct NoteRecord: Sendable {
    public let id: String
    public let name: String
    public let body: String
    public let folderName: String
    public let modifiedDate: Date?
}

/// Apple Notes via AppleScript — Scripting Bridge for Notes is complex; osascript is reliable.
public actor NotesActor {
    private let logger = Logger(label: "macctl.notes")
    public init() {}

    // MARK: - List notes

    public func list(folder: String? = nil, limit: Int = 50) async -> [NoteRecord] {
        let folderClause = folder.map { "of folder \"\($0)\"" } ?? ""
        let script = """
        tell application "Notes"
            set noteList to {}
            set allNotes to (notes \(folderClause) whose name is not "")
            set noteCount to count of allNotes
            set maxNotes to \(limit)
            if noteCount < maxNotes then set maxNotes to noteCount
            repeat with i from 1 to maxNotes
                set n to item i of allNotes
                try
                    set noteList to noteList & {{id:id of n, name:name of n, folder:name of container of n, modDate:modification date of n}}
                end try
            end repeat
            return noteList
        end tell
        """
        let result = await runScript(script)
        return parseNoteList(result)
    }

    // MARK: - Get note body

    public func get(id: String) async -> NoteRecord? {
        let script = """
        tell application "Notes"
            try
                set n to note id "\(id)"
                return {id:id of n, name:name of n, body:body of n, folder:name of container of n}
            end try
        end tell
        """
        let result = await runScript(script)
        return parseNote(result)
    }

    public func find(name: String) async -> NoteRecord? {
        let script = """
        tell application "Notes"
            try
                set matches to (notes whose name contains "\(name)")
                if (count of matches) > 0 then
                    set n to item 1 of matches
                    return {id:id of n, name:name of n, body:body of n, folder:name of container of n}
                end if
            end try
        end tell
        """
        return parseNote(await runScript(script))
    }

    // MARK: - Create / append / delete

    public func create(title: String, body: String = "", folder: String? = nil) async throws -> NoteRecord {
        let folderClause = folder.map { "in folder \"\($0)\"" } ?? ""
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody  = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Notes"
            set n to make new note \(folderClause) with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
            return {id:id of n, name:name of n, folder:name of container of n}
        end tell
        """
        let result = await runScript(script)
        guard let note = parseNote(result) else {
            throw NotesError.createFailed(title)
        }
        return note
    }

    public func append(id: String, text: String) async throws {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Notes"
            set n to note id "\(id)"
            set body of n to (body of n) & "\n\(escaped)"
        end tell
        """
        let _ = await runScript(script)
    }

    public func delete(id: String) async throws {
        let script = """
        tell application "Notes"
            delete note id "\(id)"
        end tell
        """
        let _ = await runScript(script)
    }

    public func listFolders() async -> [String] {
        let script = """
        tell application "Notes"
            set folderNames to {}
            repeat with f in folders
                set folderNames to folderNames & {name of f}
            end repeat
            return folderNames
        end tell
        """
        let result = await runScript(script)
        // Parse comma-separated list from osascript output
        return result.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // MARK: - AppleScript runner

    private func runScript(_ script: String) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", script]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError  = Pipe()
                do {
                    try task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    cont.resume(returning: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                } catch {
                    cont.resume(returning: "")
                }
            }
        }
    }

    private func parseNoteList(_ raw: String) -> [NoteRecord] {
        // osascript returns AppleScript records as text — best-effort parse
        guard !raw.isEmpty, raw != "missing value" else { return [] }
        // Very basic: each note is on a line-ish boundary; real parsing needs regex
        return []  // Fallback: list returns empty for now; use find/get for individual notes
    }

    private func parseNote(_ raw: String) -> NoteRecord? {
        guard !raw.isEmpty, raw != "missing value" else { return nil }
        // AppleScript record format: "id:x-coredata..., name:Title, body:..., folder:Notes"
        func extract(_ key: String) -> String {
            guard let range = raw.range(of: "\(key):") else { return "" }
            let after = String(raw[range.upperBound...])
            let end = after.firstIndex(of: ",") ?? after.endIndex
            return String(after[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let id = extract("id")
        guard !id.isEmpty else { return nil }
        return NoteRecord(id: id, name: extract("name"), body: extract("body"),
                          folderName: extract("folder"), modifiedDate: nil)
    }
}

public enum NotesError: Error, Sendable {
    case createFailed(String)
    case notFound(String)
}
