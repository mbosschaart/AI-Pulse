/// No timer or launch-triggered checks. Each process checks on its first Settings opening.
struct UpdateCheckPolicy {
    private(set) var hasOpenedSettings = false
    mutating func settingsOpened() -> Bool {
        guard !hasOpenedSettings else { return false }
        hasOpenedSettings = true
        return true
    }
}
