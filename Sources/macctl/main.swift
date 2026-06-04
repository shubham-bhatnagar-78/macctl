import ArgumentParser
// CLI entry — wired in Task 14
@main
struct MacCtl: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "macctl", abstract: "stub")
}
