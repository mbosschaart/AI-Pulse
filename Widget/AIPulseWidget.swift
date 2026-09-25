import WidgetKit
import SwiftUI
import AppIntents

enum WidgetProviderChoice: String, AppEnum {
    case openai, chatgpt, claude, cursor
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.openai: "OpenAI API", .chatgpt: "ChatGPT", .claude: "Claude", .cursor: "Cursor"]
}
struct WidgetOptions: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "AI Pulse"
    static var description = IntentDescription("Choose the provider shown by the small widget. Larger widgets show all four.")
    @Parameter(title: "Small widget provider", default: .openai) var provider: WidgetProviderChoice
}
struct PulseEntry: TimelineEntry {
    let date: Date
    let readings: [Reading]
    let choice: WidgetProviderChoice
}
struct PulseTimeline: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PulseEntry { PulseEntry(date: .now, readings: Reading.empty, choice: .openai) }
    func snapshot(for configuration: WidgetOptions, in context: Context) async -> PulseEntry {
        PulseEntry(date: .now, readings: SnapshotStore.read(), choice: configuration.provider)
    }
    func timeline(for configuration: WidgetOptions, in context: Context) async -> Timeline<PulseEntry> {
        let now = Date()
        let readings = SnapshotStore.read()
        // Pre-render the next hour, including expiry boundaries, without polling from the extension.
        var dates = Set((0...12).map { now.addingTimeInterval(Double($0) * 300) })
        for reading in readings {
            if let end = reading.periodEnd, end > now && end < now.addingTimeInterval(3600) { dates.insert(end) }
        }
        let entries = dates.sorted().map { PulseEntry(date: $0, readings: readings, choice: configuration.provider) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(900)))
    }
}
struct PulseWidgetView: View {
    let entry: PulseEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        Group {
            if entry.readings.isEmpty {
                Text("Enable providers in AI Pulse Settings").font(.caption).foregroundStyle(.secondary)
                    .widgetURL(URL(string: "aipulse://settings"))
            } else { switch family {
            case .systemSmall:
                let reading = entry.readings.first { $0.provider.rawValue == entry.choice.rawValue } ?? entry.readings[0]
                MetricCard(reading: reading, compact: true, now: entry.date)
                    .widgetURL(URL(string: "aipulse://\(reading.provider.rawValue)"))
            case .systemMedium:
                VStack(spacing: 5) {
                    ForEach(entry.readings) { reading in
                        Link(destination: URL(string: "aipulse://\(reading.provider.rawValue)")!) { MetricRow(reading: reading, now: entry.date, compact: true) }
                    }
                }
            default:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(entry.readings) { reading in
                        Link(destination: URL(string: "aipulse://\(reading.provider.rawValue)")!) {
                            MetricCard(reading: reading, compact: true, now: entry.date).frame(maxHeight: .infinity)
                        }
                    }
                }
            }
            }
        }.environment(\.liquidGlassCards, SnapshotStore.glassEnabled)
        .environment(\.glassCardStyle, GlassCardStyle(rawValue: SnapshotStore.glassStyle) ?? .standard)
        .containerBackground(for: .widget) {
            if !SnapshotStore.glassEnabled { Color(nsColor: .windowBackgroundColor) }
        }
    }
}
@main struct AIPulseWidgets: WidgetBundle {
    var body: some Widget {
        AIPulseWidget()
    }
}
struct AIPulseWidget: Widget {
    let kind = "AIPulse"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetOptions.self, provider: PulseTimeline()) { entry in PulseWidgetView(entry: entry) }
            .configurationDisplayName("AI Pulse")
            .description("Your billing-period cost or remaining subscription allowance.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
