import Foundation

enum SnapshotStore {
    static let group = Bundle.main.object(forInfoDictionaryKey: "AIPulseAppGroup") as? String ?? "unconfigured.nl.martijn.aipulse"
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("readings-v1.json")
    }
    private static var appearanceURL: URL? { url?.deletingLastPathComponent().appendingPathComponent("appearance-v1.json") }
    static var glassEnabled: Bool {
        guard let url = appearanceURL, let data = try? Data(contentsOf: url) else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }
    static func writeGlassEnabled(_ enabled: Bool) throws {
        guard let url = appearanceURL else { throw UsageError.unavailable("The widget container is unavailable.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(enabled).write(to: url, options: .atomic)
    }
    private static var styleURL: URL? { url?.deletingLastPathComponent().appendingPathComponent("glass-style-v1.json") }
    static var glassStyle: String {
        guard let url = styleURL, let data = try? Data(contentsOf: url) else { return "standard" }
        return (try? JSONDecoder().decode(String.self, from: data)) ?? "standard"
    }
    static func writeGlassStyle(_ style: String) throws {
        guard let url = styleURL else { throw UsageError.unavailable("The widget container is unavailable.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(style).write(to: url, options: .atomic)
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
