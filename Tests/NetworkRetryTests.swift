import XCTest
@testable import AIPulseCore

final class NetworkRetryTests: XCTestCase {
    func testOnlyTransportFailuresRetryQuickly() {
        for code in [URLError.timedOut, .cannotFindHost, .cannotConnectToHost,
                     .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet] {
            XCTAssertTrue(NetworkRetryPolicy.isTransient(URLError(code)))
        }
        XCTAssertTrue(NetworkRetryPolicy.isTransient(UsageError.network))
        for error: Error in [UsageError.unauthorized, UsageError.openAIAuthentication(401),
                            UsageError.rateLimited, UsageError.malformed,
                            UsageError.unavailable("HTTP 500"), URLError(.serverCertificateUntrusted),
                            URLError(.cancelled), NSError(domain: "Other", code: NSURLErrorTimedOut)] {
            XCTAssertFalse(NetworkRetryPolicy.isTransient(error))
        }
    }
    func testRecoveryIsBoundedWithinOneMinuteInsteadOfWaitingAnHour() {
        XCTAssertNil(NetworkRetryPolicy.delay(afterFailure: 0))
        XCTAssertEqual((1...3).compactMap(NetworkRetryPolicy.delay).reduce(0, +), 50)
        XCTAssertNil(NetworkRetryPolicy.delay(afterFailure: 4))
        XCTAssertNil(NetworkRetryPolicy.delay(afterFailure: Int.max))
    }
}
