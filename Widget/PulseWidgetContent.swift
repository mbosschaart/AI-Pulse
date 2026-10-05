import SwiftUI
import WidgetKit

/// Uses the dashboard's actual card and row components, fitted to WidgetKit's fixed sizes.
struct PulseWidgetContent: View {
    let readings: [Reading]
    let selectedProvider: Provider
    let family: WidgetFamily
    let now: Date

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                if let reading = WidgetPresentation.selectedReading(in: readings, provider: selectedProvider) {
                    MetricCard(reading: reading, compact: true, now: now)
                        .widgetURL(url(for: reading.provider))
                } else {
                    emptyState("Enable \(selectedProvider.name)", detail: "Open AI Pulse Settings")
                        .widgetURL(URL(string: "aipulse://\(selectedProvider.rawValue)"))
                }
            case .systemMedium:
                providerList(large: false).widgetURL(URL(string: "aipulse://settings"))
            default:
                providerList(large: true).widgetURL(URL(string: "aipulse://settings"))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func providerList(large: Bool) -> some View {
        if readings.isEmpty {
            emptyState("No providers selected", detail: "Edit this widget or open Settings")
                .widgetURL(URL(string: "aipulse://settings"))
        } else {
            GeometryReader { geometry in
                let available = max(0, geometry.size.height - (large ? 0 : 16))
                let rowHeight = min(large ? 64.0 : 26.0,
                                    (available - (large ? CGFloat(readings.count - 1) * 8 : 0)) / CGFloat(readings.count))
                VStack(spacing: large ? 8 : 0) {
                    ForEach(readings) { reading in
                        Link(destination: url(for: reading.provider)) {
                            if large {
                                MetricRow(reading: reading, now: now, compact: false)
                                    .padding(.horizontal, 12)
                                    .frame(height: rowHeight)
                                    .modifier(CardSurface(accent: reading.provider.accent, radius: 17))
                            } else {
                                MetricRow(reading: reading, now: now, compact: true, widgetDense: true)
                                    .frame(height: rowHeight)
                            }
                        }
                    }
                }
                .padding(large ? 0 : 8)
                .modifier(CompactWidgetSurface(enabled: !large))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func url(for provider: Provider) -> URL { URL(string: "aipulse://\(provider.rawValue)")! }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI Pulse", systemImage: "square.grid.2x2").font(.caption.weight(.semibold))
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(12).modifier(CardSurface())
    }
}

private struct CompactWidgetSurface: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.modifier(CardSurface(radius: 17)) }
        else { content }
    }
}
