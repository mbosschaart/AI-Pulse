import Foundation

/// Provider polling only; Sparkle software-update checks have a separate policy.
enum UsageRefreshInterval: Int, CaseIterable, Identifiable {
    case daily = 86400
    case hourly = 3600
    case thirtyMinutes = 1800
    case fifteenMinutes = 900
    case fiveMinutes = 300

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var title: String {
        switch self {
        case .daily: "Daily"
        case .hourly: "Hourly"
        case .thirtyMinutes: "30 min"
        case .fifteenMinutes: "15 min"
        case .fiveMinutes: "5 min"
        }
    }
    static func saved(_ value: Int) -> Self { Self(rawValue: value) ?? .hourly }
    var freshnessWindow: TimeInterval { max(900, seconds + 300) }
    func nextCheck(after lastAttempt: Date?, now: Date) -> Date {
        // A clock moving backwards must not suppress checks for an entire interval.
        guard let lastAttempt, lastAttempt <= now else { return now }
        return max(now, lastAttempt.addingTimeInterval(seconds))
    }
    func isDue(after lastAttempt: Date?, now: Date) -> Bool {
        nextCheck(after: lastAttempt, now: now) <= now
    }
}
