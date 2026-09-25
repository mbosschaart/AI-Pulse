import AppKit
import Combine
import Sparkle

@MainActor final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()
    @Published private(set) var status = "Updates are checked when Settings first opens."
    @Published private(set) var canCheck = false
    private var policy = UpdateCheckPolicy()
    private var observation: AnyCancellable?
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    private var started = false
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "AIPulseDisplayVersion") as? String ?? "0.1b" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    private func start() -> Bool {
        guard !started else { return true }
        // Override any persisted Sparkle preference: this app never schedules checks.
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = false
        do {
            try controller.updater.start()
            started = true
            observation = controller.updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] in self?.canCheck = $0 }
            return true
        } catch { status = "Updater could not start: \(error.localizedDescription)"; return false }
    }
    func settingsOpened() {
        guard policy.settingsOpened(), start() else { return }
        status = "Checking for updates…"
        controller.updater.checkForUpdatesInBackground()
    }
    func checkForUpdates() {
        guard start(), controller.updater.canCheckForUpdates else { return }
        status = "Checking for updates…"
        controller.checkForUpdates(nil)
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "Version \(item.displayVersionString) is available."
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = "You’re up to date."
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // Sparkle reports a no-update result through its error path too.
        let error = error as NSError
        if error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue {
            status = "You’re up to date."
        } else { status = "Could not check for updates: \(error.localizedDescription)" }
    }
}
