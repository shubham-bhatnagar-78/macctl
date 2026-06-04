import Carbon
import Foundation

public struct InputSourceInfo: Sendable {
    public let id: String
    public let localizedName: String
    public let isSelected: Bool
    public let category: String   // "keyboard", "input method", etc.
}

public actor InputSourceActor {
    public init() {}

    public func current() -> InputSourceInfo? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return nil }
        return sourceInfo(source, selected: true)
    }

    public func list() -> [InputSourceInfo] {
        let currentID = current()?.id
        guard let all = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return all.compactMap { source in
            // Only include selectable sources
            guard let selectable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(selectable as! CFBoolean)
            else { return nil }
            let info = sourceInfo(source, selected: false)
            if info.id.isEmpty { return nil }
            return InputSourceInfo(id: info.id, localizedName: info.localizedName,
                                   isSelected: info.id == currentID, category: info.category)
        }
    }

    public func select(id: String) throws {
        guard let all = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
              let source = all.first(where: { sourceID($0) == id })
        else { throw InputSourceError.notFound(id) }
        let result = TISSelectInputSource(source)
        if result != noErr { throw InputSourceError.selectFailed(id) }
    }

    public func selectByName(_ name: String) throws {
        guard let source = list().first(where: {
            $0.localizedName.localizedCaseInsensitiveContains(name) })
        else { throw InputSourceError.notFound(name) }
        try select(id: source.id)
    }

    private func sourceID(_ source: TISInputSource) -> String {
        guard let p = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return "" }
        return (p as! CFString) as String
    }

    private func sourceInfo(_ source: TISInputSource, selected: Bool) -> InputSourceInfo {
        let id = sourceID(source)
        let name: String = {
            if let p = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                return (p as! CFString) as String
            }
            return id
        }()
        let category: String = {
            if let p = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) {
                return (p as! CFString) as String
            }
            return "unknown"
        }()
        return InputSourceInfo(id: id, localizedName: name, isSelected: selected, category: category)
    }
}

public enum InputSourceError: Error, Sendable {
    case notFound(String)
    case selectFailed(String)
}
