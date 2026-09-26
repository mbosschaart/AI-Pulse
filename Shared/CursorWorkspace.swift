import Foundation

struct CursorWorkspace: Codable, Equatable, Identifiable {
    let id: Int
    let name: String

    static func parse(_ data: Data) throws -> [Self] {
        struct Response: Decodable { let teams: [CursorWorkspace] }
        let teams = try JSONDecoder().decode(Response.self, from: data).teams
        guard teams.allSatisfy({ $0.id > 0 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(teams.map(\.id)).count == teams.count else { throw UsageError.malformed }
        return teams
    }
}

enum CursorWorkspaceUsage {
    static func combined(_ summaries: [(CursorWorkspace, Data)], now: Date = Date()) throws -> Reading {
        guard !summaries.isEmpty, Set(summaries.map { $0.0.id }).count == summaries.count else { throw UsageError.malformed }
        struct Amount: Decodable { let used: Double? }
        struct Individual: Decodable { let overall: Amount? }
        struct Summary: Decodable {
            let billingCycleStart: String
            let billingCycleEnd: String
            let individualUsage: Individual
        }
        let iso = ISO8601DateFormatter()
        func date(_ text: String) -> Date? {
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: text) { return date }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: text)
        }
        var total = 0.0
        var period: DateInterval?
        for (_, data) in summaries {
            let summary = try JSONDecoder().decode(Summary.self, from: data)
            guard let start = date(summary.billingCycleStart), let end = date(summary.billingCycleEnd),
                  start <= now, now < end, start < end else { throw UsageError.malformed }
            let current = DateInterval(start: start, end: end)
            guard period == nil || period == current else {
                throw UsageError.unavailable("These Cursor teams have different billing periods. Select one team to see its usage.")
            }
            period = current
            guard let cents = summary.individualUsage.overall?.used, cents.isFinite, cents >= 0 else {
                throw UsageError.unavailable("Cursor did not report a personal cost total for every team. Select one team to see its allowance or usage.")
            }
            total += cents
            guard total.isFinite else { throw UsageError.malformed }
        }
        return Reading(provider: .cursor, kind: .cost, value: total / 100, currency: "USD",
                       periodStart: period!.start, periodEnd: period!.end, window: "all teams",
                       fetchedAt: now, state: .ready,
                       detail: "Your combined usage across \(summaries.count) Cursor teams for their shared billing period. Other members’ usage and fixed subscription fees are excluded.")
    }
}
