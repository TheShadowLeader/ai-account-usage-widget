import AppKit
import ServiceManagement
import SwiftUI

enum WidgetStyle: String, CaseIterable, Identifiable {
    case original = "Original"
    case claude = "Claude"
    case codex = "Codex"
    case gauge = "Gauge"
    case apple = "Apple"
    var id: String { rawValue }
    var size: CGSize { self == .original ? CGSize(width: 380, height: 540) : CGSize(width: 320, height: 214) }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
    var scheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
}

@main
struct AIUsageWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { SettingsView().environmentObject(AppModel.shared).frame(width: 430, height: 360) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let model = AppModel.shared
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var detachedWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        configurePopover()
        updateStatusItem()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
    }

    private func configurePopover() {
        popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverShell().environmentObject(model))
        popover.contentSize = currentStyle.size
    }

    private var currentStyle: WidgetStyle {
        WidgetStyle(rawValue: UserDefaults.standard.string(forKey: "widgetStyle") ?? "Original") ?? .original
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let showPercentages = UserDefaults.standard.bool(forKey: "showMenuPercentages")
        if showPercentages {
            button.title = model.availableProviders.map {
                "\($0 == .claude ? "C" : "O") \(model.primaryPercent(for: $0).map(String.init) ?? "–")%"
            }.joined(separator: " · ")
            button.image = nil
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "AI Usage")
        }
    }

    @objc private func togglePopover() {
        if let detachedWindow, detachedWindow.isVisible {
            detachedWindow.makeKeyAndOrderFront(nil)
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.contentSize = currentStyle.size
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.backgroundColor = .clear
                window.isOpaque = false
                window.makeKey()
            }
        }
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

    func detachableWindow(for popover: NSPopover) -> NSWindow? {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: currentStyle.size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "AI Usage"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.contentViewController = NSHostingController(rootView: PopoverShell().environmentObject(model))
        panel.setContentSize(currentStyle.size)
        panel.center()
        panel.delegate = self
        detachedWindow = panel
        model.applyWindowLevel()
        return panel
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === detachedWindow { detachedWindow = nil }
    }
}

struct PopoverShell: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ContentView()
            .environmentObject(model)
            .background(FrostedBackground())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("widgetStyle") private var styleRaw = WidgetStyle.original.rawValue
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    private var style: WidgetStyle { WidgetStyle(rawValue: styleRaw) ?? .original }
    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        Group {
            switch style {
            case .original: DetailedView()
            case .claude: ClaudeView()
            case .codex: CodexView()
            case .gauge: GaugeView()
            case .apple: AppleView()
            }
        }
        .environmentObject(model)
        .frame(width: style.size.width, height: style.size.height)
        .preferredColorScheme(appearance.scheme)
        .onAppear { resizeWindow() }
        .onChange(of: styleRaw) { resizeWindow() }
    }

    private func resizeWindow() {
        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.title == "AI Usage" })?.setContentSize(style.size)
            model.applyWindowLevel()
        }
    }
}

struct DetailedView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Usage").font(.title2.bold())
                    Text("Account-wide subscription limits").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(model.isRefreshing).help("Refresh now")
                    .accessibilityLabel("Refresh usage")
            }
            ForEach(model.availableProviders) { provider in
                ProviderCard(provider: provider, state: model.states[provider] ?? .loading(nil))
            }
            HStack {
                if model.isRefreshing { ProgressView().controlSize(.small); Text("Refreshing…") }
                else { Text("Refreshes every \(max(5, UserDefaults.standard.integer(forKey: "refreshMinutes"))) minutes") }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(minWidth: 350, idealWidth: 380)
        .background(.ultraThinMaterial)
        .onAppear { model.applyWindowLevel() }
    }
}

struct GaugeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 6) {
            CompactHeader(title: "Usage")
            HStack(spacing: 20) {
                ForEach(model.availableProviders) { provider in
                    VStack(spacing: 7) {
                        ZStack {
                            Circle().stroke(provider.tint.opacity(colorScheme == .light ? 0.42 : 0.16), lineWidth: 9)
                            Circle().trim(from: 0, to: Double(model.primaryPercent(for: provider) ?? 0) / 100)
                                .stroke(provider.tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(model.primaryPercent(for: provider).map { "\($0)%" } ?? "—")
                                .font(.title3.bold()).monospacedDigit()
                        }.frame(width: 82, height: 82)
                        Text(provider.rawValue).font(.caption.bold())
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

struct ClaudeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompactHeader(title: "Usage", mascot: true)
            ForEach(model.availableProviders) { provider in CompactRow(provider: provider, meter: false) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(Color.clear)
    }
}

struct CodexView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            CompactHeader(title: "Usage")
            ForEach(model.availableProviders) { provider in CompactRow(provider: provider, meter: true) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color.clear)
    }
}

struct AppleView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            CompactHeader(title: "Usage")
            HStack(spacing: 10) {
                ForEach(model.availableProviders) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(provider.rawValue).font(.caption.bold()).foregroundStyle(.secondary)
                        Text(model.primaryPercent(for: provider).map { "\($0)%" } ?? "—")
                            .font(.system(size: 31, weight: .bold, design: .rounded)).monospacedDigit()
                        ProgressView(value: Double(model.primaryPercent(for: provider) ?? 0), total: 100).tint(provider.tint)
                        Text("used").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.35)))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

struct CompactHeader: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    var mascot = false

    var body: some View {
        HStack(spacing: 8) {
            if mascot { ClaudeMascot().scaleEffect(0.62).frame(width: 34, height: 28) }
            Text(title).font(.headline)
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                .accessibilityLabel("Refresh usage")
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Settings")
        }
        .foregroundStyle(.primary)
    }
}

struct CompactRow: View {
    @EnvironmentObject private var model: AppModel
    let provider: ProviderID
    let meter: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.rawValue).font(.subheadline.bold())
                Text(model.states[provider]?.snapshot?.plan ?? "Account").font(.caption2).foregroundStyle(.secondary)
            }.frame(width: 72, alignment: .leading)
            if meter { PixelMeter(percent: model.primaryPercent(for: provider), tint: provider.tint) }
            else { ProgressView(value: Double(model.primaryPercent(for: provider) ?? 0), total: 100).tint(provider.tint) }
            Text(model.primaryPercent(for: provider).map { "\($0)%" } ?? "—")
                .font(.headline).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}

struct PixelMeter: View {
    let percent: Int?
    let tint: Color

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(8), spacing: 3), count: 8), spacing: 3) {
            ForEach(0..<24, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < Int(Double(percent ?? 0) * 0.24) ? tint : Color.white.opacity(0.13))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

struct ClaudeMascot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false
    private let orange = Color(red: 0.88, green: 0.38, blue: 0.25)

    var body: some View {
        ZStack {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(8), spacing: 0), count: 7), spacing: 0) {
                ForEach(0..<35, id: \.self) { index in
                    let rows = [2, 5, 7, 1, 3]
                    let row = index / 7
                    let col = index % 7
                    Rectangle().fill(rows[row] == 7 || (rows[row] == 5 && col > 0 && col < 6) || (rows[row] == 2 && col > 1 && col < 5) || (rows[row] == 1 && (col == 1 || col == 3 || col == 5)) ? orange : .clear)
                        .frame(width: 8, height: 8)
                }
            }
            HStack(spacing: 10) {
                Rectangle().fill(Color.black.opacity(0.72)).frame(width: 5, height: 5)
                Rectangle().fill(Color.black.opacity(0.72)).frame(width: 5, height: 5)
            }.offset(y: -8)
        }
        .frame(width: 56, height: 40)
        .offset(y: lifted ? -2 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { lifted = true }
        }
        .accessibilityLabel("Claude mascot")
    }
}

extension ProviderID {
    var tint: Color { self == .claude ? .orange : .blue }
}

struct ProviderCard: View {
    let provider: ProviderID
    let state: ProviderState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: provider == .claude ? "sparkles" : "terminal")
                    .frame(width: 28, height: 28).background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                Text(provider.rawValue).font(.headline)
                if let plan = state.snapshot?.plan { Text(plan).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                status
            }
            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    VStack(spacing: 5) {
                        HStack { Text(window.label); Spacer(); Text("\(window.usedPercent)% used").monospacedDigit() }
                        ProgressView(value: Double(window.usedPercent), total: 100)
                            .accessibilityLabel("\(provider.rawValue), \(window.label)")
                            .accessibilityValue("\(window.usedPercent) percent used")
                        HStack {
                            if let reset = resetText(window) { Text("Resets \(reset)") }
                            Spacer(); Text(snapshot.fetchedAt, style: .relative)
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else if case .unavailable(let message) = state {
                Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.4)))
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .loading: Text("Loading").foregroundStyle(.secondary)
        case .current: Label("Current", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .stale(_, let reason): Label("Stale", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange).help(reason)
        case .unavailable: Text("Unavailable").foregroundStyle(.secondary)
        }
    }

    private func resetText(_ window: QuotaWindow) -> String? {
        if let date = window.resetsAt { return date.formatted(date: .abbreviated, time: .shortened) }
        return window.resetDescription
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("refreshMinutes") private var refreshMinutes = 5
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("showMenuPercentages") private var showMenuPercentages = false
    @AppStorage("keepOnTop") private var keepOnTop = false
    @AppStorage("widgetStyle") private var widgetStyle = WidgetStyle.original.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            Picker("Layout", selection: $widgetStyle) {
                ForEach(WidgetStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Picker("Refresh", selection: $refreshMinutes) { ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) minutes") } }
                .onChange(of: refreshMinutes) { model.schedule() }
            Toggle("Show in menu bar", isOn: $showMenuBar)
            Toggle("Show percentages in menu bar", isOn: $showMenuPercentages).disabled(!showMenuBar)
            Toggle("Keep window on top", isOn: $keepOnTop).onChange(of: keepOnTop) { model.applyWindowLevel() }
            Toggle("Launch at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) {
                do { try model.setLaunchAtLogin(launchAtLogin); launchError = nil }
                catch { launchAtLogin.toggle(); launchError = error.localizedDescription }
            }
            if let launchError { Text(launchError).font(.caption).foregroundStyle(.red) }
            Divider()
            if model.availableProviders.contains(.claude) {
                LabeledContent("Claude source", value: "Claude Code /usage")
            }
            if model.availableProviders.contains(.codex) { LabeledContent("Codex source", value: "Codex app-server") }
            Button("Clear cached usage") { model.clearCache() }
        }
        .padding(20)
        .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.scheme)
    }
}
