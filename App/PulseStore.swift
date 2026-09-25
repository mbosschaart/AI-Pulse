import AppKit
import Combine
import WidgetKit
import ServiceManagement

@MainActor final class PulseStore: ObservableObject {
    @Published var readings: [Reading]
    @Published var configurations: [ProviderSettings]
    @Published private var hiddenProviders = Set<String>()
    @Published private var providerOrder = Provider.allCases
    var visibleReadings: [Reading] { providerOrder.filter { isEnabled($0) }.map { reading($0) } }
    @Published private(set) var cardRows: [[Provider]] = []
    var orderedProviders: [Provider] { providerOrder }
    func arrangeProvider(_ source: Provider, relativeTo target: Provider, placement: CardPlacement, startingRows: [[Provider]]) {
        guard !demo, isEnabled(source), isEnabled(target) else { return }
        let rows = CardArrangement.normalized(startingRows, including: providerOrder)
        cardRows = CardArrangement.moving(source, relativeTo: target, placement: placement, in: rows)
        providerOrder = Array(cardRows.joined())
        defaults.set(cardRows.map { $0.map(\.rawValue) }, forKey: "provider-rows")
        defaults.set(providerOrder.map(\.rawValue), forKey: "provider-order")
        syncWidget()
    }
    func moveProvider(_ source: Provider, to target: Provider) {
        guard !demo, source != target,
              let old = providerOrder.firstIndex(of: source),
              let destination = providerOrder.firstIndex(of: target) else { return }
        providerOrder.remove(at: old)
        providerOrder.insert(source, at: destination)
        defaults.set(providerOrder.map(\.rawValue), forKey: "provider-order")
        syncWidget()
    }
    func isEnabled(_ provider: Provider) -> Bool { !hiddenProviders.contains(provider.rawValue) }
    func setEnabled(_ enabled: Bool, for provider: Provider) {
        guard !demo else { return }
        if enabled { hiddenProviders.remove(provider.rawValue) } else { hiddenProviders.insert(provider.rawValue) }
        defaults.set(Array(hiddenProviders), forKey: "hidden-providers")
        syncWidget()
    }
    @Published var busy = Set<Provider>()
    @Published var selected: Provider = .openai
    @Published var settingsProvider: Provider? = nil
    @Published var showConnections = false
    func openSettings(provider: Provider? = nil) {
        if let provider { selected = provider }
        settingsProvider = provider
        showConnections = true
    }
    @Published var error: String?
    @Published var organizations: [(id: String, name: String)] = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var refreshInterval: UsageRefreshInterval = .hourly
    private var usageTimer: Timer?
    private var lastAutomaticRefresh: Date?
    private var sessions: [Provider: BrowserSession] = [:]
    private var timers = Set<AnyCancellable>()
    private var retryAfter: [Provider: Date] = [:]
    private var failures: [Provider: Int] = [:]
    private var generation: [Provider: Int] = [:]
    private let defaults = UserDefaults.standard
    let demo: Bool

    init() {
        let emptyDemo = ProcessInfo.processInfo.arguments.contains("--demo-empty")
        demo = emptyDemo || ProcessInfo.processInfo.arguments.contains("--demo")
        configurations = (UserDefaults.standard.data(forKey: "accounts-v1").flatMap { try? JSONDecoder().decode([ProviderSettings].self, from: $0) }) ?? Provider.allCases.map { ProviderSettings(provider: $0, mode: .automatic) }
        readings = UserDefaults.standard.data(forKey: "readings-v1").flatMap { try? JSONDecoder().decode([Reading].self, from: $0) } ?? Reading.empty
        for provider in Provider.allCases where !readings.contains(where: { $0.provider == provider }) {
            readings.append(Reading(provider: provider, kind: provider.defaultMetricKind))
        }
        for index in configurations.indices where configurations[index].provider == .chatgpt && !configurations[index].manualSaved && !configurations[index].connected {
            configurations[index].mode = .automatic
        }
        refreshInterval = UsageRefreshInterval.saved(defaults.integer(forKey: "usage-refresh-interval"))
        lastAutomaticRefresh = defaults.object(forKey: "last-automatic-usage-refresh") as? Date
        if demo {
            readings = emptyDemo ? Reading.empty : Self.demoReadings
            if emptyDemo { configurations = Provider.allCases.map { ProviderSettings(provider: $0) } }
            return
        }
        applyFreshnessWindow()
        let savedOrder = (defaults.stringArray(forKey: "provider-order") ?? []).compactMap(Provider.init(rawValue:))
        providerOrder = (savedOrder + Provider.allCases).reduce(into: []) { order, provider in
            if !order.contains(provider) { order.append(provider) }
        }
        let savedRows = (defaults.array(forKey: "provider-rows") as? [[String]] ?? []).map { $0.compactMap(Provider.init(rawValue:)) }
        if !savedRows.isEmpty { cardRows = CardArrangement.normalized(savedRows, including: providerOrder) }
        hiddenProviders = Set(defaults.stringArray(forKey: "hidden-providers") ?? [])
        syncWidget()
        scheduleUsageRefresh()
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            Task { @MainActor in await self?.refreshAutomaticallyIfDue() }
        }.store(in: &timers)
    }
    func setRefreshInterval(_ interval: UsageRefreshInterval) {
        guard !demo, interval != refreshInterval else { return }
        refreshInterval = interval
        defaults.set(interval.rawValue, forKey: "usage-refresh-interval")
        applyFreshnessWindow()
        syncWidget()
        scheduleUsageRefresh()
    }
    private func applyFreshnessWindow() {
        for index in readings.indices { readings[index].staleAfterSeconds = refreshInterval.freshnessWindow }
        if let data = try? JSONEncoder().encode(readings) { defaults.set(data, forKey: "readings-v1") }
    }
    private func scheduleUsageRefresh() {
        usageTimer?.invalidate()
        guard !demo else { return }
        let date = refreshInterval.nextCheck(after: lastAutomaticRefresh, now: Date())
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refreshAutomaticallyIfDue() }
        }
        usageTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func refreshAutomaticallyIfDue() async {
        let now = Date()
        guard refreshInterval.isDue(after: lastAutomaticRefresh, now: now) else {
            scheduleUsageRefresh()
            return
        }
        lastAutomaticRefresh = now
        defaults.set(now, forKey: "last-automatic-usage-refresh")
        scheduleUsageRefresh()
        await refreshAll()
    }
    func settings(_ provider: Provider) -> ProviderSettings { configurations.first { $0.provider == provider } ?? ProviderSettings(provider: provider) }
    func reading(_ provider: Provider) -> Reading { readings.first { $0.provider == provider } ?? Reading(provider: provider) }
    func configure(_ value: ProviderSettings) {
        guard !demo else { return }
        let previous = settings(value.provider)
        generation[value.provider, default: 0] += 1
        if let index = configurations.firstIndex(where: { $0.provider == value.provider }) { configurations[index] = value }
        else { configurations.append(value) }
        if let data = try? JSONEncoder().encode(configurations) { defaults.set(data, forKey: "accounts-v1") }
        retryAfter[value.provider] = nil
        if previous.mode != value.mode || previous.organizationID != value.organizationID || previous.billingDay != value.billingDay {
            publish(Reading(provider: value.provider, kind: value.provider.defaultMetricKind,
                            state: .unavailable, detail: "Account settings changed. Check the connection to load a new reading."))
        }
    }
    func invalidate(_ provider: Provider) {
        generation[provider, default: 0] += 1
        publish(Reading(provider: provider, kind: provider.defaultMetricKind,
                        state: .unavailable, detail: "Check the connection after signing in or changing credentials."))
    }
    private func publish(_ reading: Reading) {
        guard !demo else { return }
        var reading = reading
        reading.staleAfterSeconds = refreshInterval.freshnessWindow
        if let index = readings.firstIndex(where: { $0.provider == reading.provider }) { readings[index] = reading }
        if let data = try? JSONEncoder().encode(readings) { defaults.set(data, forKey: "readings-v1") }
        syncWidget()
    }
    private func syncWidget() {
        do {
            try SnapshotStore.write(visibleReadings)
            guard SnapshotStore.read() == visibleReadings else { throw UsageError.unavailable("The widget snapshot could not be read back.") }
            WidgetCenter.shared.reloadAllTimelines()
        }
        catch { self.error = "Widget sync: \(error.localizedDescription)" }
    }
    func browser(_ provider: Provider) -> BrowserSession {
        if let session = sessions[provider] { return session }
        let session = BrowserSession(provider: provider)
        sessions[provider] = session
        return session
    }
    func signIn(_ provider: Provider) { invalidate(provider); browser(provider).show() }
    func refreshAll(force: Bool = false) async {
        guard !demo else { return }
        await withTaskGroup(of: Void.self) { group in
            for provider in Provider.allCases where isEnabled(provider) { group.addTask { await self.refresh(provider, force: force) } }
        }
    }
    func refresh(_ provider: Provider, force: Bool = true) async {
        guard !demo, !busy.contains(provider) else { return }
        guard sessions[provider]?.isSigningIn != true else { return }
        let config = settings(provider)
        guard force || retryAfter[provider].map({ $0 <= Date() }) ?? true else { return }
        guard config.connected || config.mode == .manual || force else { return }
        let version = generation[provider, default: 0]
        busy.insert(provider)
        defer { busy.remove(provider) }
        do {
            var result: Reading
            if config.mode == .manual {
                guard config.manualSaved else { return }
                result = try UsageParser.manual(config)
            } else {
                switch provider {
                case .openai:
                    guard let key = try Credentials.read("openai-key"), !key.isEmpty else { throw UsageError.unavailable("Add an OpenAI organization Admin API key in Connections.") }
                    result = try await OpenAICostClient(session: SameHostRedirects.session).fetch(key: key, organization: config.organizationID, billingDay: config.billingDay)
                case .openrouter:
                    guard let key = try Credentials.read(provider.credentialAccount), !key.isEmpty else {
                        throw UsageError.unavailable("Add an OpenRouter Management API key in Settings.")
                    }
                    result = try await OpenRouterCostClient(session: SameHostRedirects.session).fetch(key: key)
                case .claude:
                    var id = config.organizationID
                    if id.isEmpty {
                        let data = try await browser(.claude).json(path: "/api/organizations")
                        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw UsageError.malformed }
                        organizations = list.compactMap { org in
                            guard let id = org["uuid"] as? String else { return nil }
                            return (id, org["name"] as? String ?? id)
                        }
                        guard organizations.count == 1 else { throw UsageError.unavailable("Select your Claude organization in Connections, then check again.") }
                        id = organizations[0].id
                    }
                    guard UUID(uuidString: id) != nil else { throw UsageError.unavailable("Select a valid Claude organization.") }
                    let data = try await browser(.claude).json(path: "/api/organizations/\(id)/usage")
                    result = try UsageParser.claude(data)
                case .cursor:
                    result = try UsageParser.cursor(await browser(.cursor).json(path: "/api/usage-summary"))
                case .chatgpt:
                    result = try UsageParser.chatgpt(await browser(.chatgpt).json(path: "/backend-api/wham/usage"))
                }
            }
            guard generation[provider, default: 0] == version else { return }
            var saved = config
            saved.connected = true
            configure(saved)
            result.state = .ready
            failures[provider] = 0
            retryAfter[provider] = nil
            publish(result)
        } catch {
            guard generation[provider, default: 0] == version else { return }
            var last = reading(provider)
            last.state = .failed
            if case UsageError.unauthorized = error { last.state = .reconnect }
            if case UsageError.openAIAuthentication = error { last.state = .reconnect }
            if case UsageError.unavailable = error { last.state = .unavailable }
            if error is UsageError { last.detail = error.localizedDescription }
            else if provider.usesAPIKey { last.detail = "\(provider.name) could not complete the cost request (error \((error as NSError).code)). Try again." }
            else { last.detail = "Could not read the provider dashboard. Open its sign-in window and try again." }
            failures[provider, default: 0] += 1
            var delay = min(3600.0, 300 * pow(2, Double(failures[provider, default: 1] - 1)))
            if case UsageError.rateLimited = error { delay = max(delay, 900) }
            retryAfter[provider] = Date().addingTimeInterval(delay)
            publish(last)
        }
    }
    func saveManual(_ config: ProviderSettings) throws {
        let result = try UsageParser.manual(config)
        configure(config)
        publish(result)
    }
    func disconnect(_ provider: Provider) async {
        generation[provider, default: 0] += 1
        do {
            if provider.usesAPIKey { try Credentials.remove(provider.credentialAccount) }
            if !provider.usesAPIKey { await browser(provider).clear() }
            configure(ProviderSettings(provider: provider, mode: .automatic))
            publish(Reading(provider: provider, kind: provider.defaultMetricKind))
        } catch { self.error = error.localizedDescription }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch { self.error = error.localizedDescription }
    }
    static var demoReadings: [Reading] {
        let now = Date()
        return [Reading(provider: .openai, kind: .cost, value: 24.80, periodEnd: now.addingTimeInterval(86400 * 6), fetchedAt: now, state: .ready),
                Reading(provider: .chatgpt, kind: .cost, value: 200, periodEnd: now.addingTimeInterval(86400 * 17), fetchedAt: now, state: .ready, manual: true),
                Reading(provider: .claude, value: 32, periodEnd: now.addingTimeInterval(8040), window: "session", fetchedAt: now, state: .ready),
                Reading(provider: .cursor, value: 18, periodEnd: now.addingTimeInterval(86400 * 9), window: "other models", fetchedAt: now, state: .ready)]
    }
}
