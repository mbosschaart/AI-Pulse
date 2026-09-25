import SwiftUI
import AppKit

@MainActor final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(store: PulseStore) {
        if window == nil {
            let view = SettingsContent().environmentObject(store)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "AI Pulse Settings"
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.contentView = NSHostingView(rootView: view)
            window.minSize = NSSize(width: 620, height: 480)
            window.setFrameAutosaveName("AI-Pulse-Settings")
            if !window.setFrameUsingName("AI-Pulse-Settings") {
                window.center()
                if let dashboard = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }),
                   let screen = dashboard.screen {
                    let area = screen.visibleFrame
                    let right = dashboard.frame.maxX + 20
                    let left = dashboard.frame.minX - window.frame.width - 20
                    let x = right + window.frame.width <= area.maxX ? right : max(area.minX, left)
                    let y = min(max(dashboard.frame.maxY - window.frame.height, area.minY), area.maxY - window.frame.height)
                    window.setFrameOrigin(NSPoint(x: x, y: y))
                }
            }
            self.window = window
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        UpdateController.shared.settingsOpened()
    }
}

private struct SettingsContent: View {
    @EnvironmentObject var store: PulseStore
    @ObservedObject private var updates = UpdateController.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Settings", selection: Binding(
                    get: { store.settingsProvider },
                    set: { provider in
                        store.settingsProvider = provider
                        if let provider { store.selected = provider }
                    }
                )) {
                    Text("General · All providers").tag(Optional<Provider>.none)
                    Divider()
                    ForEach(Provider.allCases) { provider in
                        Text(provider.name).tag(Optional(provider))
                    }
                }.pickerStyle(.menu)
                Divider()
                if store.settingsProvider != nil {
                    ConnectionsView()
                } else {
                    GeneralSettingsView()
                    Divider()
                HStack {
                    Text("AI Pulse \(UpdateController.version)").font(.headline)
                    Text("Build \(UpdateController.build)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for updates") { updates.checkForUpdates() }.disabled(!updates.canCheck)
                }
                Text(updates.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Checks once when Settings first opens after launch, or when you click Check for updates.")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24)
        }.frame(minWidth: 600, idealWidth: 660, minHeight: 440, idealHeight: 740)
    }
}
