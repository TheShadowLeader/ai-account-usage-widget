import Foundation

@main
enum SelfCheck {
    static func main() throws {
        let codex = #"{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":37,"windowDurationMins":300,"resetsAt":1784546885},"secondary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1785000000},"planType":"plus"}}}"#
        let codexSnapshot = try ProviderParsers.codex(Data(codex.utf8))
        precondition(codexSnapshot.plan == "Plus")
        precondition(codexSnapshot.windows.map(\.usedPercent) == [37, 12])
        precondition(codexSnapshot.windows.map(\.label) == ["5-hour window", "Weekly"])

        let claude = """
        Claude Code · Claude Pro
        Current session
        18% used
        Resets 12:30am (Europe/Belgrade)
        Current week (all models)
        42% used
        Resets Jul 21 at 4pm (Europe/Belgrade)
        Current week (Fable)
        7% used
        """
        let claudeSnapshot = try ProviderParsers.claude(claude)
        precondition(claudeSnapshot.plan == "Pro")
        precondition(claudeSnapshot.windows.map(\.usedPercent) == [18, 42, 7])
        precondition(claudeSnapshot.windows.first?.resetDescription == "12:30am (Europe/Belgrade)")

        do {
            _ = try ProviderParsers.claude("unrelated output")
            fatalError("Malformed Claude output was accepted")
        } catch is UsageError {}
        print("Self-check passed: Codex and Claude parsers")
    }
}
