import Foundation

enum SnapshotStore {
    static let group = Bundle.main.object(forInfoDictionaryKey: "AIPulseAppGroup") as? String ?? "unconfigured.nl.martijn.aipulse"
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("readings-v1.json")
    }
    private static var connectionLEDURL: URL? { url?.deletingLastPathComponent().appendingPathComponent("connection-leds-v1.json") }
    static var connectionLEDsEnabled: Bool {
        guard let url = connectionLEDURL, let data = try? Data(contentsOf: url) else { return true }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? true
    }
    static func writeConnectionLEDsEnabled(_ enabled: Bool) throws {
        guard let url = connectionLEDURL else { throw UsageError.unavailable("The widget container is unavailable.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(enabled).write(to: url, options: .atomic)
    }
    static func read() -> [Reading] {
        guard let url, let data = try? Data(contentsOf: url), let readings = try? JSONDecoder().decode([Reading].self, from: data) else { return Reading.empty }
        return readings
    }
    static func write(_ readings: [Reading]) throws {
        guard let url else { throw UsageError.unavailable("The shared widget container is unavailable. Check App Group signing in Xcode.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(readings).write(to: url, options: .atomic)
    }
}
