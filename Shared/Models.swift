import Foundation
import CoreGraphics

enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openai, chatgpt, claude, cursor, openrouter
    var id: String { rawValue }
    var name: String {
        switch self { case .openai: "OpenAI API"; case .chatgpt: "ChatGPT"; case .claude: "Claude"; case .cursor: "Cursor"; case .openrouter: "OpenRouter" }
    }
    var usesAPIKey: Bool { self == .openai || self == .openrouter }
    var credentialAccount: String { rawValue + "-key" }
    var defaultMetricKind: MetricKind { usesAPIKey ? .cost : .remaining }
    var logo: String { self == .chatgpt ? "openai" : rawValue }
    var website: URL {
        let address = switch self {
        case .openai: "https://platform.openai.com/usage"
        case .chatgpt: "https://chatgpt.com/codex/settings/usage"
        case .claude: "https://claude.ai/new#settings/usage"
        case .cursor: "https://cursor.com/dashboard/usage"
        case .openrouter: "https://openrouter.ai/activity"
        }
        return URL(string: address)!
    }
}

enum MetricKind: String, Codable, Sendable { case cost, remaining }
enum ConnectionMode: String, Codable, CaseIterable { case automatic, manual }
enum ReadingState: String, Codable, Sendable { case ready, disconnected, unavailable, reconnect, failed }

enum ConnectionHealth {
    case current, needsRefresh, reconnect, inactive, manual
    var label: String {
        switch self {
        case .current: "Usage updated successfully"
        case .needsRefresh: "Usage needs a successful refresh"
        case .reconnect: "Sign in again"
        case .inactive: "Account not connected"
        case .manual: "Manually entered usage; session not checked"
        }
    }
}

struct Reading: Codable, Equatable, Identifiable, Sendable {
    var provider: Provider
    var kind: MetricKind = .remaining
    var value: Double?
    var currency = "USD"
    var spendLimit: Double?
    var periodStart: Date?
    var periodEnd: Date?
    var window = ""
    var staleAfterSeconds: TimeInterval?
    var fetchedAt: Date?
    var state: ReadingState = .disconnected
    var detail = "Connect your account in AI Pulse."
    var manual = false
    var id: Provider { provider }

    func connectionHealth(at now: Date) -> ConnectionHealth {
        if manual { return .manual }
        if state == .disconnected { return .inactive }
        if state == .reconnect { return .reconnect }
        guard state == .ready, value != nil, let fetchedAt, fetchedAt <= now,
              !isExpired(at: now), !isStale(at: now) else { return .needsRefresh }
        return .current
    }
    func isExpired(at now: Date) -> Bool { periodEnd.map { $0 <= now } ?? false }
    func isStale(at now: Date) -> Bool {
        !manual && (state != .ready || fetchedAt.map { now.timeIntervalSince($0) > (staleAfterSeconds ?? 900) } ?? true)
    }
    func headline(at now: Date = Date()) -> String {
        guard !isExpired(at: now), let value else {
            if isExpired(at: now) { return manual ? "Update period" : "Updating…" }
            switch state {
            case .disconnected: return "Connect"
            case .reconnect: return "Reconnect"
            default: return "Unavailable"
            }
        }
        if kind == .remaining { return "\(Int(value.rounded(.down)))%" }
        return value.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }
    func subtitle(at now: Date = Date()) -> String {
        guard value != nil, !isExpired(at: now) else {
            if isExpired(at: now) { return "Period ended · open AI Pulse" }
            return state == .disconnected ? "Set up account" : state == .reconnect ? "Sign in again" : "Open AI Pulse for details"
        }
        if isStale(at: now) { return "Last known · refresh needed" }
        let date = periodEnd?.formatted(.dateTime.month(.abbreviated).day().hour().minute()) ?? "date unavailable"
        let prefix = manual ? "Entered · " : ""
        return prefix + (kind == .remaining ? "Resets \(date)" : "Until \(date)")
    }
    var spendAllowanceLabel: String? {
        guard provider == .claude, kind == .remaining, let spendLimit,
              spendLimit.isFinite, spendLimit > 0 else { return nil }
        let amount = currency == "USD"
            ? "$" + spendLimit.formatted(.number.precision(.fractionLength(0...2)))
            : spendLimit.formatted(.currency(code: currency).precision(.fractionLength(0...2)))
        return "of \(amount) monthly spend"
    }
    var metricLabel: String {
        if let spendAllowanceLabel { return "left " + spendAllowanceLabel }
        return kind == .cost ? (provider == .openrouter ? "this month · USD" : "this billing period") : (window.isEmpty ? "remaining" : "left · \(window)")
    }
    static var empty: [Reading] { Provider.allCases.map { Reading(provider: $0, kind: $0.defaultMetricKind) } }
}

struct ProviderSettings: Codable, Equatable {
    var provider: Provider
    var mode: ConnectionMode = .automatic
    var connected = false
    var organizationID = ""
    var billingDay = 1
    var manualKind: MetricKind = .cost
    var manualValue: Double = 0
    var currency = "USD"
    var manualStart = Date()
    var manualEnd = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    var manualSaved = false
}

struct UsageWindow: Equatable {
    let used: Double
    let reset: Date
    let label: String
}

enum UsageError: LocalizedError {
    case unauthorized, openAIAuthentication(Int), rateLimited, unavailable(String), malformed, network
    var errorDescription: String? {
        switch self {
        case .unauthorized: "Your session expired or access was denied. Sign in again."
        case .openAIAuthentication(let status): status == 401
            ? "OpenAI rejected the saved key (HTTP 401). Replace it with a valid organization Admin API key, then check again."
            : "OpenAI denied access to organization costs (HTTP 403). Use an organization Admin API key with permission to read usage and costs. If you entered an Organization ID, it must belong to that key."
        case .rateLimited: "The provider requested fewer checks. Retrying later."
        case .unavailable(let reason): reason
        case .malformed: "The provider returned an unrecognized response. No usage value was assumed."
        case .network: "Could not reach the provider. Last known values have been retained."
        }
    }
}

enum BillingPeriod {
    static func current(day: Int, now: Date) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = calendar.dateInterval(of: .month, for: now)!.start
        func anchor(_ month: Date) -> Date {
            let days = calendar.range(of: .day, in: .month, for: month)!.count
            return calendar.date(byAdding: .day, value: min(max(day, 1), days) - 1, to: month)!
        }
        let thisAnchor = anchor(month)
        let startMonth = now < thisAnchor ? calendar.date(byAdding: .month, value: -1, to: month)! : month
        return DateInterval(start: anchor(startMonth), end: anchor(calendar.date(byAdding: .month, value: 1, to: startMonth)!))
    }
}

enum CardPlacement: String { case above, below, before, after }
enum CardArrangement {
    static func normalized(_ rows: [[Provider]], including providers: [Provider]) -> [[Provider]] {
        var seen = Set<Provider>()
        var result = rows.map { row in row.filter { providers.contains($0) && seen.insert($0).inserted } }.filter { !$0.isEmpty }
        let missing = providers.filter { !seen.contains($0) }
        if !missing.isEmpty { result.append(missing) }
        return result
    }
    static func moving(_ source: Provider, relativeTo target: Provider, placement: CardPlacement,
                       in rows: [[Provider]]) -> [[Provider]] {
        guard source != target, rows.joined().contains(source), rows.joined().contains(target) else { return rows }
        var result = rows.map { $0.filter { $0 != source } }.filter { !$0.isEmpty }
        guard let row = result.firstIndex(where: { $0.contains(target) }),
              let column = result[row].firstIndex(of: target) else { return rows }
        switch placement {
        case .above: result.insert([source], at: row)
        case .below: result.insert([source], at: row + 1)
        case .before: result[row].insert(source, at: column)
        case .after: result[row].insert(source, at: column + 1)
        }
        return result
    }
}

struct CardSnapTarget: Equatable {
    let provider: Provider
    let placement: CardPlacement
}
enum CardSnapGeometry {
    static func target(at point: CGPoint, excluding source: Provider,
                       frames: [Provider: CGRect], reach: CGFloat = 90) -> CardSnapTarget? {
        let candidates = frames.filter { $0.key != source }.map { provider, rect in
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return (provider, rect, hypot(dx, dy))
        }.filter { $0.2 <= reach }.sorted {
            if $0.2 != $1.2 { return $0.2 < $1.2 }
            let lhs = hypot($0.1.midX - point.x, $0.1.midY - point.y)
            let rhs = hypot($1.1.midX - point.x, $1.1.midY - point.y)
            return lhs == rhs ? $0.0.rawValue < $1.0.rawValue : lhs < rhs
        }
        guard let (provider, rect, _) = candidates.first else { return nil }
        let edges: [(CardPlacement, CGFloat)] = [
            (.above, abs(point.y - rect.minY)), (.below, abs(point.y - rect.maxY)),
            (.before, abs(point.x - rect.minX)), (.after, abs(point.x - rect.maxX))
        ]
        return CardSnapTarget(provider: provider, placement: edges.min { $0.1 < $1.1 }!.0)
    }
}
