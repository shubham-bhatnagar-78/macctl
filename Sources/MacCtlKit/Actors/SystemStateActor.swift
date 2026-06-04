import AudioToolbox   // kAudioHardwareServiceDeviceProperty_VirtualMainVolume
import CoreAudio
import CoreWLAN
import IOKit
import Foundation
import Logging

public actor SystemStateActor {
    private let logger = Logger(label: "macctl.system-state")
    public init() {}

    // MARK: - Volume (CoreAudio + AudioToolbox — public API)

    public func volume() -> Float {
        guard let deviceID = defaultOutputDevice() else { return 0 }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &vol)
        return vol
    }

    public func setVolume(_ value: Float) {
        guard let deviceID = defaultOutputDevice() else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var vol = max(0, min(1, value))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
    }

    public func isMuted() -> Bool {
        guard let deviceID = defaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return muted != 0
    }

    public func setMuted(_ muted: Bool) {
        guard let deviceID = defaultOutputDevice() else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var val: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val)
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    // MARK: - Brightness (IOKit — undocumented but stable since macOS 10.x)
    // No public API exists for programmatic brightness control on macOS.
    // IODisplayConnect = external displays. AppleBacklightDisplay = built-in (MacBook/iMac).
    // Tries both services; returns first non-zero value found.

    public func brightness() -> Float {
        for service in brightnessServices() {
            var value: Float = 0
            if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value) == kIOReturnSuccess,
               value > 0 {
                IOObjectRelease(service)
                return value
            }
            IOObjectRelease(service)
        }
        return 0
    }

    public func setBrightness(_ value: Float) {
        let clamped = max(0, min(1, value))
        for service in brightnessServices() {
            IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
            IOObjectRelease(service)
        }
    }

    private func brightnessServices() -> [io_object_t] {
        var services: [io_object_t] = []
        for serviceName in ["IODisplayConnect", "AppleBacklightDisplay"] {
            var iterator = io_iterator_t()
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceName), &iterator)
            var service = IOIteratorNext(iterator)
            while service != 0 {
                services.append(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        return services
    }

    // MARK: - WiFi (CoreWLAN — public API)

    public func wifiEnabled() -> Bool {
        CWWiFiClient.shared().interface()?.powerOn() ?? false
    }

    public func setWifiEnabled(_ enabled: Bool) throws {
        guard let iface = CWWiFiClient.shared().interface() else {
            throw SystemStateError.wifiInterfaceNotFound
        }
        try iface.setPower(enabled)
    }

    public func wifiSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    // MARK: - Bluetooth
    // Read: public IOBluetooth API.
    // Write: IOBluetoothPreferenceSetControllerPowerState — private, stable 10+ years.
    // kBluetoothHCIPowerStateOn = 1, kBluetoothHCIPowerStateOff = 0

    public func bluetoothEnabled() -> Bool {
        // Read from /Library/Preferences/com.apple.Bluetooth.plist
        // Avoids IOBluetoothHostController which requires main thread + Bluetooth entitlement.
        // ControllerPowerState: 1 = on, 0 = off
        let prefs = UserDefaults(suiteName: "/Library/Preferences/com.apple.Bluetooth")
        return (prefs?.integer(forKey: "ControllerPowerState") ?? 0) == 1
    }

    public func setBluetoothEnabled(_ enabled: Bool) {
        guard let handle = dlopen(
            "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY),
              let sym = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else {
            logger.warning("IOBluetoothPreferenceSetControllerPowerState unavailable")
            return
        }
        // kBluetoothHCIPowerStateOn=1, kBluetoothHCIPowerStateOff=0 (UInt32)
        typealias SetBTPower = @convention(c) (UInt32) -> Void
        unsafeBitCast(sym, to: SetBTPower.self)(enabled ? 1 : 0)
        dlclose(handle)
    }

    // MARK: - Status summary

    public struct SystemStatus: Sendable {
        public let volume: Float
        public let isMuted: Bool
        public let brightness: Float
        public let wifiEnabled: Bool
        public let wifiSSID: String?
        public let bluetoothEnabled: Bool
    }

    public func status() -> SystemStatus {
        SystemStatus(
            volume: volume(),
            isMuted: isMuted(),
            brightness: brightness(),
            wifiEnabled: wifiEnabled(),
            wifiSSID: wifiSSID(),
            bluetoothEnabled: bluetoothEnabled()
        )
    }
}

public enum SystemStateError: Error, Sendable {
    case wifiInterfaceNotFound
}
