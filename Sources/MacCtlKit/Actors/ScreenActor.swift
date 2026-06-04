@preconcurrency import AppKit
import IOKit
import Foundation

public struct ScreenInfo: Sendable {
    public let index: Int
    public let name: String
    public let width: Int
    public let height: Int
    public let scaleFactor: Double   // 2.0 = Retina
    public let isMain: Bool
    public let brightness: Float     // 0-1, -1 if unavailable
    public let frame: CGRect
    public let visibleFrame: CGRect
}

public actor ScreenActor {
    public init() {}

    public func list() -> [ScreenInfo] {
        NSScreen.screens.enumerated().map { i, screen in
            let brightness = getBrightness(screen: screen)
            return ScreenInfo(
                index:        i,
                name:         screen.localizedName,
                width:        Int(screen.frame.width),
                height:       Int(screen.frame.height),
                scaleFactor:  screen.backingScaleFactor,
                isMain:       screen == NSScreen.main,
                brightness:   brightness,
                frame:        screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }

    public func main() -> ScreenInfo? {
        list().first { $0.isMain }
    }

    public func setBrightness(_ value: Float, screenIndex: Int = 0) {
        let clamped = max(0, min(1, value))
        var iterator = io_iterator_t()
        IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"), &iterator)
        var service = IOIteratorNext(iterator)
        var idx = 0
        while service != 0 {
            if idx == screenIndex {
                IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
                IOObjectRelease(service)
                break
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
            idx += 1
        }
        IOObjectRelease(iterator)
    }

    private func getBrightness(screen: NSScreen) -> Float {
        // Try IODisplayConnect for the display matching this screen
        var iterator = io_iterator_t()
        IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"), &iterator)
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var value: Float = 0
            if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value) == kIOReturnSuccess {
                IOObjectRelease(service)
                return value
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return -1  // unavailable
    }
}
