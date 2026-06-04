@preconcurrency import AppKit
import Foundation

public struct SharingServiceInfo: Sendable {
    public let name: String
    public let title: String
}

public actor ShareActor {
    public init() {}

    /// List available sharing services for given item types.
    public func availableServices(forURLs: Bool = true) -> [SharingServiceInfo] {
        let items: [Any] = forURLs ? [URL(fileURLWithPath: "/tmp")] : ["text"]
        return NSSharingService.sharingServices(forItems: items).map { svc in
            SharingServiceInfo(name: svc.title, title: svc.title)
        }
    }

    /// Share URL(s) via a named service (5ms — no UI needed).
    public func shareURLs(_ urls: [URL], via serviceName: NSSharingService.Name) throws {
        guard let service = NSSharingService(named: serviceName) else {
            throw ShareError.serviceUnavailable(serviceName.rawValue)
        }
        guard service.canPerform(withItems: urls) else {
            throw ShareError.cannotPerform(serviceName.rawValue)
        }
        service.perform(withItems: urls)
    }

    /// Share text via a named service.
    public func shareText(_ text: String, via serviceName: NSSharingService.Name) throws {
        guard let service = NSSharingService(named: serviceName) else {
            throw ShareError.serviceUnavailable(serviceName.rawValue)
        }
        guard service.canPerform(withItems: [text]) else {
            throw ShareError.cannotPerform(serviceName.rawValue)
        }
        service.perform(withItems: [text])
    }

    /// Open file with default app (convenience).
    public func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

public enum ShareError: Error, Sendable {
    case serviceUnavailable(String)
    case cannotPerform(String)
}
