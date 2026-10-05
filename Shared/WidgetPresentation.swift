import Foundation

/// Shared, deterministic content decisions; the extension never accesses credentials.
enum WidgetPresentation {
    static func configuredReadings(_ readings: [Reading], selection: [Provider], followAppOrder: Bool) -> [Reading] {
        if followAppOrder {
            let visible = Set(selection)
            return readings.filter { visible.contains($0.provider) }
        }
        return orderedReadings(readings, selection: selection)
    }

    static func orderedReadings(_ readings: [Reading], selection: [Provider]) -> [Reading] {
        var seen = Set<Provider>()
        return selection.compactMap { provider in
            guard seen.insert(provider).inserted else { return nil }
            return readings.first { $0.provider == provider }
        }
    }

    static func selectedReading(in readings: [Reading], provider: Provider) -> Reading? {
        readings.first { $0.provider == provider }
    }

    static func timelineDates(readings: [Reading], now: Date) -> [Date] {
        let horizon = now.addingTimeInterval(86_400)
        var dates: Set<Date> = [now, horizon]
        for reading in readings {
            // Include expiry and stale transitions even if macOS defers our next reload.
            let stale = reading.manual ? nil : reading.fetchedAt?.addingTimeInterval((reading.staleAfterSeconds ?? 900) + 1)
            for date in [reading.periodEnd, stale].compactMap({ $0 }) where date > now && date <= horizon {
                dates.insert(date)
            }
        }
        return dates.sorted()
    }

    static func samples(at now: Date) -> [Reading] {
        Provider.allCases.enumerated().map { index, provider in
            Reading(provider: provider, kind: provider.defaultMetricKind,
                    value: provider.usesAPIKey ? 12.34 : Double(85 - index * 12),
                    periodEnd: now.addingTimeInterval(86_400 * 7),
                    window: provider.usesAPIKey ? "" : "weekly", fetchedAt: now,
                    state: .ready, detail: "Preview data")
        }
    }
}
