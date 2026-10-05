import WidgetKit
import SwiftUI
import AppIntents

enum WidgetProviderChoice: String, AppEnum {
    case openai, chatgpt, claude, cursor, openrouter
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.openai: "OpenAI API", .chatgpt: "ChatGPT", .claude: "Claude", .cursor: "Cursor", .openrouter: "OpenRouter"]
}
enum WidgetRowChoice: String, AppEnum {
    case hidden, openai, chatgpt, claude, cursor, openrouter
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider row"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .hidden: "Hidden", .openai: "OpenAI API", .chatgpt: "ChatGPT", .claude: "Claude", .cursor: "Cursor", .openrouter: "OpenRouter"
    ]
}
struct WidgetOptions: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "AI Pulse"
    static var description = IntentDescription("Choose providers for medium and large widgets. Hidden always removes a row. Follow app order controls ordering only.")
    @Parameter(title: "Small widget provider", default: .openai) var provider: WidgetProviderChoice
    @Parameter(title: "Follow app order", default: true) var followApp: Bool
    @Parameter(title: "First row", default: .openai) var first: WidgetRowChoice
    @Parameter(title: "Second row", default: .chatgpt) var second: WidgetRowChoice
    @Parameter(title: "Third row", default: .claude) var third: WidgetRowChoice
    @Parameter(title: "Fourth row", default: .cursor) var fourth: WidgetRowChoice
    @Parameter(title: "Fifth row", default: .openrouter) var fifth: WidgetRowChoice

    func arranged(_ readings: [Reading], family: WidgetFamily) -> [Reading] {
        guard family != .systemSmall else { return readings }
        return WidgetPresentation.configuredReadings(readings,
            selection: [first, second, third, fourth, fifth].compactMap { Provider(rawValue: $0.rawValue) }, followAppOrder: followApp)
    }
}
struct PulseEntry: TimelineEntry {
    let date: Date
    let readings: [Reading]
    let choice: WidgetProviderChoice
    var isGalleryPreview: Bool = false
}
struct PulseTimeline: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: .now, readings: WidgetPresentation.samples(at: .now), choice: .openai,
                   isGalleryPreview: context.isPreview)
    }
    func snapshot(for configuration: WidgetOptions, in context: Context) async -> PulseEntry {
        let now = Date()
        return PulseEntry(date: now,
                          readings: configuration.arranged(context.isPreview ? WidgetPresentation.samples(at: now) : SnapshotStore.read(), family: context.family),
                          choice: configuration.provider, isGalleryPreview: context.isPreview)
    }
    func timeline(for configuration: WidgetOptions, in context: Context) async -> Timeline<PulseEntry> {
        let now = Date()
        let readings = configuration.arranged(SnapshotStore.read(), family: context.family)
        let entries = WidgetPresentation.timelineDates(readings: readings, now: now).map {
            PulseEntry(date: $0, readings: readings, choice: configuration.provider)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(900)))
    }
}
struct PulseWidgetView: View {
    let entry: PulseEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        PulseWidgetContent(readings: entry.readings,
                           selectedProvider: Provider(rawValue: entry.choice.rawValue) ?? .openai,
                           family: family, now: entry.date)
            .padding(8)
            .environment(\.nativeWidgetAppearance, true)
            .environment(\.connectionLEDVisibility, SnapshotStore.connectionLEDsEnabled)
            .containerBackground(for: .widget) {
                // The gallery supplies its own surface. Keep sample cards transparent
                // there; installed widgets retain the system-managed background.
                if entry.isGalleryPreview {
                    Color.clear
                } else {
                    Color(nsColor: .windowBackgroundColor)
                }
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
            .description("One provider card, Compact rows, or a single column of provider tiles. Edit the widget to arrange or hide rows.")
            .contentMarginsDisabled()
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
