import Foundation

struct OpenAICostClient {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func fetch(key: String, organization: String, billingDay: Int, now: Date = Date()) async throws -> Reading {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let organization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw UsageError.unavailable("Enter an organization Admin API key to connect OpenAI.") }
        if key.hasPrefix("sk-proj-") || key.hasPrefix("sk-svcacct-") {
            throw UsageError.unavailable("The saved key is a project API key. Organization billing costs require an Admin API key from OpenAI Platform → Settings → Organization → Admin keys. Replace the key here and check again.")
        }
        let period = BillingPeriod.current(day: billingDay, now: now)
        var page: String?
        var seen = Set<String>()
        var amount: Decimal = 0
        var currencies = Set<String>()
        repeat {
            var url = URLComponents(string: "https://api.openai.com/v1/organization/costs")!
            url.queryItems = [URLQueryItem(name: "start_time", value: String(Int(period.start.timeIntervalSince1970))),
                             URLQueryItem(name: "end_time", value: String(Int(now.timeIntervalSince1970))),
                             URLQueryItem(name: "bucket_width", value: "1d"), URLQueryItem(name: "limit", value: "31")]
            if let page { url.queryItems!.append(URLQueryItem(name: "page", value: page)) }
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 90
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if !organization.isEmpty { request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization") }
            let data: Data
            let response: URLResponse
            do { (data, response) = try await session.data(for: request) }
            catch let error as URLError {
                let explanation: String
                switch error.code {
                case .timedOut: explanation = "The cost request timed out. Try again."
                case .notConnectedToInternet: explanation = "The Mac appears to be offline."
                case .cannotFindHost, .dnsLookupFailed: explanation = "The Mac could not resolve api.openai.com. Check DNS or your VPN."
                case .cannotConnectToHost: explanation = "The Mac could not connect to api.openai.com. Check your connection or proxy."
                case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate: explanation = "The secure connection to OpenAI failed. Check the Mac’s date and network certificate settings."
                default: explanation = "The network request failed."
                }
                throw UsageError.unavailable("\(explanation) Network error \(error.code.rawValue).")
            }
            guard let response = response as? HTTPURLResponse else { throw UsageError.network }
            switch response.statusCode {
            case 200: break
            case 401, 403: throw UsageError.openAIAuthentication(response.statusCode)
            case 429: throw UsageError.rateLimited
            default: throw UsageError.unavailable("OpenAI returned HTTP \(response.statusCode). Try again later.")
            }
            let parsed: UsageParser.CostPage
            do { parsed = try UsageParser.costs(data) }
            catch {
                let type = response.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                throw UsageError.unavailable("OpenAI returned HTTP 200 but an unsupported cost response (\(type), \(data.count) bytes). Shape: \(Self.responseShape(data)).")
            }
            amount += parsed.amount
            currencies.formUnion(parsed.currencies)
            page = parsed.next
            if let page, !seen.insert(page).inserted || seen.count > 100 { throw UsageError.malformed }
        } while page != nil
        guard currencies.count <= 1 else { throw UsageError.unavailable("The response contains multiple currencies; they cannot be added together.") }
        return Reading(provider: .openai, kind: .cost, value: NSDecimalNumber(decimal: amount).doubleValue,
                       currency: currencies.first ?? "USD", periodStart: period.start, periodEnd: period.end,
                       fetchedAt: now, state: .ready, detail: "Provider-reported cost. Billing boundaries use UTC. Costs can arrive with a delay.")
    }
    // Structural diagnostics only: no string values, amounts, IDs, or credentials.
    static func responseShape(_ data: Data) -> String {
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data) }
        catch {
            if data.starts(with: [0x1f, 0x8b]) { return "gzip bytes" }
            let e = error as NSError
            let reason = (e.userInfo[NSDebugDescriptionErrorKey] as? String ?? "invalid JSON")
                .replacingOccurrences(of: #"[0-9]+(?:[.eE+\-][0-9]+)*"#, with: "#", options: .regularExpression)
            return "JSON error \(e.code): \(reason.prefix(240)); UTF8=\(String(data: data, encoding: .utf8) != nil)"
        }
        func shape(_ value: Any, depth: Int) -> String {
            if value is NSNull { return "null" }
            if let object = value as? [String: Any] {
                guard depth < 5 else { return "object" }
                let allowed: Set<String> = ["data", "results", "amount", "value", "currency", "has_more", "next_page", "object", "start_time", "end_time", "error", "message", "code"]
                return "{" + object.keys.sorted().prefix(12).map { key in
                    (allowed.contains(key) ? key : "other") + ":" + shape(object[key]!, depth: depth + 1)
                }.joined(separator: ",") + "}"
            }
            if let values = value as? [Any] { return "[" + values.prefix(2).map { shape($0, depth: depth + 1) }.joined(separator: ",") + "]" }
            if value is String { return "string" }
            if let number = value as? NSNumber { return UsageParser.number(number) == nil ? "bool" : "number" }
            return "unknown"
        }
        return shape(json, depth: 0)
    }
}
