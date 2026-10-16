import XCTest
@testable import AIPulseCore

final class ElevenLabsUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func reading(_ json: String) throws -> Reading {
        try ElevenLabsUsageClient.reading(from: Data(json.utf8), now: now)
    }
    func testAllowanceAndReportedReset() throws {
        let r = try reading(#"{"character_count":2500,"character_limit":10000,"next_character_count_reset_unix":1800100000}"#)
        XCTAssertEqual(r.provider, .elevenlabs)
        XCTAssertEqual(r.value, 75)
        XCTAssertEqual(r.kind, .remaining)
        XCTAssertEqual(r.periodEnd, Date(timeIntervalSince1970: 1_800_100_000))
        XCTAssertEqual(r.connectionHealth(at: now), .current)
        XCTAssertTrue(Provider.elevenlabs.usesAPIKey)
        XCTAssertEqual(Provider.elevenlabs.defaultMetricKind, .remaining)
    }
    func testOverageCannotBecomeNegativeAllowance() throws {
        XCTAssertEqual(try reading(#"{"character_count":12000,"character_limit":10000}"#).value, 0)
        XCTAssertEqual(try reading(#"{"character_count":0,"character_limit":10000}"#).value, 100)
    }
    func testMissingResetNotInventedAndOldResetExpires() throws {
        XCTAssertNil(try reading(#"{"character_count":1,"character_limit":10,"next_character_count_reset_unix":null}"#).periodEnd)
        XCTAssertTrue(try reading(#"{"character_count":1,"character_limit":10,"next_character_count_reset_unix":1799999999}"#).isExpired(at: now))
    }
    func testInvalidAllowanceDoesNotProduceFakePercentage() {
        for json in [#"{}"#, #"{"character_count":-1,"character_limit":100}"#, #"{"character_count":0,"character_limit":0}"#, #"{"character_count":0,"character_limit":-1}"#, #"{"character_count":1,"character_limit":10,"next_character_count_reset_unix":-1}"#] {
            XCTAssertThrowsError(try reading(json))
        }
    }
    func testSixProvidersCanBeSelectedAndOrdered() {
        let all = WidgetPresentation.samples(at: now)
        XCTAssertEqual(all.count, 6)
        XCTAssertEqual(WidgetPresentation.configuredReadings(all, selection: Provider.allCases, followAppOrder: true).count, 6)
        XCTAssertEqual(WidgetPresentation.configuredReadings(all, selection: [.elevenlabs, .openai], followAppOrder: false).map(\.provider), [.elevenlabs, .openai])
    }
    func testRequestAuthenticationAndErrorsDoNotLeakResponse() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/user/subscription")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-key")
            return (200, Data(#"{"character_count":25,"character_limit":100}"#.utf8))
        }
        let result = try await ElevenLabsUsageClient(session: session).fetch(key: " test-key ", now: now)
        XCTAssertEqual(result.value, 75)
        for status in [401, 403, 429, 500] {
            StubURLProtocol.handler = { _ in (status, Data("private-response-marker".utf8)) }
            do {
                _ = try await ElevenLabsUsageClient(session: session).fetch(key: "test-key", now: now)
                XCTFail("Expected HTTP failure")
            } catch {
                XCTAssertFalse(error.localizedDescription.contains("private-response-marker"))
                if status == 401 { guard case UsageError.unauthorized = error else { return XCTFail("Expected authentication error") } }
                if status == 429 { guard case UsageError.rateLimited = error else { return XCTFail("Expected rate limit") } }
            }
        }
        StubURLProtocol.handler = { _ in XCTFail("Empty key should not be sent"); return (500, Data()) }
        do { _ = try await ElevenLabsUsageClient(session: session).fetch(key: "  "); XCTFail("Expected missing-key error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("API key")) }
    }

}
