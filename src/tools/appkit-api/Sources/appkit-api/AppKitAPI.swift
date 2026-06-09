import ArgumentParser

@main
struct AppKitAPI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appkit-api",
        abstract: "Query macOS SDK API existence and availability."
    )
    func run() throws {
        print("appkit-api: no subcommand. Try --help.")
    }
}
