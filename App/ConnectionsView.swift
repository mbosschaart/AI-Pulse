import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject var store: PulseStore
    @State private var config = ProviderSettings(provider: .openai)
    @State private var key = ""
    @State private var amount = ""
    @State private var feedback: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ProviderLogo(provider: store.selected, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.selected.name).font(.headline)
                    if let updated = store.reading(store.selected).fetchedAt {
                        Text("Last updated: \(updated.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Last updated: Never").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(store.reading(store.selected).detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Show \(store.selected.name)", isOn: Binding(
                get: { store.isEnabled(store.selected) },
                set: { store.setEnabled($0, for: store.selected) }
            )).toggleStyle(.switch)
            Text("When off, this provider is hidden and automatic checks pause. Your sign-in stays saved.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Data source", selection: $config.mode) {
                Text("Automatic").tag(ConnectionMode.automatic)
                Text("Manual entry").tag(ConnectionMode.manual)
            }.pickerStyle(.segmented)
            if config.mode == .manual { manualFields }
            else { automaticFields }
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if config.mode == .manual {
                    Button("Save value") { saveManual() }.buttonStyle(.borderedProminent)
                } else {
                    Button(store.busy.contains(store.selected) ? "Checking…" : "Check connection") {
                        saveAndCheck()
                    }.buttonStyle(.borderedProminent).disabled(store.busy.contains(store.selected))
                }
                Link("Open provider", destination: store.selected.website)
                Spacer()
                Button("Disconnect", role: .destructive) {
                    let provider = store.selected
                    Task { await store.disconnect(provider); load() }
                }.disabled(store.busy.contains(store.selected))
            }

        }
        .disabled(store.demo)
        .onAppear { load() }
        .onChange(of: store.selected) { _, _ in load() }
    }
    @ViewBuilder var automaticFields: some View {
        if store.selected == .openai {
            Text("Use an organization Admin API key, not a project API key. It stays in this Mac’s Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Open OpenAI Admin keys", destination: URL(string: "https://platform.openai.com/settings/organization/admin-keys")!)
            SecureField("Admin API key · leave blank to keep saved key", text: $key).textFieldStyle(.roundedBorder)
            TextField("Organization ID (optional)", text: $config.organizationID).textFieldStyle(.roundedBorder)
            HStack {
                Text("Billing cycle starts on day").font(.caption)
                Picker("Billing day", selection: $config.billingDay) { ForEach(1...31, id: \.self) { Text(String($0)).tag($0) } }.frame(width: 85)
                Text("UTC · defaults to calendar month").font(.caption).foregroundStyle(.secondary)
            }
        } else if store.selected == .openrouter {
            Text("Use a Management API key to read account-wide Activity spend for the current UTC month. For organization accounts this includes the whole organization. The key stays in this Mac’s Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Open OpenRouter Management keys", destination: URL(string: "https://openrouter.ai/settings/management-keys")!)
            SecureField("Management API key · leave blank to keep saved key", text: $key).textFieldStyle(.roundedBorder)
            Text("Shows Activity total spend, including BYOK where reported. Credit purchases and remaining prepaid balance are not monthly spend. Use a personal-account key to track only your own account.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Sign in directly on the provider’s website. Close the sign-in window, then check the connection. Your session stays in this app’s private WebKit storage on this Mac.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Sign in to \(store.selected.name)") { store.signIn(store.selected) }
            if store.selected == .claude {
                if !store.organizations.isEmpty {
                    Picker("Organization", selection: $config.organizationID) {
                        Text("Select organization").tag("")
                        ForEach(store.organizations, id: \.id) { org in Text(org.name).tag(org.id) }
                    }
                } else { TextField("Organization UUID (optional for a single account)", text: $config.organizationID).textFieldStyle(.roundedBorder) }
            }
            Text(store.selected == .chatgpt
                 ? "Tracks your shared ChatGPT Work/Codex allowance. Shows the lowest remaining usage window and its reset date; this is not an overall quota for every ChatGPT feature."
                 : store.selected == .cursor
                 ? "Shows your remaining allowance, or personal billing-period usage cost when no individual allowance is set. Team-wide spending is never substituted for your own."
                 : "Tracks the lowest remaining allowance and that allowance’s reset date. Dashboard integrations can change; failed checks never become 0% or 100%.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    var manualFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entered values do not update automatically. Copy the amount or remaining percentage and period dates from your provider.").font(.caption).foregroundStyle(.secondary)
            Picker("Display", selection: $config.manualKind) {
                Text("Billing-period cost").tag(MetricKind.cost)
                Text("Percentage remaining").tag(MetricKind.remaining)
            }.pickerStyle(.segmented)
            HStack {
                TextField(config.manualKind == .cost ? "Amount" : "Remaining 0–100", text: $amount).textFieldStyle(.roundedBorder)
                if config.manualKind == .cost {
                    Picker("Currency", selection: $config.currency) { ForEach(["USD", "EUR", "GBP", "CAD", "AUD"], id: \.self) { Text($0).tag($0) } }.frame(width: 115)
                } else { Text("%").foregroundStyle(.secondary) }
            }
            DatePicker("Period starts", selection: $config.manualStart, displayedComponents: [.date, .hourAndMinute])
            DatePicker(config.manualKind == .cost ? "Period ends" : "Resets at", selection: $config.manualEnd, displayedComponents: [.date, .hourAndMinute])
        }
    }
    func load() {
        config = store.settings(store.selected)
        amount = config.manualSaved ? String(config.manualValue) : ""
        key = ""
        feedback = nil
    }
    func saveManual() {
        let normalized = amount.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Double(normalized) else { feedback = "Enter a valid number without a currency symbol or thousands separators."; return }
        config.manualValue = value
        config.manualSaved = true
        config.connected = true
        do { try store.saveManual(config); feedback = "Saved. This value is explicitly marked as entered." }
        catch { feedback = error.localizedDescription }
    }
    func saveAndCheck() {
        do {
            if store.selected.usesAPIKey && !key.isEmpty {
                try Credentials.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: store.selected.credentialAccount)
                key = ""
                store.invalidate(store.selected)
            }
            store.configure(config)
            let provider = store.selected
            Task { await store.refresh(provider, force: true); if store.selected == provider { feedback = store.reading(provider).detail } }
        } catch { feedback = error.localizedDescription }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var store: PulseStore
    @AppStorage("liquid-glass") private var liquidGlass = false
    @AppStorage("glass-card-style") private var glassStyle: GlassCardStyle = .standard
    @AppStorage("connection-status-leds") private var connectionLEDs = true
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General").font(.title2.weight(.semibold))
            Text("Applies to all providers and views.").font(.subheadline).foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Refresh rate").font(.headline)
                Picker("Refresh rate", selection: Binding(get: { store.refreshInterval }, set: { store.setRefreshInterval($0) })) {
                    ForEach(UsageRefreshInterval.allCases) { interval in Text(interval.title).tag(interval) }
                }.pickerStyle(.segmented).labelsHidden()
                Text("Automatic usage checks while AI Pulse is running. Hourly by default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Connection status LEDs", isOn: $connectionLEDs).toggleStyle(.switch)
            Text("Show status lights for all providers in Cards, Compact, the menu bar overview, and desktop widgets.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Liquid Glass cards", isOn: $liquidGlass).toggleStyle(.switch)
            if liquidGlass {
                Picker("Glass style", selection: $glassStyle) {
                    ForEach(GlassCardStyle.allCases) { style in Text(style.title).tag(style) }
                }.pickerStyle(.segmented)
                Text("Clear balances transparency with a visible glass edge. Smoked adds a darker tint. Both use white text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Open AI Pulse at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLogin($0) }))
                .font(.caption)
            Text("Add the desktop widget: right-click your desktop → Edit Widgets → AI Pulse. macOS controls widget redraw timing. Keep AI Pulse running for automatic usage checks.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.disabled(store.demo)
    }
}
