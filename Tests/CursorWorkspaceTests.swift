import XCTest
@testable import AIPulseCore

final class CursorWorkspaceTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00Z")!
    func summary(_ cents: Double, end: String = "2026-10-01T00:00:00Z") -> Data {
        Data("{\"billingCycleStart\":\"2026-09-01T00:00:00Z\",\"billingCycleEnd\":\"\(end)\",\"individualUsage\":{\"overall\":{\"used\":\(cents)}},\"teamUsage\":{\"onDemand\":{\"used\":999999}}}".utf8)
    }
    func testCombinedCostUsesOnlyPersonalTotals() throws {
        let result = try CursorWorkspaceUsage.combined([(.init(id: 1, name: "One"),summary(150)),(.init(id: 2, name: "Two"),summary(275))], now: now)
        XCTAssertEqual(result.value, 4.25)
        XCTAssertEqual(result.kind, .cost)
        XCTAssertEqual(result.metricLabel, "all teams")
    }
    func testDifferentPeriodsAndMissingPersonalTotalsFailClosed() {
        XCTAssertThrowsError(try CursorWorkspaceUsage.combined([(.init(id: 1,name: "One"),summary(150)),(.init(id: 2,name: "Two"),summary(275,end: "2026-10-02T00:00:00Z"))],now: now))
        XCTAssertThrowsError(try CursorWorkspaceUsage.combined([(.init(id: 1,name: "One"),Data("{}".utf8))],now: now))
        XCTAssertThrowsError(try CursorWorkspaceUsage.combined([],now: now))
        XCTAssertThrowsError(try CursorWorkspaceUsage.combined([(.init(id: 1,name: "One"),summary(-1))],now: now))
        XCTAssertThrowsError(try CursorWorkspaceUsage.combined([(.init(id: 1,name: "One"),summary(1)),(.init(id: 1,name: "One"),summary(1))],now: now))
    }
    func testTeamDiscoveryAndOldPreferences() throws {
        let teams = try CursorWorkspace.parse(Data(#"{"teams":[{"id":7,"name":"Platform"},{"id":8,"name":"Growth"}]}"#.utf8))
        XCTAssertEqual(teams.map(\.name),["Platform","Growth"])
        XCTAssertThrowsError(try CursorWorkspace.parse(Data(#"{"teams":[{"id":7,"name":"One"},{"id":7,"name":"Two"}]}"#.utf8)))
        var settings = ProviderSettings(provider:.cursor)
        settings.connected = true
        let old = try JSONEncoder().encode(settings)
        XCTAssertNil(try JSONDecoder().decode(ProviderSettings.self,from:old).cursorWorkspaceID)
        settings.cursorWorkspaceID = "8"
        settings.cursorWorkspaces = teams
        XCTAssertEqual(try JSONDecoder().decode(ProviderSettings.self,from:JSONEncoder().encode(settings)),settings)
    }
}
