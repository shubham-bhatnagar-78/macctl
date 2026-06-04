import AppKit
import Foundation

// ClipboardContent defined in Protocol/MacOperation.swift

public actor ClipboardActor {
    private let pb: NSPasteboard

    // Default: NSPasteboard.general (production). Pass NSPasteboard(name:) for tests.
    public init(pasteboard: NSPasteboard = .general) {
        self.pb = pasteboard
    }

    // MARK: - Read

    public func read() -> ClipboardContent {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty { return .files(urls) }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = images.first,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { return .image(png) }
        if let html = pb.string(forType: .html)   { return .html(html) }
        if let rtf  = pb.data(forType: .rtf)      { return .rtf(rtf) }
        if let text = pb.string(forType: .string)  { return .text(text) }
        return .empty
    }

    public func readText()  -> String?  { pb.string(forType: .string) }
    public func readHTML()  -> String?  { pb.string(forType: .html) }
    public func readRTF()   -> Data?    { pb.data(forType: .rtf) }
    public func readFiles() -> [URL]    {
        pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
    }

    // MARK: - Write

    public func write(_ content: ClipboardContent) {
        pb.clearContents()
        switch content {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .html(let h):
            pb.setString(h, forType: .html)
            let stripped = h.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            pb.setString(stripped, forType: .string)
        case .rtf(let d):
            pb.setData(d, forType: .rtf)
        case .image(let png):
            if let image = NSImage(data: png) { pb.writeObjects([image]) }
        case .files(let urls):
            pb.writeObjects(urls as [NSURL])
        case .color(let r, let g, let b, let a):
            pb.writeObjects([NSColor(red: r, green: g, blue: b, alpha: a)])
        case .empty:
            break
        }
    }

    public func writeText(_ text: String)   { write(.text(text)) }
    public func writeFiles(_ urls: [URL])   { write(.files(urls)) }

    public func clear()         { pb.clearContents() }
    public func changeCount() -> Int { pb.changeCount }
}
