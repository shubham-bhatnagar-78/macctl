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

    /// Find first element matching query. Checks focused window first (fast), falls back to full tree.
    /// Returns element ID registered in cache.
    public func findElementID(query: String, in app: AXUIElement, maxDepth: Int = 6) -> String? {
        let q = query.lowercased()
        // Fast path: focused window only (same tree as `see`)
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef,
           let element = findRecursive(query: q, element: focused as! AXUIElement, depth: maxDepth) {
            let id = nextID()
            elementCache[id] = element
            return id
        }
        // Slow path: full app tree (multi-window apps, menu items, etc.)
        guard let element = findRecursive(query: q, element: app, depth: maxDepth) else { return nil }
        let id = nextID()
        elementCache[id] = element
        return id
    }

    /// Internal: returns raw AXUIElement — only use within this actor.
    func findElement(query: String, in app: AXUIElement, maxDepth: Int = 6) -> AXUIElement? {
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

    /// List interactive elements. Resolution: focused window → first window → full app.
    /// Max 100 elements, 2s timeout, partial results if timeout fires.
    public func listElements(in app: AXUIElement, maxDepth: Int = 5, maxElements: Int = 100) -> [AXElementInfo] {
        let root: AXUIElement
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef {
            // Best: focused window (app is frontmost)
            root = focused as! AXUIElement
        } else {
            // Fallback: first window in kAXWindowsAttribute (app is in background)
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement],
               let first = windows.first {
                root = first
            } else {
                root = app
            }
        }
        // Run traversal on background queue with 2s timeout — returns partial results on slow apps
        let box = ElementListBox()
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInteractive).async {
            var results: [AXElementInfo] = []
            self.enumerateRecursive(element: root, depth: maxDepth, results: &results, maxElements: maxElements)
            box.elements = results
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))  // returns partial results on timeout
        return box.elements
    }

    // Roles that agents can meaningfully interact with.
    // AXStaticText excluded — it's display-only content, not actionable.
    // AXImage excluded — usually decorative.
    private let interactiveRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
        "AXLink", "AXPopUpButton", "AXMenuItem", "AXMenuBarItem", "AXSlider",
        "AXComboBox", "AXSearchField", "AXDisclosureTriangle", "AXIncrementor",
        "AXDateField", "AXTimeField", "AXColorWell",
    ]

    // Roles that are always included (even with empty title) — user can type into them
    private let alwaysIncludeRoles: Set<String> = ["AXTextArea", "AXTextField", "AXSearchField"]

    private func enumerateRecursive(element: AXUIElement, depth: Int,
                                    results: inout [AXElementInfo], maxElements: Int = 100) {
        guard depth > 0, results.count < maxElements else { return }
        let role = stringValue(element, attribute: kAXRoleAttribute) ?? ""
        // Title: try kAXTitle, kAXDescription, kAXValue (for text areas showing content)
        let title = stringValue(element, attribute: kAXTitleAttribute)
            ?? stringValue(element, attribute: kAXDescriptionAttribute)
            ?? (alwaysIncludeRoles.contains(role) ? (stringValue(element, attribute: kAXValueAttribute).map { String($0.prefix(40)) } ?? role) : "")

        // Include if: (interactive role AND has title) OR (text input role — always useful)
        let shouldInclude = interactiveRoles.contains(role) && (!title.isEmpty || alwaysIncludeRoles.contains(role))
        if shouldInclude {
            let id = nextID()
            elementCache[id] = element
            results.append(AXElementInfo(id: id, role: role, title: title.isEmpty ? role : title, frame: frameOf(element)))
        }
        for child in childrenOf(element) {
            guard results.count < maxElements else { break }
            enumerateRecursive(element: child, depth: depth - 1, results: &results, maxElements: maxElements)
        }
    }

    // MARK: - Element ID registry

    private func nextID() -> String {
        idCounter += 1
        return "E\(idCounter)"
    }

    public func element(for id: String) -> AXUIElement? { elementCache[id] }
    public func elementExists(id: String) -> Bool { elementCache[id] != nil }
    public func clearCache() { elementCache.removeAll(); idCounter = 0 }

    // MARK: - Actions (by element ID — safe cross-actor boundary)

    public func press(id: String) throws {
        guard let element = elementCache[id] else { throw AXActorError.elementNotFound }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else { throw AXActorError.actionFailed(result.rawValue) }
    }

    public func setValue(_ value: String, forID id: String) throws {
        guard let element = elementCache[id] else { throw AXActorError.elementNotFound }
        // AXUIElementSetAttributeValue is synchronous IPC — run on background queue
        // so callers can apply a real timeout (task group cancellation of sync calls doesn't work)
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
        guard result == .success else { throw AXActorError.setValueFailed(result.rawValue) }
    }

    /// setValue with real DispatchSemaphore timeout.
    /// Unlike task group approach, this actually interrupts the blocking IPC call.
    public func setValueWithTimeout(_ value: String, forID id: String, timeoutMs: Int = 150) async throws {
        guard let element = elementCache[id] else { throw AXActorError.elementNotFound }
        // Bridge: run blocking setValue on a background thread, wait with timeout on another thread
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let sem = DispatchSemaphore(value: 0)
            let box = ResultBox()
            let v = value
            // Worker: calls blocking AX IPC
            DispatchQueue.global(qos: .userInteractive).async {
                box.result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, v as CFString)
                sem.signal()
            }
            // Waiter: blocks on semaphore with timeout, then resumes continuation
            // Must be .userInteractive — lower QoS can delay the timeout by 900ms+
            DispatchQueue.global(qos: .userInteractive).async {
                let timedOut = sem.wait(timeout: .now() + .milliseconds(timeoutMs)) == .timedOut
                if timedOut {
                    cont.resume(throwing: AXActorError.timeout)
                } else if box.result == .success {
                    cont.resume()
                } else {
                    cont.resume(throwing: AXActorError.setValueFailed(box.result?.rawValue ?? -1))
                }
            }
        }
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

    /// Returns element ID for focused UI element, with timeout to avoid blocking.
    public func focusedElementID(pid: pid_t, timeoutMs: Int = 200) -> String? {
        let app = AXUIElementCreateApplication(pid)
        // Run on background queue with semaphore timeout — prevents blocking main actor
        let sem = DispatchSemaphore(value: 0)
        let box = FocusedElementBox()
        DispatchQueue.global(qos: .userInteractive).async {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success {
                box.element = ref as! AXUIElement?
            }
            sem.signal()
        }
        guard sem.wait(timeout: .now() + .milliseconds(timeoutMs)) != .timedOut,
              let element = box.element else { return nil }
        let id = nextID()
        elementCache[id] = element
        return id
    }

    /// Press using AXClick if AXPress fails (e.g. text areas, links).
    public func click(id: String) throws {
        guard let element = elementCache[id] else { throw AXActorError.elementNotFound }
        var result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result != .success {
            result = AXUIElementPerformAction(element, kAXPickAction as CFString)
        }
        // Some elements (text areas) just need focus, not press
        if result != .success {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFBoolean)
        }
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
    case timeout
}

/// Thread-safe result box for bridging DispatchQueue → async context.
private final class ResultBox: @unchecked Sendable {
    var result: AXError? = nil
}

private final class FocusedElementBox: @unchecked Sendable {
    var element: AXUIElement? = nil
}

private final class ElementListBox: @unchecked Sendable {
    var elements: [AXElementInfo] = []
}
