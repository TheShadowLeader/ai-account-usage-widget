import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var states: [ProviderID: ProviderState] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var availableProviders: [ProviderID] = []
    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    init() {
        availableProviders = ProviderID.allCases.filter(ProviderRunner.isInstalled)
        let cached = Cache.load()
        for provider in availableProviders { states[provider] = .loading(cached[provider]) }
        schedule()
        refresh()
    }

    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        refreshTask = Task {
            let indicator = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                if !Task.isCancelled { self?.isRefreshing = false }
            }
            await withTaskGroup(of: (ProviderID, Result<UsageSnapshot, Error>).self) { group in
                if availableProviders.contains(.claude) {
                    group.addTask {
                        do { return (.claude, .success(try await Task.detached { try ProviderRunner.fetchClaude() }.value)) }
                        catch { return (.claude, .failure(error)) }
                    }
                }
                if availableProviders.contains(.codex) {
                    group.addTask {
                        do { return (.codex, .success(try await Task.detached { try ProviderRunner.fetchCodex() }.value)) }
                        catch { return (.codex, .failure(error)) }
                    }
                }
                for await (provider, result) in group { apply(result, for: provider) }
            }
            indicator.cancel()
            isRefreshing = false
            refreshTask = nil
        }
    }

    func schedule() {
        timerTask?.cancel()
        let minutes = max(5, UserDefaults.standard.integer(forKey: "refreshMinutes"))
        if UserDefaults.standard.integer(forKey: "refreshMinutes") == 0 { UserDefaults.standard.set(5, forKey: "refreshMinutes") }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(minutes * 60))
                if !Task.isCancelled { self?.refresh() }
            }
        }
    }

    func clearCache() {
        Cache.clear()
    }

    func applyWindowLevel() {
        let floating = UserDefaults.standard.bool(forKey: "keepOnTop")
        NSApp.windows.filter { $0.title == "AI Usage" }.forEach { $0.level = floating ? .floating : .normal }
    }

    func configureWidgetWindow() {
        guard let window = NSApp.windows.first(where: { $0.title == "AI Usage" }) else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { window.standardWindowButton($0)?.isHidden = true }
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        applyWindowLevel()
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    func primaryPercent(for provider: ProviderID) -> Int? {
        states[provider]?.snapshot?.windows.first?.usedPercent
    }

    private func apply(_ result: Result<UsageSnapshot, Error>, for provider: ProviderID) {
        switch result {
        case .success(let snapshot):
            states[provider] = .current(snapshot)
            Cache.save(snapshot)
        case .failure(let error):
            fputs("\(provider.rawValue) refresh failed: \(error.localizedDescription)\n", stderr)
            Cache.record(error: "\(provider.rawValue): \(error.localizedDescription)")
            if let cached = states[provider]?.snapshot { states[provider] = .stale(cached, error.localizedDescription) }
            else { states[provider] = .unavailable(error.localizedDescription) }
        }
    }
}

enum Cache {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AIUsageWidget/usage.json")
    }

    static func load() -> [ProviderID: UsageSnapshot] {
        guard let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([UsageSnapshot].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.provider, $0) })
    }

    static func save(_ snapshot: UsageSnapshot) {
        var values = load(); values[snapshot.provider] = snapshot
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? JSONEncoder().encode(Array(values.values)) { try? data.write(to: url, options: .atomic) }
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }

    static func record(error: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? Data(error.utf8).write(to: url.deletingLastPathComponent().appendingPathComponent("last-error.txt"), options: .atomic)
    }
}
