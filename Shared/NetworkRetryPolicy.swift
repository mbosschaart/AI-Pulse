import Foundation

/// Only transport failures get short retries; authentication and rate limits keep their own policy.
enum NetworkRetryPolicy {
    static func isTransient(_ error: Error) -> Bool {
        if case UsageError.network = error { return true }
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed,
                NSURLErrorNotConnectedToInternet].contains(error.code)
    }
    static func delay(afterFailure count: Int) -> TimeInterval? {
        let delays: [TimeInterval] = [5, 15, 30]
        guard count > 0, count <= delays.count else { return nil }
        return delays[count - 1]
    }
}
