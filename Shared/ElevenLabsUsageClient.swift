import Foundation

/// Reads subscription allowance only; never performs billable generation requests.
struct ElevenLabsUsageClient {
    let session: URLSession

    func fetch(key: String, now: Date = Date()) async throws -> Reading {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw UsageError.unavailable("Enter an ElevenLabs API key.") }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!)
        request.timeoutInterval = 60
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UsageError.network }
        switch response.statusCode {
        case 200: break
        case 401: throw UsageError.unauthorized
        case 403: throw UsageError.unavailable("Allow subscription read access for this ElevenLabs API key, then check again.")
        case 429: throw UsageError.rateLimited
        default: throw UsageError.unavailable("ElevenLabs returned HTTP \(response.statusCode). Try again later.")
        }
        return try Self.reading(from: data, now: now)
    }

    static func reading(from data: Data, now: Date) throws -> Reading {
        struct Subscription: Decodable {
            let character_count: Double
            let character_limit: Double
            let next_character_count_reset_unix: Double?
        }
        let subscription: Subscription
        do { subscription = try JSONDecoder().decode(Subscription.self, from: data) }
        catch { throw UsageError.malformed }
        guard subscription.character_count.isFinite, subscription.character_count >= 0,
              subscription.character_limit.isFinite, subscription.character_limit > 0 else {
            throw UsageError.unavailable("ElevenLabs did not report a usable subscription allowance.")
        }
        var reset: Date?
        if let timestamp = subscription.next_character_count_reset_unix {
            guard timestamp.isFinite, timestamp > 0 else { throw UsageError.malformed }
            reset = Date(timeIntervalSince1970: timestamp)
        }
        let remaining = max(0, 1 - subscription.character_count / subscription.character_limit) * 100
        return Reading(provider: .elevenlabs, kind: .remaining, value: remaining,
                       periodEnd: reset, window: "included allowance", fetchedAt: now, state: .ready,
                       detail: "Remaining included subscription allowance reported by ElevenLabs for this API key. Usage beyond the allowance displays 0%; overage costs and invoice totals are not included. A missing reset date is not estimated.")
    }
}
