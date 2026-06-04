import IOKit.pwr_mgt
import Foundation
import Logging

public typealias SleepToken = UInt64

public actor PowerActor {
    private var assertions: [SleepToken: IOPMAssertionID] = [:]
    private var tokenCounter: UInt64 = 0
    private let logger = Logger(label: "macctl.power")

    public init() {}

    // MARK: - Sleep prevention (IOPMAssertion — public API)

    public func preventSleep(reason: String) throws -> SleepToken {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID)
        guard result == kIOReturnSuccess else {
            throw PowerError.assertionFailed(result)
        }
        tokenCounter += 1
        assertions[tokenCounter] = assertionID
        logger.debug("Sleep prevention: \(reason) token=\(tokenCounter)")
        return tokenCounter
    }

    public func releaseSleep(token: SleepToken) {
        guard let id = assertions.removeValue(forKey: token) else { return }
        IOPMAssertionRelease(id)
    }

    public func releaseAllSleep() {
        for (_, id) in assertions { IOPMAssertionRelease(id) }
        assertions.removeAll()
    }

    public func activePreventionCount() -> Int { assertions.count }

    // MARK: - System sleep (IOPMSleepSystem — public API)

    public func systemSleep() throws {
        let port = IOPMFindPowerManagement(mach_port_t(0))
        guard port != 0 else { throw PowerError.portUnavailable }
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    // MARK: - Screen lock
    // SACLockScreenImmediately — private SecurityAgentCocoa.framework symbol.
    // Most reliable lock method; alternatives have delays or require user interaction.

    public func lockScreen() {
        let path = "/System/Library/PrivateFrameworks/SecurityAgentCocoa.framework/SecurityAgentCocoa"
        if let handle = dlopen(path, RTLD_LAZY),
           let sym = dlsym(handle, "SACLockScreenImmediately") {
            typealias LockFn = @convention(c) () -> Void
            unsafeBitCast(sym, to: LockFn.self)()
            dlclose(handle)
        } else {
            // Fallback: screensaver (triggers lock if "require password" is enabled)
            var p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "ScreenSaverEngine"]
            try? p.run()
        }
    }
}

public enum PowerError: Error, Sendable {
    case assertionFailed(kern_return_t)
    case portUnavailable
}
