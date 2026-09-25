import Foundation

enum UsageParser {
    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: string) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    static func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let n = value as? NSNumber {
            guard CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        if let s = value as? String, let n = Double(s), n.isFinite { return n }
        return nil
    }
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw UsageError.malformed }
        return object
    }
    static func remaining(_ windows: [UsageWindow], provider: Provider, now: Date) throws -> Reading {
        let valid = windows.filter { $0.used.isFinite && $0.used >= 0 && $0.reset > now }
        guard let tightest = valid.max(by: { $0.used < $1.used }) else {
            throw UsageError.unavailable("No current allowance with a reset date was returned by this account.")
        }
        return Reading(provider: provider, value: max(0, 100 - tightest.used), periodEnd: tightest.reset,
                       window: tightest.label, fetchedAt: now, state: .ready, detail: "Lowest remaining allowance reported by the provider.")
    }
    static func claude(_ data: Data, now: Date = Date()) throws -> Reading {
        let json = try object(data)
        let fields = [("five_hour", "session"), ("seven_day", "weekly"), ("seven_day_sonnet", "Sonnet weekly"), ("seven_day_opus", "Opus weekly")]
        let windows = fields.compactMap { key, label -> UsageWindow? in
            guard let value = json[key] as? [String: Any], let used = number(value["utilization"]), let reset = date(value["resets_at"]) else { return nil }
            return UsageWindow(used: used, reset: reset, label: label)
        }
        if windows.isEmpty,
           let extra = json["extra_usage"] as? [String: Any],
           extra["is_enabled"] as? Bool != false,
           let used = number(extra["used_credits"]), used >= 0,
           let limit = number(extra["monthly_limit"]), limit > 0 {
            // Enterprise spend caps reset on the first day of each month at 00:00 UTC.
            // Both fields use the same monetary unit, so no currency conversion is needed.
            let period = BillingPeriod.current(day: 1, now: now)
            var result = try remaining([UsageWindow(used: used / limit * 100,
                                                    reset: period.end, label: "monthly spend")],
                                       provider: .claude, now: now)
            result.periodStart = period.start
            result.spendLimit = limit / 100
            result.currency = (extra["currency"] as? String)?.uppercased() ?? "USD"
            result.detail = "Remaining monthly spend allowance for the selected Claude organization. Resets on the first of the month at 00:00 UTC."
            return result
        }
        return try remaining(windows, provider: .claude, now: now)
    }
    static func chatgpt(_ data: Data, now: Date = Date()) throws -> Reading {
        let json = try object(data)
        guard let limits = json["rate_limit"] as? [String: Any] else {
            throw UsageError.unavailable("This account did not report a ChatGPT Work/Codex allowance. Open the usage dashboard to check the selected account, or enter your subscription cost manually.")
        }
        let windows = ["primary_window", "secondary_window"].compactMap { key -> UsageWindow? in
            guard let window = limits[key] as? [String: Any],
                  let used = number(window["used_percent"]), used >= 0,
                  let epoch = number(window["reset_at"]), epoch > 0, epoch < 253402300800 else { return nil }
            let seconds = number(window["limit_window_seconds"])
            let label = seconds == 604800 ? "Work/Codex weekly" : seconds == 18000 ? "Work/Codex 5h" : "Work/Codex"
            return UsageWindow(used: used, reset: Date(timeIntervalSince1970: epoch), label: label)
        }
        var result = try remaining(windows, provider: .chatgpt, now: now)
        result.detail = "Lowest remaining shared ChatGPT Work/Codex allowance and its reset date. Other ChatGPT features may have separate limits."
        return result
    }
    static func cursor(_ data: Data, now: Date = Date()) throws -> Reading {
        let json = try object(data)
        guard let end = date(json["billingCycleEnd"]), let individual = json["individualUsage"] as? [String: Any] else { throw UsageError.malformed }
        let plan = individual["plan"] as? [String: Any] ?? [:]
        var windows: [UsageWindow] = []
        for (key, label) in [("autoPercentUsed", "Cursor models"), ("apiPercentUsed", "other models")] {
            if let used = number(plan[key]) { windows.append(UsageWindow(used: used, reset: end, label: label)) }
        }
        if windows.isEmpty, let total = number(plan["totalPercentUsed"]) {
            windows.append(UsageWindow(used: total, reset: end, label: "monthly"))
        }
        if windows.isEmpty {
            let scope = individual["overall"] as? [String: Any] ?? plan
            if let used = number(scope["used"]), let limit = number(scope["limit"]), used >= 0, limit > 0 {
                windows.append(UsageWindow(used: used / limit * 100, reset: end, label: "monthly"))
            }
        }
        if windows.isEmpty, end > now {
            // Team accounts may have metered usage without an individual allowance.
            // These are individual cents, never the team's shared spend or plan credits.
            let overall = individual["overall"] as? [String: Any]
            let onDemand = individual["onDemand"] as? [String: Any]
            if let cents = number(overall?["used"]) ?? number(onDemand?["used"]), cents >= 0 {
                return Reading(provider: .cursor, kind: .cost, value: cents / 100,
                               currency: "USD", periodStart: date(json["billingCycleStart"]), periodEnd: end,
                               fetchedAt: now, state: .ready,
                               detail: "Cursor reports personal usage cost without a finite individual allowance. Showing billing-period usage cost; fixed subscription fees are not included.")
            }
        }
        var result = try remaining(windows, provider: .cursor, now: now)
        result.periodStart = date(json["billingCycleStart"])
        return result
    }
    struct CostPage {
        var amount: Decimal
        var currencies: Set<String>
        var next: String?
    }
    private struct CostResponse: Decodable {
        let data: [Bucket]
        let has_more: Bool
        let next_page: String?
        struct Bucket: Decodable { let results: [Result] }
        struct Result: Decodable { let amount: Amount }
        struct Amount: Decodable {
            let value: Double
            let currency: String
            enum CodingKeys: String, CodingKey { case value, currency }
            init(from decoder: Decoder) throws {
                let fields = try decoder.container(keyedBy: CodingKeys.self)
                currency = try fields.decode(String.self, forKey: .currency)
                if let number = try? fields.decode(Double.self, forKey: .value) { value = number }
                else {
                    let text = try fields.decode(String.self, forKey: .value)
                    guard let number = Double(text) else { throw UsageError.malformed }
                    value = number
                }
            }
        }
    }
    static func costs(_ data: Data) throws -> CostPage {
        // JSONSerialization constructs NSDecimalNumber for long decimal tokens and can
        // fail with "Number wound up as NaN". Decode numeric costs directly as Double.
        guard let response = try? JSONDecoder().decode(CostResponse.self, from: data) else { throw UsageError.malformed }
        var amount: Decimal = 0
        var currencies = Set<String>()
        for bucket in response.data {
            for result in bucket.results {
                let raw = result.amount.value
                let currency = result.amount.currency
                guard raw.isFinite, currency.count == 3 else { throw UsageError.malformed }
                // Sub-1e-100 amounts cannot affect a billed cent and underflow Decimal.
                // Preserve normal sub-cent amounts and negative billing adjustments.
                let value = abs(raw) < 1e-100 ? Decimal.zero : Decimal(raw)
                guard !value.isNaN else { throw UsageError.malformed }
                amount += value
                currencies.insert(currency.uppercased())
            }
        }
        let next = response.next_page
        if response.has_more && (next == nil || next!.isEmpty) { throw UsageError.malformed }
        return CostPage(amount: amount, currencies: currencies, next: response.has_more ? next : nil)
    }
    static func manual(_ settings: ProviderSettings, now: Date = Date()) throws -> Reading {
        guard settings.manualSaved, settings.manualValue.isFinite, settings.manualValue >= 0,
              settings.manualStart <= now, settings.manualEnd > now, settings.manualEnd > settings.manualStart,
              settings.manualKind != .remaining || settings.manualValue <= 100,
              settings.currency.count == 3 else { throw UsageError.unavailable("Enter a value and a current billing or usage period.") }
        return Reading(provider: settings.provider, kind: settings.manualKind, value: settings.manualValue,
                       currency: settings.currency.uppercased(), periodStart: settings.manualStart,
                       periodEnd: settings.manualEnd, fetchedAt: now, state: .ready,
                       detail: "Manually entered. This value does not update automatically.", manual: true)
    }
}

import CoreFoundation
