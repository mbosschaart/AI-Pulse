import XCTest
@testable import AIPulseCore

final class WidgetPresentationTests: XCTestCase {
    func testHiddenSelectionsApplyWhileFollowingAppOrder() {
        let readings = [Reading(provider: .cursor), Reading(provider: .claude), Reading(provider: .openai)]
        let selection: [Provider] = [.openai, .cursor]
        XCTAssertEqual(WidgetPresentation.configuredReadings(readings, selection: selection, followAppOrder: true).map(\.provider), [.cursor, .openai])
        XCTAssertEqual(WidgetPresentation.configuredReadings(readings, selection: selection, followAppOrder: false).map(\.provider), [.openai, .cursor])
        XCTAssertTrue(WidgetPresentation.configuredReadings(readings, selection: [], followAppOrder: true).isEmpty)
        XCTAssertTrue(WidgetPresentation.configuredReadings(readings, selection: [], followAppOrder: false).isEmpty)
    }

    func testCustomRowsPreserveOrderHideOmittedAndDeduplicate() {
        let readings = Reading.empty.filter { $0.provider != .cursor }
        let selected = WidgetPresentation.orderedReadings(readings, selection: [.claude, .openai, .claude, .cursor])
        XCTAssertEqual(selected.map(\.provider), [.claude, .openai])
        XCTAssertTrue(WidgetPresentation.orderedReadings(readings, selection: []).isEmpty)
    }

    func testDisabledSelectionNeverSubstitutesAnotherProvider() {
        let readings = [Reading(provider: .claude, value: 71)]
        XCTAssertNil(WidgetPresentation.selectedReading(in: readings, provider: .cursor))
        XCTAssertEqual(WidgetPresentation.selectedReading(in: readings, provider: .claude)?.value, 71)
    }

    func testTimelineIncludesStaleAndExpiryTransitionsBeyondReloadRequest() {
        let now = Date(timeIntervalSince1970: 100_000)
        let reading = Reading(provider: .claude, value: 71,
                              periodEnd: now.addingTimeInterval(7200),
                              staleAfterSeconds: 3600, fetchedAt: now, state: .ready)
        let dates = WidgetPresentation.timelineDates(readings: [reading], now: now)
        XCTAssertEqual(dates, [now, now.addingTimeInterval(3601), now.addingTimeInterval(7200), now.addingTimeInterval(86_400)])
        XCTAssertTrue(reading.isStale(at: dates[1]))
        XCTAssertTrue(reading.isExpired(at: dates[2]))
    }

    func testManualAndPastBoundariesDoNotAddStaleEntries() {
        let now = Date(timeIntervalSince1970: 100_000)
        let manual = Reading(provider: .cursor, value: 50, fetchedAt: now, manual: true)
        let expired = Reading(provider: .claude, value: 50, periodEnd: now.addingTimeInterval(-1), fetchedAt: now.addingTimeInterval(-2000))
        XCTAssertEqual(WidgetPresentation.timelineDates(readings: [manual, expired], now: now), [now, now.addingTimeInterval(86_400)])
    }
}
