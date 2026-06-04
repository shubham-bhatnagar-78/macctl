import Foundation

/// Registers all 59 Apple-shipped app adapters in one call at daemon startup.
/// O(59) registrations, ~2ms total.
public enum AppleAdapterRegistry {

    public static func registerAll() async {
        let registry = await AdapterRegistry.shared

        func reg(_ id: String, _ name: String,
                 _ caps: AdapterCapabilities = [.keyboard, .accessibility]) async {
            await registry.register(AppleAppAdapter(bundleID: id, displayName: name, capabilities: caps))
        }
        func regSB(_ id: String, _ name: String) async {
            await reg(id, name, [.keyboard, .accessibility, .scriptingBridge])
        }
        func regFW(_ id: String, _ name: String) async {
            await reg(id, name, [.keyboard, .accessibility, .frameworkAPI])
        }

        // ── System ───────────────────────────────────────────────────────────
        await reg("com.apple.finder",              "Finder",              [.keyboard, .accessibility, .scriptingBridge])
        await reg("com.apple.systempreferences",   "System Settings")
        await reg("com.apple.AppStore",            "App Store")
        await reg("com.apple.Calculator",          "Calculator")
        await reg("com.apple.Dictionary",          "Dictionary")
        await reg("com.apple.FontBook",            "Font Book")
        await reg("com.apple.Preview",             "Preview")
        await reg("com.apple.QuickTimePlayerX",    "QuickTime Player")
        await reg("com.apple.Stickies",            "Stickies")
        await reg("com.apple.TextEdit",            "TextEdit")
        await reg("com.apple.clock",               "Clock")
        await reg("com.apple.weather",             "Weather")
        await reg("com.apple.Photo-Booth",         "Photo Booth")
        await reg("com.apple.findmy",              "Find My")
        await reg("com.apple.ScreenContinuity",    "iPhone Mirroring",   [.keyboard, .accessibility, .iosMirroring])

        // ── Developer tools ──────────────────────────────────────────────────
        await reg("com.apple.Terminal",            "Terminal",            [.keyboard, .accessibility, .scriptingBridge])
        await reg("com.apple.dt.Xcode",            "Xcode")
        await regSB("com.apple.ScriptEditor2",     "Script Editor")
        await regSB("com.apple.Automator",         "Automator")
        await reg("com.apple.ActivityMonitor",     "Activity Monitor")
        await reg("com.apple.Console",             "Console")
        await reg("com.apple.DiskUtility",         "Disk Utility")
        await reg("com.apple.audio.AudioMIDISetup","Audio MIDI Setup")
        await reg("com.apple.ColorSyncUtility",    "ColorSync Utility")
        await reg("com.apple.DirectoryUtility",    "Directory Utility")
        await reg("com.apple.AirPortUtility",      "AirPort Utility")
        await reg("com.apple.WirelessDiagnostics", "Wireless Diagnostics")
        await reg("com.apple.keychainaccess",      "Keychain Access")
        await reg("com.apple.DigitalColorMeter",   "Digital Color Meter")
        await reg("com.apple.Image_Capture",       "Image Capture")
        await reg("com.apple.MigrationAssistant",  "Migration Assistant")
        await reg("com.apple.SystemProfiler",      "System Information")
        await reg("com.apple.BluetoothFileExchange","Bluetooth File Exchange")
        await reg("com.apple.ScreenSharing",       "Screen Sharing")

        // ── Productivity / iWork ─────────────────────────────────────────────
        await regSB("com.apple.Safari",            "Safari")
        await regSB("com.apple.mail",              "Mail")
        await regSB("com.apple.Notes",             "Notes")
        await regFW("com.apple.iCal",              "Calendar")   // EventKit in Plan 3B
        await regFW("com.apple.reminders",         "Reminders")  // EventKit in Plan 3B
        await regFW("com.apple.AddressBook",       "Contacts")   // ContactsKit in Plan 3B
        await reg("com.apple.iWork.Pages",         "Pages")
        await reg("com.apple.iWork.Numbers",       "Numbers")
        await reg("com.apple.iWork.Keynote",       "Keynote")

        // ── Communication + media ────────────────────────────────────────────
        await regSB("com.apple.MobileSMS",         "Messages")
        await reg("com.apple.FaceTime",            "FaceTime")
        await regFW("com.apple.Photos",            "Photos")     // PhotosKit in Plan 3B
        await reg("com.apple.Music",               "Music")
        await reg("com.apple.TV",                  "TV")
        await reg("com.apple.podcasts",            "Podcasts")
        await reg("com.apple.iBooksX",             "Books")
        await reg("com.apple.News",                "News")
        await reg("com.apple.Stocks",              "Stocks")
        await reg("com.apple.Home",                "Home")
        await reg("com.apple.Maps",                "Maps")
        await reg("com.apple.VoiceMemos",          "Voice Memos")
        await reg("com.apple.Freeform",            "Freeform")
        await reg("com.apple.shortcuts",           "Shortcuts")

        // ── Creative ─────────────────────────────────────────────────────────
        await reg("com.apple.iMovieApp",           "iMovie")
        await reg("com.apple.GarageBand",          "GarageBand")
    }
}
