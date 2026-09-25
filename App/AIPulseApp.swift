import SwiftUI
import AppKit
import WidgetKit

@main struct AIPulseApp: App {
    @StateObject private var store = PulseStore()
    var body: some Scene {
        Window("AI Pulse", id: "main") {
            MainView().environmentObject(store)
                .onAppear { StatusBarController.shared.configure(store: store) }
                .onOpenURL { url in
                    if let raw = url.host, let provider = Provider(rawValue: raw) { store.openSettings(provider: provider) }
                    if url.host == "settings" { store.openSettings() }
                    NSApp.activate(ignoringOtherApps: true)
                }
        }.defaultSize(width: 640, height: 580).windowStyle(.hiddenTitleBar).windowResizability(.contentSize)

    }
}

enum DashboardLayout: String, CaseIterable, Identifiable {
    case cards, list
    var id: String { rawValue }
    var title: String { self == .cards ? "Cards" : "Compact" }
}

struct MainView: View {
    @EnvironmentObject var store: PulseStore
    @AppStorage("liquid-glass") private var liquidGlass = false
    @AppStorage("glass-card-style") private var glassStyle: GlassCardStyle = .standard
    @AppStorage("connection-status-leds") private var connectionLEDs = true
    @StateObject private var interaction = DashboardInteraction()
    @AppStorage("dashboard-layout") private var layout: DashboardLayout = .cards
    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if store.visibleReadings.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash").font(.title2).foregroundStyle(.secondary)
                        Text("No providers shown").font(.headline)
                        Button("Settings…") { store.openSettings() }.buttonStyle(.plain).font(.caption)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                } else { switch layout {
                case .list:
                    VStack(spacing: 0) {
                        ForEach(store.visibleReadings) { reading in
                            MetricRow(reading: reading, now: context.date, compact: true)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .contentShape(Rectangle())
                                .contextMenu { dashboardMenu(provider: reading.provider) }
                                .modifier(ProviderReordering(provider: reading.provider, snap: snap, activate: connectionAction(for: reading.provider)))
                        }
                    }
                    .padding(.trailing, 28).padding(.vertical, 3)
                    .overlay(alignment: .bottomTrailing) {
                        Button { Task { await store.refreshAll(force: true) } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11))
                                .frame(width: 20, height: 20).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(liquidGlass && glassStyle != .standard ? Color.white : Color.secondary)
                        .disabled(!store.busy.isEmpty || store.demo)
                        .help("Refresh all providers").accessibilityLabel("Refresh all providers")
                        .padding(.trailing, 10).padding(.bottom, 10)
                    }
                    .modifier(CardSurface(radius: 16))
                case .cards:
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(visibleRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 10) {
                                ForEach(row, id: \.self) { provider in
                                    MetricCard(reading: store.reading(provider), compact: true, now: context.date,
                                               refreshAction: { refresh(provider) }, isRefreshing: store.busy.contains(provider))
                                        .frame(width: 220, height: 158)
                                        .contextMenu { dashboardMenu(provider: provider) }
                                        .modifier(ProviderReordering(provider: provider, snap: snap, activate: connectionAction(for: provider)))
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)

                }
                }
            }.padding(4)

        }
        .frame(width: dashboardWidth)
        .coordinateSpace(name: "dashboard")
        .onPreferenceChange(CardFramePreference.self) { interaction.cardFrames = $0 }
        .background(BorderlessDashboardWindow(interaction: interaction))
        .environmentObject(interaction)
        .environment(\.liquidGlassCards, liquidGlass)
        .environment(\.glassCardStyle, glassStyle)
        .onAppear {
            // Old strip/custom selections now share the saved Cards arrangement.
            if let saved = UserDefaults.standard.string(forKey: "dashboard-layout"),
               DashboardLayout(rawValue: saved) == nil { layout = .cards }
            syncAppearance()
        }
        .onChange(of: liquidGlass) { _, _ in syncAppearance() }
        .onChange(of: connectionLEDs) { _, _ in syncAppearance() }
        .onChange(of: glassStyle) { _, _ in syncAppearance() }
        .contentShape(Rectangle())
        .contextMenu { dashboardMenu() }
        .onChange(of: store.showConnections) { _, visible in
            if visible {
                SettingsWindowController.shared.show(store: store)
                store.showConnections = false
            }
        }
        .alert("AI Pulse", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private func syncAppearance() {
        do { try SnapshotStore.writeConnectionLEDsEnabled(connectionLEDs); try SnapshotStore.writeGlassEnabled(liquidGlass); try SnapshotStore.writeGlassStyle(glassStyle.rawValue); WidgetCenter.shared.reloadAllTimelines() }
        catch { store.error = "Could not save widget appearance." }
    }
    private var initialRows: [[Provider]] {
        store.cardRows.isEmpty ? [store.orderedProviders] : store.cardRows
    }
    private var visibleRows: [[Provider]] { initialRows.map { $0.filter { store.isEnabled($0) } }.filter { !$0.isEmpty } }
    private var dashboardWidth: CGFloat {
        if layout == .list { return 380 }
        let columns = max(1, visibleRows.map(\.count).max() ?? 1)
        return CGFloat(columns) * 220 + CGFloat(columns - 1) * 10 + 8
    }
    private func snap(_ source: Provider, _ target: Provider, _ placement: CardPlacement) {
        if layout == .list {
            store.moveProvider(source, to: target)
        } else {
            store.arrangeProvider(source, relativeTo: target, placement: placement, startingRows: initialRows)
        }
    }
    private func connectionAction(for provider: Provider) -> (() -> Void)? {
        let settings = store.settings(provider)
        let reading = store.reading(provider)
        guard (!settings.connected && !settings.manualSaved) || reading.state == .disconnected || reading.state == .reconnect else { return nil }
        return {
            store.openSettings(provider: provider)
        }
    }
    private func refresh(_ provider: Provider) {
        Task { await store.refresh(provider, force: true) }
    }
    @ViewBuilder private func dashboardMenu(provider: Provider? = nil) -> some View {
        Menu("View") {
            Picker("Layout", selection: $layout) {
                ForEach(DashboardLayout.allCases) { option in Text(option.title).tag(option) }
            }.pickerStyle(.inline)
        }
        Divider()
        Button("Settings…") {
            store.openSettings(provider: provider)
        }
        Button("Refresh") { Task { await store.refreshAll(force: true) } }
            .disabled(!store.busy.isEmpty || store.demo)
    }
}

struct MenuView: View {
    @EnvironmentObject var store: PulseStore
    var openDashboard: () -> Void
    var body: some View {
        VStack(spacing: 15) {
            HStack { Text("AI Pulse").font(.headline); Spacer(); if store.demo { Text("DEMO").font(.caption).foregroundStyle(.secondary) } }
            ForEach(store.visibleReadings) { reading in
                Button { store.openSettings(provider: reading.provider); openDashboard() } label: { MetricRow(reading: reading) }.buttonStyle(.plain)
            }
            Divider()
            HStack {
                Spacer()
                Button { Task { await store.refreshAll(force: true) } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh").disabled(!store.busy.isEmpty || store.demo)
            }.buttonStyle(.plain).font(.caption)
        }.padding(20).frame(width: 340)
    }
}

struct CardFramePreference: PreferenceKey {
    static var defaultValue: [Provider: CGRect] = [:]
    static func reduce(value: inout [Provider: CGRect], nextValue: () -> [Provider: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct ProviderReordering: ViewModifier {
    @EnvironmentObject var interaction: DashboardInteraction
    @Environment(\.liquidGlassCards) private var liquidGlass
    @Environment(\.glassCardStyle) private var glassStyle
    let provider: Provider
    let snap: (Provider, Provider, CardPlacement) -> Void
    var activate: (() -> Void)? = nil
    @State private var reordering: Bool?
    func body(content: Content) -> some View {
        content
            .opacity(interaction.draggedProvider == provider ? 0.25 : 1)
            .contentShape(Rectangle())
            .background(GeometryReader { geometry in
                Color.clear.preference(key: CardFramePreference.self,
                                       value: [provider: geometry.frame(in: .named("dashboard"))])
            })
            .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("dashboard"))
                .onChanged { _ in
                    if reordering == nil {
                        reordering = NSEvent.modifierFlags.contains(.shift)
                        if reordering == true {
                            interaction.beginCardDrag(provider, preview: AnyView(content.environment(\.liquidGlassCards, liquidGlass).environment(\.glassCardStyle, glassStyle)))
                        }
                    }
                    if reordering == true { interaction.updateCardDrag() }
                    else { interaction.moveWindow() }
                }
                .onEnded { _ in
                    if reordering == true {
                        let target = interaction.snapTarget
                        let canSnap = NSEvent.modifierFlags.contains(.shift)
                        interaction.endCardDrag()
                        if canSnap, let target { snap(provider, target.provider, target.placement) }
                    } else { interaction.endMove() }
                    reordering = nil
                }
                .exclusively(before: TapGesture().onEnded {
                    guard !NSEvent.modifierFlags.contains(.shift) else { return }
                    activate?()
                }))
            .accessibilityActions {
                if let activate { Button("Set up \(provider.name)", action: activate) }
            }
            .onHover { _ in interaction.updateModifiers() }
            .overlay {
                if let target = interaction.snapTarget, target.provider == provider {
                    GeometryReader { geometry in
                        let horizontal = target.placement == .above || target.placement == .below
                        RoundedRectangle(cornerRadius: 3).fill(provider.accent)
                            .frame(width: horizontal ? geometry.size.width - 8 : 5,
                                   height: horizontal ? 5 : geometry.size.height - 8)
                            .position(x: target.placement == .before ? 3 : target.placement == .after ? geometry.size.width - 3 : geometry.size.width / 2,
                                      y: target.placement == .above ? 3 : target.placement == .below ? geometry.size.height - 3 : geometry.size.height / 2)
                    }.allowsHitTesting(false)
                }
            }
    }
}

// Apply only to the dashboard; sign-in windows and Settings keep normal window behavior.
struct BorderlessDashboardWindow: NSViewRepresentable {
    let interaction: DashboardInteraction
    final class WindowAnchor: NSView {
        weak var interaction: DashboardInteraction?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }
        func configure() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask = [.borderless, .resizable]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            window.isMovableByWindowBackground = false
            interaction?.attach(window)
        }
    }
    func makeNSView(context: Context) -> WindowAnchor {
        let view = WindowAnchor()
        view.interaction = interaction
        return view
    }
    func updateNSView(_ view: WindowAnchor, context: Context) { view.configure() }
}

@MainActor final class DashboardInteraction: ObservableObject {
    @Published var shiftPressed = NSEvent.modifierFlags.contains(.shift)
    @Published var draggedProvider: Provider?
    @Published var snapTarget: CardSnapTarget?
    var cardFrames: [Provider: CGRect] = [:]
    private var dragPreview: NSPanel?
    private var previewOffset = NSPoint.zero
    func beginCardDrag(_ provider: Provider, preview: AnyView) {
        guard let window, let rect = cardFrames[provider], let contentView = window.contentView else { return }
        let screenRect = window.convertToScreen(NSRect(x: rect.minX, y: contentView.bounds.height - rect.maxY,
                                                       width: rect.width, height: rect.height))
        let panel = NSPanel(contentRect: screenRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: preview.frame(width: rect.width, height: rect.height))
        let mouse = NSEvent.mouseLocation
        previewOffset = NSPoint(x: mouse.x - screenRect.minX, y: mouse.y - screenRect.minY)
        dragPreview = panel
        draggedProvider = provider
        panel.orderFrontRegardless()
    }
    func updateCardDrag() {
        guard let source = draggedProvider, let window, let contentView = window.contentView else { return }
        let mouse = NSEvent.mouseLocation
        dragPreview?.setFrameOrigin(NSPoint(x: mouse.x - previewOffset.x, y: mouse.y - previewOffset.y))
        let local = window.convertPoint(fromScreen: mouse)
        let point = CGPoint(x: local.x, y: contentView.bounds.height - local.y)
        snapTarget = CardSnapGeometry.target(at: point, excluding: source, frames: cardFrames)
    }
    func endCardDrag() {
        dragPreview?.close()
        dragPreview = nil
        draggedProvider = nil
        snapTarget = nil
    }
    private weak var window: NSWindow?
    private var monitor: Any?
    private var startMouse: NSPoint?
    private var startOrigin: NSPoint?
    func attach(_ window: NSWindow) {
        self.window = window
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .leftMouseDown, .mouseMoved]) { [weak self] event in
            self?.shiftPressed = event.modifierFlags.contains(.shift)
            if event.type == .leftMouseDown { self?.endMove(); self?.endCardDrag() }
            return event
        }
    }
    func updateModifiers() { shiftPressed = NSEvent.modifierFlags.contains(.shift) }
    func moveWindow() {
        guard !shiftPressed, let window else { return }
        let mouse = NSEvent.mouseLocation
        guard let startMouse, let startOrigin else {
            self.startMouse = mouse
            self.startOrigin = window.frame.origin
            return
        }
        window.setFrameOrigin(NSPoint(x: startOrigin.x + mouse.x - startMouse.x,
                                      y: startOrigin.y + mouse.y - startMouse.y))
    }
    func endMove() { startMouse = nil; startOrigin = nil }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

@MainActor final class StatusBarController: NSObject {
    static let shared = StatusBarController()
    private var item: NSStatusItem?
    private var store: PulseStore?
    private let popover = NSPopover()
    func configure(store: PulseStore) {
        guard item == nil else { return }
        self.store = store
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        item.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "AI Pulse")
        item.button?.toolTip = "AI Pulse"
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            MenuView(openDashboard: { [weak self] in self?.showDashboard() }).environmentObject(store))
    }
    @objc private func clicked() {
        guard let button = item?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            let menu = NSMenu()
            let show = menu.addItem(withTitle: "Show Widget", action: #selector(showCards), keyEquivalent: "")
            show.target = self
            let settings = menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: "")
            settings.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "Quit AI Pulse", action: #selector(quit), keyEquivalent: "")
            quit.target = self
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    private func showDashboard() {
        popover.performClose(nil)
        let dashboard = NSApp.windows.first { $0.identifier?.rawValue == "main" }
            ?? NSApp.windows.first { $0.title == "AI Pulse" && !$0.isKind(of: NSPanel.self) }
        dashboard?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showCards() {
        store?.showConnections = false
        showDashboard()
    }
    @objc private func settings() {
        showDashboard()
        store?.openSettings()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
