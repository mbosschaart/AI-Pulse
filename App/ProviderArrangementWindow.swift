import AppKit
import SwiftUI

@MainActor final class ProviderArrangementWindow: NSWindowController {
    static let shared = ProviderArrangementWindow()
    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(store: PulseStore) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 440),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Arrange AI Pulse"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ProviderArrangementView().environmentObject(store))
            window.center()
            self.window = window
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ProviderArrangementView: View {
    @EnvironmentObject var store: PulseStore
    @State private var dragged: Provider?
    @State private var translation: CGSize = .zero
    @State private var frames: [Provider: CGRect] = [:]
    @State private var target: CardSnapTarget?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag providers to reorder").font(.headline)
            Text("Widgets with “Follow app order” enabled use this order. Switch providers off to hide them across AI Pulse.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(store.orderedProviders) { provider in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        ProviderLogo(provider: provider, size: 24)
                        Text(provider.name)
                        Spacer()
                        Toggle("Show \(provider.name)", isOn: Binding(get: { store.isEnabled(provider) }, set: { store.setEnabled($0, for: provider) }))
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: CardFramePreference.self, value: [provider: geo.frame(in: .named("arrangement"))])
                    })
                    .overlay(alignment: target?.placement == .above ? .top : .bottom) {
                        if target?.provider == provider { Capsule().fill(provider.accent).frame(height: 3) }
                    }
                    .offset(dragged == provider ? translation : .zero)
                    .opacity(dragged == provider ? 0.85 : 1)
                    .zIndex(dragged == provider ? 1 : 0)
                    .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("arrangement"))
                        .onChanged { value in
                            dragged = provider
                            translation = value.translation
                            if let snap = CardSnapGeometry.target(at: value.location, excluding: provider, frames: frames), let rect = frames[snap.provider] {
                                target = CardSnapTarget(provider: snap.provider, placement: value.location.y < rect.midY ? .above : .below)
                            } else { target = nil }
                        }
                        .onEnded { _ in
                            if let target {
                                store.arrangeWidgetProvider(provider, relativeTo: target.provider, placement: target.placement)
                            }
                            dragged = nil; translation = .zero; target = nil
                        })
                }
            }.coordinateSpace(name: "arrangement")
                .onPreferenceChange(CardFramePreference.self) { frames = $0 }
            Text("Changes are saved automatically.").font(.caption).foregroundStyle(.secondary)
        }.frame(width: 370, height: 400, alignment: .top).padding(20)
    }
}
