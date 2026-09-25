import SwiftUI

extension Provider {
    var accent: Color {
        switch self {
        case .openai: Color(red: 0.29, green: 0.70, blue: 0.60)
        case .chatgpt: Color(red: 0.61, green: 0.64, blue: 0.75)
        case .claude: Color(red: 0.83, green: 0.57, blue: 0.41)
        case .cursor: Color(red: 0.64, green: 0.61, blue: 0.91)
        }
    }
}

struct ProviderLogo: View {
    let provider: Provider
    var size: CGFloat = 28
    var body: some View {
        Image(provider.logo).resizable().scaledToFit().padding(size * 0.17)
            .frame(width: size, height: size)
            .background(.white, in: RoundedRectangle(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

enum GlassCardStyle: String, CaseIterable, Identifiable {
    case standard, clear, smoked
    var id: String { rawValue }
    var title: String {
        switch self { case .standard: "Standard"; case .clear: "Clear · white text"; case .smoked: "Smoked · white text" }
    }
}
private struct ConnectionLEDVisibilityKey: EnvironmentKey { static let defaultValue: Bool? = nil }
private struct GlassCardStyleKey: EnvironmentKey { static let defaultValue = GlassCardStyle.standard }
private struct LiquidGlassCardsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var connectionLEDVisibility: Bool? {
        get { self[ConnectionLEDVisibilityKey.self] }
        set { self[ConnectionLEDVisibilityKey.self] = newValue }
    }
    var glassCardStyle: GlassCardStyle {
        get { self[GlassCardStyleKey.self] }
        set { self[GlassCardStyleKey.self] = newValue }
    }
    var liquidGlassCards: Bool {
        get { self[LiquidGlassCardsKey.self] }
        set { self[LiquidGlassCardsKey.self] = newValue }
    }
}
struct CardSurface: ViewModifier {
    @Environment(\.liquidGlassCards) private var enabled
    @Environment(\.glassCardStyle) private var style
    var accent: Color = .clear
    var radius: CGFloat = 17
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            if style == .clear {
                // Fade only the glass layer, keeping all foreground content fully opaque.
                content.background {
                    if #available(macOS 26.0, *) {
                        Color.clear.glassEffect(.clear, in: RoundedRectangle(cornerRadius: radius))
                            .opacity(0.50)
                    } else {
                        RoundedRectangle(cornerRadius: radius).fill(.white.opacity(0.025))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
            } else if #available(macOS 26.0, *) {
                switch style {
                case .standard:
                    content.glassEffect(.regular.tint(accent.opacity(0.06)), in: RoundedRectangle(cornerRadius: radius))
                case .clear:
                    content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: radius))
                case .smoked:
                    content.glassEffect(.clear.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: radius))
                }
            } else {
                content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            }
        } else {
            content
                .background(accent.opacity(0.045), in: RoundedRectangle(cornerRadius: radius))
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.055), lineWidth: 1))
        }
    }
}

struct ConnectionHealthLED: View {
    @AppStorage("connection-status-leds") private var enabled = true
    @Environment(\.connectionLEDVisibility) private var visibilityOverride
    let reading: Reading
    var now: Date
    private var health: ConnectionHealth { reading.connectionHealth(at: now) }
    private var color: Color {
        switch health {
        case .current: .green
        case .needsRefresh: .orange
        case .reconnect: .red
        case .inactive, .manual: .gray
        }
    }
    var body: some View {
        if visibilityOverride ?? enabled {
        Circle().fill(color.gradient)
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.4), radius: 2)
            .help(health.label)
            .accessibilityLabel(health.label)
        }
    }
}

struct MetricCard: View {
    @Environment(\.liquidGlassCards) private var glassEnabled
    @Environment(\.glassCardStyle) private var glassStyle
    private var whiteText: Bool { glassEnabled && glassStyle != .standard }

    let reading: Reading
    var compact = false
    var now = Date()
    var refreshAction: (() -> Void)? = nil
    var isRefreshing = false
    private var available: Bool { reading.value != nil && !reading.isExpired(at: now) }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            HStack(spacing: 9) {
                ProviderLogo(provider: reading.provider, size: compact ? 23 : 30)
                Text(reading.provider.name).font(.system(size: compact ? 12 : 14, weight: .medium))
                Spacer(minLength: 0)
                ConnectionHealthLED(reading: reading, now: now)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.headline(at: now))
                    .font(.system(size: available ? (compact ? 30 : 39) : (compact ? 18 : 24), weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                Text(available ? reading.metricLabel : " ")
                    .font(.system(size: compact ? 10 : 12)).foregroundStyle(whiteText ? Color.white : Color.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if reading.kind == .remaining, let value = reading.value, available {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.07))
                        Capsule().fill(reading.isStale(at: now) ? .gray : reading.provider.accent)
                            .frame(width: geo.size.width * min(100, max(0, value)) / 100)
                    }
                }.frame(height: 4).accessibilityHidden(true)
            } else { Color.clear.frame(height: 4) }
            HStack(alignment: .bottom, spacing: 6) {
                Text(reading.subtitle(at: now)).font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(whiteText ? Color.white : Color.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let refreshAction {
                    ProviderRefreshButton(provider: reading.provider, busy: isRefreshing, action: refreshAction)
                }
            }
        }
        .foregroundStyle(whiteText ? Color.white : Color.primary)
        .padding(compact ? 13 : 20)
        .modifier(CardSurface(accent: reading.provider.accent, radius: compact ? 17 : 22))
        .accessibilityElement(children: refreshAction == nil ? .combine : .contain)
    }
}

struct MetricRow: View {
    @Environment(\.liquidGlassCards) private var glassEnabled
    @Environment(\.glassCardStyle) private var glassStyle
    private var whiteText: Bool { glassEnabled && glassStyle != .standard }

    let reading: Reading
    var now = Date()
    var compact = false
    var refreshAction: (() -> Void)? = nil
    var isRefreshing = false
    var body: some View {
        HStack(spacing: 10) {
            ProviderLogo(provider: reading.provider, size: 25)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(reading.provider.name).font(.system(size: 12, weight: .medium))
                    ConnectionHealthLED(reading: reading, now: now)
                }
                Text(reading.subtitle(at: now)).font(.system(size: 10)).foregroundStyle(whiteText ? Color.white : Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(reading.headline(at: now))
                    .font(.system(size: compact ? 14 : 17, weight: .semibold, design: .rounded)).monospacedDigit()
                if reading.value != nil && !reading.isExpired(at: now) {
                    Text(reading.metricLabel).font(.system(size: 9)).foregroundStyle(whiteText ? Color.white : Color.secondary).lineLimit(1)
                }
            }
            if let refreshAction {
                ProviderRefreshButton(provider: reading.provider, busy: isRefreshing, action: refreshAction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }.foregroundStyle(whiteText ? Color.white : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: refreshAction == nil ? .combine : .contain)
    }
}

struct ProviderRefreshButton: View {
    @Environment(\.liquidGlassCards) private var glassEnabled
    @Environment(\.glassCardStyle) private var glassStyle
    private var whiteText: Bool { glassEnabled && glassStyle != .standard }

    let provider: Provider
    let busy: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise").font(.system(size: 11))
                .frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(whiteText ? Color.white : Color.secondary)
        .disabled(busy)
        .help(busy ? "Checking \(provider.name)…" : "Refresh \(provider.name)")
        .accessibilityLabel("Refresh \(provider.name)")
    }
}
