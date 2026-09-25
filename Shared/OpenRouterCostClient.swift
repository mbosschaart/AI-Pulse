import Foundation

/// Account-wide Activity analytics; a Management key is required.
struct OpenRouterCostClient {
    let session: URLSession
    func fetch(key: String, now: Date = Date()) async throws -> Reading {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw UsageError.unavailable("Enter an OpenRouter Management API key.") }
        let period = BillingPeriod.current(day: 1, now: now)
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/analytics/query")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let formatter = ISO8601DateFormatter()
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "metrics": ["total_usage"], "limit": 1,
            "time_range": ["start": formatter.string(from: period.start), "end": formatter.string(from: now)]
        ])
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw UsageError.unavailable("Could not reach OpenRouter. Check your connection and try again.") }
        guard let response = response as? HTTPURLResponse else { throw UsageError.network }
        switch response.statusCode {
        case 200: break
        case 401: throw UsageError.unauthorized
        case 403: throw UsageError.unavailable("OpenRouter requires a Management API key with access to Activity analytics. A regular inference key cannot read account-wide spend.")
        case 429: throw UsageError.rateLimited
        default: throw UsageError.unavailable("OpenRouter returned HTTP \(response.statusCode). Try again later.")
        }
        return try Self.reading(from: data, now: now)
    }
    static func reading(from data: Data, now: Date) throws -> Reading {
        struct Row: Decodable { let total_usage: Double }
        struct Metadata: Decodable { let truncated: Bool; let row_count: Int }
        struct Result: Decodable { let data: [Row]; let metadata: Metadata }
        struct Envelope: Decodable { let data: Result }
        let result: Result
        do { result = try JSONDecoder().decode(Envelope.self, from: data).data }
        catch { throw UsageError.malformed }
        guard !result.metadata.truncated, result.data.count <= 1,
              result.metadata.row_count == result.data.count else {
            throw UsageError.unavailable("OpenRouter returned incomplete analytics. No partial total was used.")
        }
        let cost = result.data.first?.total_usage ?? 0
        guard cost.isFinite, cost >= 0 else { throw UsageError.malformed }
        let period = BillingPeriod.current(day: 1, now: now)
        return Reading(provider: .openrouter, kind: .cost, value: cost, currency: "USD",
                       periodStart: period.start, periodEnd: period.end, fetchedAt: now, state: .ready,
                       detail: "Account-wide Activity total spend for the current UTC month, including BYOK where reported. Organization keys include organization-wide spend. Analytics may arrive with a delay.")
    }
}
