import ScreenCaptureKit
import CoreGraphics
import AppKit
import Logging

/// Warm screenshot actor. Uses SCScreenshotManager on macOS 14+, CGWindowListCreateImage on 13.
public actor CaptureActor {
    private var cachedContent: SCShareableContent?
    private let screenshotDir: URL
    private let logger = Logger(label: "macctl.capture")

    public init() {
        let tmp = FileManager.default.temporaryDirectory
        screenshotDir = tmp.appendingPathComponent("macctl-screenshots")
        try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
        if #available(macOS 14, *) {
            Task { await self.warmSession() }
        }
    }

    @available(macOS 14, *)
    private func warmSession() async {
        do {
            cachedContent = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            logger.info("SCK session warmed (macOS 14+)")
        } catch {
            logger.warning("SCK warm failed: \(error)")
        }
    }

    // MARK: - Screenshot

    public func screenshot(app bundleID: String? = nil) async throws -> URL {
        let path = screenshotDir.appendingPathComponent("snap-\(UUID().uuidString).png")

        if #available(macOS 14, *) {
            return try await screenshotSCK(bundleID: bundleID, path: path)
        } else {
            return try screenshotCG(bundleID: bundleID, path: path)
        }
    }

    @available(macOS 14, *)
    private func screenshotSCK(bundleID: String?, path: URL) async throws -> URL {
        // Always refresh — SCShareableContent.excludingDesktopWindows is fast (~2ms)
        // and must reflect current window set. Stale cache causes wrong window captures.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        cachedContent = content

        let filter: SCContentFilter
        if let bundleID,
           let window = content.windows.first(where: {
               $0.owningApplication?.bundleIdentifier == bundleID }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            guard let display = content.displays.first else { throw CaptureError.noDisplay }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let config = SCStreamConfiguration()
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CaptureError.encodingFailed }
        try data.write(to: path)
        return path
    }

    private func screenshotCG(bundleID: String?, path: URL) throws -> URL {
        let cgImage: CGImage?
        if let bundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            // Capture specific app window
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
            let appWindows = windowList?.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier }
            if let winID = (appWindows?.first?[kCGWindowNumber as String] as? CGWindowID) {
                cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, winID, [.boundsIgnoreFraming])
            } else {
                cgImage = CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, [])
            }
        } else {
            cgImage = CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, [])
        }
        guard let image = cgImage else { throw CaptureError.captureFailedCG }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CaptureError.encodingFailed }
        try data.write(to: path)
        return path
    }
}

public enum CaptureError: Error, Sendable {
    case noDisplay
    case encodingFailed
    case captureFailedCG
}
