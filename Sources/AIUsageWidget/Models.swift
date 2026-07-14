import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable {
    case claude = "Claude"
    case codex = "Codex"
    var id: String { rawValue }
}

struct QuotaWindow: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let usedPercent: Int
    let resetsAt: Date?
    let resetDescription: String?
}

struct UsageSnapshot: Codable, Equatable {
    let provider: ProviderID
    let plan: String?
    let windows: [QuotaWindow]
    let fetchedAt: Date
    let sourceVersion: String?
}

enum ProviderState: Equatable {
    case loading(UsageSnapshot?)
    case current(UsageSnapshot)
    case stale(UsageSnapshot, String)
    case unavailable(String)

    var snapshot: UsageSnapshot? {
        switch self {
        case .loading(let value): value
        case .current(let value), .stale(let value, _): value
        case .unavailable: nil
        }
    }
}

enum UsageError: LocalizedError {
    case executableMissing(String)
    case timedOut
    case commandFailed(String)
    case sourceChanged(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let name): "\(name) is not installed"
        case .timedOut: "Usage request timed out"
        case .commandFailed(let message): message
        case .sourceChanged(let message): message
        }
    }
}
