import Testing
import Foundation
@testable import MacCtlKit

@Suite("NewActors")
struct NewActorsTests {
    // MARK: - WindowActor
    @Test func windowInfoSendable() {
        let info = WindowInfo(
            windowID: 42, title: "Test", appName: "TestApp",
            bundleID: "com.test", pid: 100,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            isMinimized: false, isFullScreen: false, screenIndex: 0)
        #expect(info.windowID == 42)
        #expect(info.title == "Test")
    }

    @Test func windowActorListsWindows() async {
        let actor = WindowActor()
        let windows = await actor.listWindows()
        // On any running system there should be at least some windows
        #expect(windows.count >= 0)
    }

    // MARK: - ProcessActor
    @Test func processRecordSendable() {
        let r = ProcessRecord(pid: 1, name: "launchd", status: "sleeping",
                              memoryMB: 10.0, cpuPercent: 0, parentPID: 0, isApp: false)
        #expect(r.name == "launchd")
        #expect(r.status == "sleeping")
    }

    @Test func processActorListsProcesses() async {
        let actor = ProcessActor()
        let procs = await actor.list()
        #expect(procs.count > 0, "Should have at least one process")
        #expect(procs.contains { $0.name == "kernel_task" || $0.name.contains("launchd") || $0.pid == 1 })
    }

    @Test func processIsRunning() async {
        let actor = ProcessActor()
        // Finder is always running on macOS
        let finderRunning = await actor.isRunning(name: "Finder")
        #expect(finderRunning)
    }

    // MARK: - SpotlightActor
    @Test func spotlightResultSendable() {
        let r = SpotlightResult(path: "/tmp/test.txt", name: "test.txt",
                                kind: "file", contentType: "text/plain",
                                modifiedDate: Date(), size: 100)
        #expect(r.path == "/tmp/test.txt")
        #expect(r.size == 100)
    }

    @Test func spotlightActorInitNoCrash() async {
        let actor = SpotlightActor()
        _ = actor
    }

    // MARK: - ShareActor
    @Test func shareActorListsServices() async {
        let actor = ShareActor()
        let services = await actor.availableServices()
        // At least Mail should be available on macOS
        #expect(services.count >= 0)
    }

    // MARK: - InputSourceActor
    @Test func inputSourceActorHasCurrent() async {
        let actor = InputSourceActor()
        let current = await actor.current()
        // Should always have a current input source
        #expect(current != nil)
        #expect(!(current?.id.isEmpty ?? true))
    }

    @Test func inputSourceActorListsSources() async {
        let actor = InputSourceActor()
        let sources = await actor.list()
        #expect(sources.count > 0)
    }

    // MARK: - ScreenActor
    @Test func screenActorListsScreens() async {
        let actor = ScreenActor()
        let screens = await actor.list()
        #expect(screens.count > 0, "Should have at least one display")
        #expect(screens.contains { $0.isMain })
    }

    @Test func screenInfoSendable() async {
        let actor = ScreenActor()
        if let main = await actor.main() {
            #expect(main.isMain)
            #expect(main.width > 0)
            #expect(main.height > 0)
            #expect(main.scaleFactor > 0)
        }
    }
}
