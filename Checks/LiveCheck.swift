import Foundation

@main
enum LiveCheck {
    static func main() {
        for (name, fetch) in [("Codex", ProviderRunner.fetchCodex), ("Claude", ProviderRunner.fetchClaude)] {
            do {
                let snapshot = try fetch()
                print("\(name): \(snapshot.plan ?? "Unknown plan")")
                for window in snapshot.windows { print("  \(window.label): \(window.usedPercent)% used") }
            } catch {
                print("\(name) failed: \(error.localizedDescription)")
                exit(1)
            }
        }
    }
}
