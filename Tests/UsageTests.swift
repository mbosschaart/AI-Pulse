import XCTest
@testable import AIPulseCore

final class UsageTests: XCTestCase {
    func testConnectionHealthRequiresSuccessfulCurrentAutomaticReading() {
        let now = Date(timeIntervalSince1970: 100000)
        var reading = Reading(provider: .claude, value: 75, fetchedAt: now, state: .ready)
        XCTAssertEqual(reading.connectionHealth(at: now), .current)
        XCTAssertEqual(reading.connectionHealth(at: now.addingTimeInterval(901)), .needsRefresh)
        reading.staleAfterSeconds = 3900
        XCTAssertEqual(reading.connectionHealth(at: now.addingTimeInterval(1800)), .current)
        for state in [ReadingState.failed, .unavailable] {
            reading.state = state
            XCTAssertEqual(reading.connectionHealth(at: now), .needsRefresh)
        }
        reading.state = .reconnect
        XCTAssertEqual(reading.connectionHealth(at: now), .reconnect)
        reading.state = .disconnected
        XCTAssertEqual(reading.connectionHealth(at: now), .inactive)
        reading.manual = true
        XCTAssertEqual(reading.connectionHealth(at: now), .manual)
        reading.manual = false
        reading.state = .ready
        reading.periodEnd = now
        XCTAssertEqual(reading.connectionHealth(at: now), .needsRefresh)
        reading.periodEnd = nil
        reading.fetchedAt = nil
        XCTAssertEqual(reading.connectionHealth(at: now), .needsRefresh)
        reading.fetchedAt = now.addingTimeInterval(1)
        XCTAssertEqual(reading.connectionHealth(at: now), .needsRefresh)
    }

    func testUsageRefreshDefaultsAndChoices() {
        XCTAssertEqual(UsageRefreshInterval.saved(0), .hourly)
        XCTAssertEqual(UsageRefreshInterval.saved(-1), .hourly)
        XCTAssertEqual(UsageRefreshInterval.allCases.map(\.rawValue), [86400, 3600, 1800, 900, 300])
        for interval in UsageRefreshInterval.allCases { XCTAssertEqual(UsageRefreshInterval.saved(interval.rawValue), interval) }
    }
    func testUsageRefreshDueBoundariesAndWakeResume() {
        let previous = Date(timeIntervalSince1970: 100000)
        for interval in UsageRefreshInterval.allCases {
            let due = previous.addingTimeInterval(interval.seconds)
            XCTAssertFalse(interval.isDue(after: previous, now: due.addingTimeInterval(-1)))
            XCTAssertTrue(interval.isDue(after: previous, now: due))
            XCTAssertEqual(interval.nextCheck(after: previous, now: previous), due)
            XCTAssertTrue(interval.isDue(after: previous, now: due.addingTimeInterval(3600)))
        }
        XCTAssertTrue(UsageRefreshInterval.hourly.isDue(after: nil, now: previous))
        XCTAssertTrue(UsageRefreshInterval.hourly.isDue(after: previous.addingTimeInterval(10), now: previous))
        let later = previous.addingTimeInterval(1800)
        XCTAssertFalse(UsageRefreshInterval.hourly.isDue(after: previous, now: later))
        XCTAssertTrue(UsageRefreshInterval.fifteenMinutes.isDue(after: previous, now: later))
    }
    func testReadingFreshnessFollowsSelectedRefreshRate() throws {
        let fetched = Date(timeIntervalSince1970: 100000)
        for interval in UsageRefreshInterval.allCases {
            var reading = Reading(provider: .openai, value: 10, fetchedAt: fetched, state: .ready)
            reading.staleAfterSeconds = interval.freshnessWindow
            XCTAssertFalse(reading.isStale(at: fetched.addingTimeInterval(interval.seconds)))
            XCTAssertTrue(reading.isStale(at: fetched.addingTimeInterval(interval.freshnessWindow + 1)))
            reading.state = .failed
            XCTAssertTrue(reading.isStale(at: fetched))
        }
        let legacy = try JSONDecoder().decode(Reading.self, from: JSONEncoder().encode(Reading(provider: .openai)))
        XCTAssertNil(legacy.staleAfterSeconds)
    }
    func testUpdateChecksOnlyOnFirstSettingsOpeningPerSession() {
        var policy = UpdateCheckPolicy()
        XCTAssertFalse(policy.hasOpenedSettings)
        XCTAssertTrue(policy.settingsOpened())
        XCTAssertFalse(policy.settingsOpened())
        XCTAssertFalse(policy.settingsOpened())
        var nextSession = UpdateCheckPolicy()
        XCTAssertTrue(nextSession.settingsOpened())
    }
    let now = ISO8601DateFormatter().date(from: "2026-09-25T10:00:00Z")!
    func data(_ text: String) -> Data { Data(text.utf8) }
    func testSnapReachOutsideCardAndOutOfRangeCancellation() {
        let frames: [Provider: CGRect] = [.claude: CGRect(x: 0, y: 0, width: 220, height: 158)]
        XCTAssertEqual(CardSnapGeometry.target(at: CGPoint(x: 110, y: 218), excluding: .cursor, frames: frames),
                       CardSnapTarget(provider: .claude, placement: .below))
        XCTAssertEqual(CardSnapGeometry.target(at: CGPoint(x: -65, y: 79), excluding: .cursor, frames: frames),
                       CardSnapTarget(provider: .claude, placement: .before))
        XCTAssertNil(CardSnapGeometry.target(at: CGPoint(x: 110, y: 300), excluding: .cursor, frames: frames))
        XCTAssertNil(CardSnapGeometry.target(at: CGPoint(x: 110, y: 79), excluding: .claude, frames: frames))
    }
    func testSnapNearestEdgeAndNeighbor() {
        let frames: [Provider: CGRect] = [.claude: CGRect(x: 0, y: 0, width: 220, height: 158),
                                         .chatgpt: CGRect(x: 230, y: 0, width: 220, height: 158)]
        XCTAssertEqual(CardSnapGeometry.target(at: CGPoint(x: 440, y: 80), excluding: .cursor, frames: frames),
                       CardSnapTarget(provider: .chatgpt, placement: .after))
        XCTAssertEqual(CardSnapGeometry.target(at: CGPoint(x: 330, y: -40), excluding: .cursor, frames: frames),
                       CardSnapTarget(provider: .chatgpt, placement: .above))
    }
    func testCardSnapCreatesRowsAndJoinsRows() {
        let strip: [[Provider]] = [[.openai, .chatgpt, .claude, .cursor]]
        let second = CardArrangement.moving(.claude, relativeTo: .openai, placement: .below, in: strip)
        XCTAssertEqual(second, [[.openai, .chatgpt, .cursor], [.claude]])
        let grid = CardArrangement.moving(.cursor, relativeTo: .claude, placement: .after, in: second)
        XCTAssertEqual(grid, [[.openai, .chatgpt], [.claude, .cursor]])
        let vertical = CardArrangement.moving(.chatgpt, relativeTo: .openai, placement: .below, in: grid)
        XCTAssertEqual(vertical, [[.openai], [.chatgpt], [.claude, .cursor]])
        XCTAssertEqual(CardArrangement.moving(.cursor, relativeTo: .claude, placement: .below, in: vertical),
                       [[.openai], [.chatgpt], [.claude], [.cursor]])
    }
    func testCardSnapRemovesEmptyRowsAndPreservesProviders() {
        let rows: [[Provider]] = [[.openai], [.claude], [.chatgpt, .cursor]]
        XCTAssertEqual(CardArrangement.moving(.claude, relativeTo: .openai, placement: .above, in: rows),
                       [[.claude], [.openai], [.chatgpt, .cursor]])
        XCTAssertEqual(CardArrangement.moving(.claude, relativeTo: .claude, placement: .below, in: rows), rows)
        let restored = CardArrangement.normalized([[.cursor, .cursor], [], [.claude]], including: Provider.allCases)
        XCTAssertEqual(restored, [[.cursor], [.claude], [.openai, .chatgpt]])
    }
    func testChatGPTSelectsTightestWindowWithMatchingReset() throws {
        let end = now.addingTimeInterval(3600).timeIntervalSince1970
        let week = now.addingTimeInterval(86400).timeIntervalSince1970
        let reading = try UsageParser.chatgpt(data("{\"rate_limit\":{\"primary_window\":{\"used_percent\":12,\"reset_at\":\(end),\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":83,\"reset_at\":\(week),\"limit_window_seconds\":604800}}}"), now: now)
        XCTAssertEqual(reading.value, 17)
        XCTAssertEqual(reading.window, "Work/Codex weekly")
        XCTAssertEqual(reading.periodEnd, Date(timeIntervalSince1970: week))
        XCTAssertEqual(reading.provider, .chatgpt)
    }
    func testChatGPTMissingInvalidAndExpiredWindowsNeverInventAllowance() {
        for payload in [#"{}"#, #"{"rate_limit":{}}"#, #"{"rate_limit":{"primary_window":{"used_percent":true,"reset_at":2000000000}}}"#, #"{"rate_limit":{"primary_window":{"used_percent":0}}}"#, #"{"rate_limit":{"primary_window":{"used_percent":0,"reset_at":1}}}"#] {
            XCTAssertThrowsError(try UsageParser.chatgpt(data(payload), now: now))
        }
    }
    func testChatGPTExplicitZeroUsageAndExhaustion() throws {
        for used in [0,100,110] {
            let reading = try UsageParser.chatgpt(data("{\"rate_limit\":{\"primary_window\":{\"used_percent\":\(used),\"reset_at\":2000000000,\"limit_window_seconds\":18000}}}"), now: now)
            XCTAssertEqual(reading.value, Double(max(0,100-used)))
        }
    }
    func testClaudeSelectsLeastRemainingAndItsOwnReset() throws {
        let reading = try UsageParser.claude(data(#"{"five_hour":{"utilization":32,"resets_at":"2026-09-25T12:00:00Z"},"seven_day":{"utilization":87,"resets_at":"2026-09-28T10:00:00.000Z"}}"#), now: now)
        XCTAssertEqual(reading.value, 13)
        XCTAssertEqual(reading.window, "weekly")
        XCTAssertEqual(reading.periodEnd, UsageParser.date("2026-09-28T10:00:00Z"))
    }
    func testClaudeEnterpriseSpendAllowanceAndUTCReset() throws {
        let reading = try UsageParser.claude(data(#"{"five_hour":null,"seven_day":null,"extra_usage":{"is_enabled":true,"used_credits":17301,"monthly_limit":22000}}"#), now: now)
        XCTAssertEqual(reading.value!, 21.359090909, accuracy: 0.000001)
        XCTAssertEqual(reading.window, "monthly spend")
        XCTAssertEqual(reading.periodEnd, UsageParser.date("2026-10-01T00:00:00Z"))
        XCTAssertEqual(reading.periodStart, UsageParser.date("2026-09-01T00:00:00Z"))
    }
    func testClaudeSpendNeverInventsMissingOrDisabledLimit() {
        for extra in [#"{"used_credits":5}"#, #"{"used_credits":5,"monthly_limit":null}"#, #"{"used_credits":5,"monthly_limit":0}"#, #"{"used_credits":-1,"monthly_limit":100}"#, #"{"used_credits":true,"monthly_limit":100}"#, #"{"is_enabled":false,"used_credits":5,"monthly_limit":100}"#] {
            XCTAssertThrowsError(try UsageParser.claude(data("{\"extra_usage\":\(extra)}"), now: now))
        }
    }
    func testClaudeIncludedWindowTakesPrecedenceOverExtraSpend() throws {
        let reading = try UsageParser.claude(data(#"{"five_hour":{"utilization":30,"resets_at":"2026-09-25T12:00:00Z"},"extra_usage":{"used_credits":90,"monthly_limit":100}}"#), now: now)
        XCTAssertEqual(reading.value, 70)
        XCTAssertEqual(reading.window, "session")
    }
    func testMissingClaudeMetricsNeverBecomeFullAllowance() {
        XCTAssertThrowsError(try UsageParser.claude(data(#"{"five_hour":null,"seven_day":{}}"#), now: now))
    }
    func testExpiredWindowIgnoredAndOverageClamped() throws {
        let result = try UsageParser.remaining([UsageWindow(used: 200, reset: now.addingTimeInterval(-10), label: "old"), UsageWindow(used: 104, reset: now.addingTimeInterval(3600), label: "current")], provider: .claude, now: now)
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(result.window, "current")
    }
    func testCursorUsesMostConstrainedPoolNotAverage() throws {
        let reading = try UsageParser.cursor(data(#"{"billingCycleEnd":"2026-10-01T00:00:00Z","individualUsage":{"plan":{"autoPercentUsed":24,"apiPercentUsed":82,"totalPercentUsed":53}}}"#), now: now)
        XCTAssertEqual(reading.value, 18)
        XCTAssertEqual(reading.window, "other models")
    }
    func testCursorFractionalPercentIsNotMultipliedBy100() throws {
        let reading = try UsageParser.cursor(data(#"{"billingCycleEnd":"2026-10-01T00:00:00Z","individualUsage":{"plan":{"apiPercentUsed":0.36}}}"#), now: now)
        XCTAssertEqual(reading.value!, 99.64, accuracy: 0.001)
    }
    func testCursorWithoutIndividualLimitShowsPersonalBillingCost() throws {
        let reading = try UsageParser.cursor(data(#"{"billingCycleStart":"2026-09-01T00:00:00Z","billingCycleEnd":"2026-10-01T00:00:00Z","individualUsage":{"overall":{"used":13126,"limit":null},"onDemand":{"used":13129}},"teamUsage":{"onDemand":{"used":990000}}}"#), now: now)
        XCTAssertEqual(reading.kind, .cost)
        XCTAssertEqual(reading.value, 131.26)
        XCTAssertEqual(reading.periodEnd, UsageParser.date("2026-10-01T00:00:00Z"))
    }
    func testCursorPersonalOnDemandFallbackAndExplicitZero() throws {
        for cents in [0, 12345] {
            let payload = data("{\"billingCycleEnd\":\"2026-10-01T00:00:00Z\",\"individualUsage\":{\"onDemand\":{\"used\":\(cents)}}}")
            let result = try UsageParser.cursor(payload, now: now)
            XCTAssertEqual(result.kind, .cost)
            XCTAssertEqual(result.value, Double(cents) / 100)
        }
    }
    func testCursorDoesNotUseSharedTeamSpendOrExpiredCost() {
        for payload in [#"{"billingCycleEnd":"2026-10-01T00:00:00Z","individualUsage":{},"teamUsage":{"onDemand":{"used":990000}}}"#,
                        #"{"billingCycleEnd":"2026-09-01T00:00:00Z","individualUsage":{"onDemand":{"used":12345}}}"#] {
            XCTAssertThrowsError(try UsageParser.cursor(data(payload), now: now))
        }
    }
    func testCursorMissingOrZeroLimitNotAssumedUnused() {
        for payload in [#"{"billingCycleEnd":"2026-10-01T00:00:00Z","individualUsage":{"plan":{}}}"#, #"{"billingCycleEnd":"2026-10-01T00:00:00Z","individualUsage":{"plan":{"used":0,"limit":0}}}"#] {
            XCTAssertThrowsError(try UsageParser.cursor(data(payload), now: now))
        }
    }
    func testCostPagesValidatePaginationAndRetainCredits() throws {
        let page = try UsageParser.costs(data(#"{"data":[{"results":[{"amount":{"value":12.50,"currency":"usd"}},{"amount":{"value":-2,"currency":"usd"}}]}],"has_more":true,"next_page":"abc"}"#))
        XCTAssertEqual(page.amount, Decimal(string: "10.50"))
        XCTAssertEqual(page.next, "abc")
        XCTAssertEqual(page.currencies, ["USD"])
        XCTAssertThrowsError(try UsageParser.costs(data(#"{"data":[],"has_more":true}"#)))
        XCTAssertThrowsError(try UsageParser.costs(data(#"{"data":[{"results":[{"amount":{"currency":"usd"}}]}],"has_more":false}"#)))
    }
    func testCostDecimalsThatBreakFoundationJSONSerialization() throws {
        let tiny = "0." + String(repeating: "0", count: 140) + "1"
        let payload = data("{\"data\":[{\"results\":[{\"amount\":{\"value\":\(tiny),\"currency\":\"usd\"}},{\"amount\":{\"value\":24.80,\"currency\":\"usd\"}}]}],\"has_more\":false,\"next_page\":null}")
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: payload))
        let page = try UsageParser.costs(payload)
        XCTAssertEqual(NSDecimalNumber(decimal: page.amount).doubleValue, 24.80, accuracy: 0.000001)
        XCTAssertNil(page.next)
    }
    func testInvalidCostNumbersAreNotTreatedAsZero() {
        for value in ["null", "true", "\"NaN\"", "\"Infinity\""] {
            let payload = data("{\"data\":[{\"results\":[{\"amount\":{\"value\":\(value),\"currency\":\"usd\"}}]}],\"has_more\":false}")
            XCTAssertThrowsError(try UsageParser.costs(payload))
        }
    }
    func testBillingBoundaryClampsEndOfMonth() {
        let date = UsageParser.date("2026-03-01T00:00:00Z")!
        let interval = BillingPeriod.current(day: 31, now: date)
        XCTAssertEqual(interval.start, UsageParser.date("2026-02-28T00:00:00Z"))
        XCTAssertEqual(interval.end, UsageParser.date("2026-03-31T00:00:00Z"))
        let boundary = BillingPeriod.current(day: 1, now: date)
        XCTAssertEqual(boundary.start, date)
    }
    func testExpiredReadingCannotLookCurrent() {
        let reading = Reading(provider: .claude, value: 54, periodEnd: now, fetchedAt: now, state: .ready)
        XCTAssertEqual(reading.headline(at: now), "Updating…")
        XCTAssertFalse(reading.headline(at: now).contains("54"))
        XCTAssertTrue(reading.subtitle(at: now).contains("ended"))
    }
    func testManualRequiresCurrentPeriodAndIsLabeled() throws {
        var settings = ProviderSettings(provider: .chatgpt, mode: .manual)
        settings.manualSaved = true
        settings.manualValue = 200
        settings.manualStart = now.addingTimeInterval(-100)
        settings.manualEnd = now.addingTimeInterval(100)
        let reading = try UsageParser.manual(settings, now: now)
        XCTAssertTrue(reading.manual)
        XCTAssertTrue(reading.subtitle(at: now).contains("Entered"))
        settings.manualKind = .remaining
        XCTAssertThrowsError(try UsageParser.manual(settings, now: now))
        settings.manualValue = 50
        settings.manualEnd = now
        XCTAssertThrowsError(try UsageParser.manual(settings, now: now))
    }
    func testBooleansAreNotPercentagesAndStaleKeepsLastValue() {
        XCTAssertNil(UsageParser.number(true))
        let reading = Reading(provider: .cursor, value: 42, periodEnd: now.addingTimeInterval(86400), fetchedAt: now.addingTimeInterval(-901), state: .ready)
        XCTAssertEqual(reading.headline(at: now), "42%")
        XCTAssertTrue(reading.subtitle(at: now).contains("Last known"))
    }
}

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class CostClientTests: XCTestCase {
    func testNetworkErrorsAreActionableWithoutKeyOrResponseLeak() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await OpenAICostClient(session: session).fetch(key: "test-admin-key", organization: "", billingDay: 1)
            XCTFail("Should report timeout")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
            XCTAssertTrue(error.localizedDescription.contains("-1001"))
            XCTAssertFalse(error.localizedDescription.contains("test-admin-key"))
        }
        session.invalidateAndCancel()
    }
    func testFetchFollowsPagesAndDoesNotPublishPartialTotals() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let now = UsageParser.date("2026-09-25T10:00:00Z")!
        var requests = 0
        StubURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            if requests == 1 { return (200, Data(#"{"data":[{"results":[{"amount":{"value":10,"currency":"usd"}}]}],"has_more":true,"next_page":"page2"}"#.utf8)) }
            XCTAssertTrue(request.url!.absoluteString.contains("page=page2"))
            return (200, Data(#"{"data":[{"results":[{"amount":{"value":2.25,"currency":"usd"}}]}],"has_more":false}"#.utf8))
        }
        let reading = try await OpenAICostClient(session: session).fetch(key: "test-key", organization: "", billingDay: 1, now: now)
        XCTAssertEqual(reading.value, 12.25)
        XCTAssertEqual(requests, 2)
        StubURLProtocol.handler = { _ in (401, Data()) }
        do { _ = try await OpenAICostClient(session: session).fetch(key: "bad-key", organization: "", billingDay: 1, now: now); XCTFail("Must reject auth failures") }
        catch UsageError.openAIAuthentication(401) {} catch { XCTFail("Wrong error: \(error)") }
        session.invalidateAndCancel()
    }
    func testProjectKeyIsRejectedWithoutMakingARequest() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = { _ in XCTFail("Project key must not be sent to costs endpoint"); return (500, Data()) }
        do {
            _ = try await OpenAICostClient(session: session).fetch(key: "sk-proj-test-only", organization: "", billingDay: 1)
            XCTFail("Must require an admin key")
        } catch { XCTAssertTrue(error.localizedDescription.contains("project API key")) }
        session.invalidateAndCancel()
    }
    func testForbiddenHasActionableMessageWithoutEchoingServerSecrets() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = { _ in (403, Data(#"{"error":{"message":"secret-key-fragment"}}"#.utf8)) }
        do {
            _ = try await OpenAICostClient(session: session).fetch(key: "test-admin-key", organization: "", billingDay: 1)
            XCTFail("Must reject forbidden request")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("HTTP 403"))
            XCTAssertTrue(error.localizedDescription.contains("Admin API key"))
            XCTAssertFalse(error.localizedDescription.contains("secret-key-fragment"))
        }
        session.invalidateAndCancel()
    }
}
