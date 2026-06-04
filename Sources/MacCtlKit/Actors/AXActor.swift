import Cocoa
@preconcurrency import ApplicationServices
import Logging

/// Owns all AXUIElement references — never exposes them across actor boundary.
/// External callers use String element IDs only.
public actor AXActor {
    private var elementCache: [String: AXUIElement] = [:]
    private var idCounter = 0
    private let logger = Logger(label: "macctl.ax")

    public init() {}

    // MARK: - App element

    public func appElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    // MARK: - Attribute access (internal use, AXUIElement stays in actor)

    func stringValue(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let str = value as? String else { return nil }
        return str
    }

    func boolValue(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let num = value as? NSNumber else { return nil }
        return num.boolValue
    }

    func childrenOf(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }

    func frameOf(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard let axPos = posRef, AXValueGetValue(axPos as! AXValue, .cgPoint, &pos),
              let axSize = sizeRef, AXValueGetValue(axSize as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: pos, size: size)
    }

    // MARK: - Element search

    /// Find first element matching query. Returns element ID registered in cache.
    public func findElementID(query: String, in app: AXUIElement, maxDepth: Int = 10) -> String? {
        guard let element = findRecursive(query: query.lowercased(), element: app, depth: maxDepth)
        else { return nil }
        let id = nextID()
        elementCache[id] = element
        return id
    }

    /// Internal: returns raw AXUIElement — only use within this actor.
    func findElement(query: String, in app: AXUIElement, maxDepth: Int = 10) -> AXUIElement? {
        findRecursive(query: query.lowercased(), element: app, depth: maxDepth)
    }

    private func findRecursive(query: String, element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth > 0 else { return nil }
        let candidates = [
            stringValue(element, attribute: kAXTitleAttribute),
            stringValue(element, attribute: kAXDescriptionAttribute),
            stringValue(element, attribute: kAXValueAttribute),
            stringValue(element, attribute: kAXPlaceholderValueAttribute),
        ]
        if candidates.compactMap({ $0 }).contains(where: { $0.lowercased().contains(query) }) {
            return element
        }
        for child in childrenOf(element) {
            if let found = findRecursive(query: query, element: child, depth: depth - 1) {
                return found
            }
        }
        return nil
    }

    // MARK: - Element enumeration

    /// List interactive elements, return as AXElementInfo (Sendable — no AXUIElement exposed).
    public func listElements(in app: AXUIElement, maxDepth: Int = 6) -> [AXElementInfo] {
        var results: [AXElementInfo] = []
        enumerateRecursive(element: app, depth: maxDepth, results: &results)
        return results
    }

    private let interactiveRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
        "AXLink", "AXPopUpButton", "AXMenuItem", "AXSlider", "AXComboBox",
        "AXSearchField", "AXStaticText", "AXImage",
    ]

    private func enumerateRecursive(element: AXUIElement, depth: Int, results: inout [AXElementInfo]) {
        guard depth > 0 else { return }
        let role = stringValue(element, attribute: kAXRoleAttribute) ?? ""
        let title = stringValue(element, attribute: kAXTitleAttribute)
            ?? stringValue(element, attribute: kAXDescriptionAttribute)
            ?? stringValue(element, attribute: kAXValueAttribute)
            ?? ""
        if interactiveRoles.contains(role) && !title.isEmpty {
            let id = nextID()
            elementCache[id] = element
            results.append(AXElementInfo(id: id, role: role, title: title, frame: frameOf(element)))
        }
        for child in childrenOf(element) {
            enumerateRecursive(element: child, depth: depth - 1, results: &results)
        }
    }

    // MARK: - Element ID registry

    private func nextID() -> String {
        idCounter += 1
        return "E\(idCounter)"
    }

    public func element(for id: String) -> AXUIElement? { elementCache[id] }
    public func clearCache() { elementCache.removeAll(); idCounter = 0 }

    // MARK: - Actions (by element ID — safe cross-actor boundary)

    public func press(id: String) throws {
        guard let element = elementCache[id] else { throw AXActorError.elementNotFound }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else { throw AXActorError.actionFailed(result.rawValue) }
    }

    public func setValue(_ value: String, forID id: String) throws {
        guard let element = elementCache[id] else { throw AXActorError.elementNotFound }
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
        guard result == .success else { throw AXActorError.setValueFailed(result.rawValue) }
    }

    public func isSettable(id: String, attribute: String) -> Bool {
        guard let element = elementCache[id] else { return false }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return settable.boolValue
    }

    // Internal AXUIElement variants — used by InputActor indirectly (within actor only)
    func press(_ element: AXUIElement) throws {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else { throw AXActorError.actionFailed(result.rawValue) }
    }

    func setValue(_ value: String, on element: AXUIElement) throws {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
        guard result == .success else { throw AXActorError.setValueFailed(result.rawValue) }
    }

    func isSettable(_ element: AXUIElement, attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return settable.boolValue
    }

    public func focus(id: String) {
        guard let element = elementCache[id] else { return }
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFBoolean)
    }
}

// MARK: - Supporting types

public struct AXElementInfo: Sendable {
    public let id: String
    public let role: String
    public let title: String
    public let frame: CGRect?
}

public enum AXActorError: Error, Sendable {
    case actionFailed(Int32)
    case setValueFailed(Int32)
    case elementNotFound
}
