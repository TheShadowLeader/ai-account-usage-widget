import Foundation

enum ProviderParsers {
    static func codex(_ data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = root?["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any]
        else { throw UsageError.sourceChanged("Codex rate-limit response changed") }

        var windows: [QuotaWindow] = []
        for (key, fallback) in [("primary", "Primary window"), ("secondary", "Secondary window")] {
            guard let window = rateLimits[key] as? [String: Any],
                  let used = window["usedPercent"] as? Int,
                  (0...100).contains(used)
            else { continue }
            let minutes = window["windowDurationMins"] as? Int
            let label = minutes.map(windowLabel) ?? fallback
            let reset = (window["resetsAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            windows.append(.init(id: key, label: label, usedPercent: used, resetsAt: reset, resetDescription: nil))
        }
        guard !windows.isEmpty else { throw UsageError.sourceChanged("Codex returned no quota windows") }
        return UsageSnapshot(
            provider: .codex,
            plan: (rateLimits["planType"] as? String)?.capitalized,
            windows: windows,
            fetchedAt: fetchedAt,
            sourceVersion: nil
        )
    }

    static func claude(_ output: String, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let clean = stripANSI(output)
        let sections = [
            ("Current session", "Current window", "current"),
            ("Current week (all models)", "Weekly · all models", "weekly"),
            ("Current week (Fable)", "Weekly · Fable", "fable"),
        ]
        var windows: [QuotaWindow] = []
        for (sourceLabel, label, id) in sections {
            guard let start = clean.range(of: sourceLabel) else { continue }
            let tail = String(clean[start.upperBound...].prefix(240))
            guard let percent = firstPercent(in: tail) else { continue }
            let reset = firstCapture(#"Resets\s+([^\r\n]+)"#, in: tail)
            windows.append(.init(id: id, label: label, usedPercent: percent, resetsAt: nil, resetDescription: reset))
        }
        guard !windows.isEmpty else {
            if clean.localizedCaseInsensitiveContains("login") { throw UsageError.commandFailed("Sign in to Claude Code") }
            throw UsageError.sourceChanged("Claude /usage output changed")
        }
        let plan = firstCapture(#"Claude\s+(Pro|Max|Team|Enterprise)"#, in: clean)
        return UsageSnapshot(provider: .claude, plan: plan, windows: windows, fetchedAt: fetchedAt, sourceVersion: nil)
    }

    private static func firstPercent(in text: String) -> Int? {
        guard let value = firstCapture(#"(\d{1,3})%"#, in: text), let percent = Int(value), (0...100).contains(percent) else { return nil }
        return percent
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return text[range].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripANSI(_ text: String) -> String {
        let pattern = #"\u001B(?:\[[0-?]*[ -/]*[@-~]|\][^\u0007]*(?:\u0007|\u001B\\)|[()][A-Z0-9]|[=>])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func windowLabel(_ minutes: Int) -> String {
        if minutes % 10_080 == 0 { return minutes == 10_080 ? "Weekly" : "\(minutes / 10_080) weeks" }
        if minutes % 1_440 == 0 { return minutes == 1_440 ? "Daily" : "\(minutes / 1_440) days" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
    }
}

enum ProviderRunner {
    static func isInstalled(_ provider: ProviderID) -> Bool {
        (try? executable(named: provider == .claude ? "claude" : "codex")) != nil
    }

    static func fetchCodex() throws -> UsageSnapshot {
        let codex = try executable(named: "codex")
        let process = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = codex
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let lock = NSLock()
        var buffer = Data()
        var response: Data?
        let finished = DispatchSemaphore(value: 0)
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard line.count < 1_000_000,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["id"] as? Int == 1
                else { continue }
                response = Data(line)
                finished.signal()
            }
        }
        try process.run()
        try writeJSON(["method": "initialize", "id": 0, "params": ["clientInfo": ["name": "ai_usage_widget", "title": "AI Usage Widget", "version": "1.0.0"]]], to: input)
        try writeJSON(["method": "initialized", "params": [:]], to: input)
        try writeJSON(["method": "account/rateLimits/read", "id": 1], to: input)

        guard finished.wait(timeout: .now() + 20) == .success else {
            process.terminate(); throw UsageError.timedOut
        }
        output.fileHandleForReading.readabilityHandler = nil
        input.fileHandleForWriting.closeFile()
        process.terminate()
        lock.lock(); let data = response; lock.unlock()
        guard let data else { throw UsageError.sourceChanged("Codex returned no response") }
        return try ProviderParsers.codex(data)
    }

    static func fetchClaude() throws -> UsageSnapshot {
        let claude = try executable(named: "claude")
        let process = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", claude.path, "--safe-mode", "--no-chrome", "--ax-screen-reader"]
        process.currentDirectoryURL = trustedWorkingDirectory()
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["TERM"] = "xterm-256color"
        environment["COLUMNS"] = "80"
        environment["LINES"] = "24"
        environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let lock = NSLock()
        let ready = DispatchSemaphore(value: 0)
        var buffer = Data()
        var didSignalReady = false
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            if buffer.count < 2_000_000 { buffer.append(chunk.prefix(2_000_000 - buffer.count)) }
            if !didSignalReady {
                let text = String(decoding: buffer.suffix(20_000), as: UTF8.self)
                if text.contains("Claude Code v") || text.contains("Welcome back") {
                    didSignalReady = true
                    ready.signal()
                }
            }
        }
        try process.run()

        guard ready.wait(timeout: .now() + 45) == .success else {
            input.fileHandleForWriting.closeFile(); process.terminate(); throw UsageError.timedOut
        }
        input.fileHandleForWriting.write(Data("/usage\r".utf8))
        Thread.sleep(forTimeInterval: 6)
        input.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning { process.terminate() }
        output.fileHandleForReading.readabilityHandler = nil
        lock.lock(); let data = buffer; lock.unlock()
        guard data.count < 2_000_000 else { throw UsageError.sourceChanged("Claude output was too large") }
        return try ProviderParsers.claude(String(decoding: data, as: UTF8.self))
    }

    private static func executable(named name: String) throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appendingPathComponent(".local/bin/\(name)"), URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"), URL(fileURLWithPath: "/usr/local/bin/\(name)")]
        guard let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw UsageError.executableMissing(name) }
        return url.resolvingSymlinksInPath()
    }

    private static func trustedWorkingDirectory() -> URL {
        let configured = UserDefaults.standard.string(forKey: "claudeWorkingDirectory")
        if let configured, FileManager.default.fileExists(atPath: configured) { return URL(fileURLWithPath: configured) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func writeJSON(_ object: [String: Any], to pipe: Pipe) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        pipe.fileHandleForWriting.write(data)
    }
}
