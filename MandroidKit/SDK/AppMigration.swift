import Foundation

/// One-time upgrade from either former app name. Never merges or overwrites data roots.
public enum AppMigration {
    public static let legacyNames = ["Madroid", "AndroidAppRunner"]
    public static let legacyBundleIDs = ["io.github.madeye.madroid", "io.github.madeye.androidapprunner"]
    public static let bundleID = "io.github.madeye.mandroid"

    public static func source(in support: URL) -> URL? {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: support.appendingPathComponent("Mandroid").path) else { return nil }
        return legacyNames.map { support.appendingPathComponent($0, isDirectory: true) }
            .first { fm.fileExists(atPath: $0.path) }
    }

    @discardableResult
    public static func migrateData(in support: URL) throws -> URL? {
        guard let old = source(in: support) else { return nil }
        try FileManager.default.moveItem(at: old, to: support.appendingPathComponent("Mandroid", isDirectory: true))
        return old
    }

    /// Copy explicit preferences, preserving new choices and preferring the most recent old app.
    /// This runs independently of the folder move, so an interrupted migration can finish next launch.
    public static func migratePreferences(_ defaults: UserDefaults, destination: String = bundleID,
                                          sources: [String] = legacyBundleIDs) {
        var current = defaults.persistentDomain(forName: destination) ?? [:]
        guard current["migratedLegacyPreferences"] as? Bool != true else { return }
        for source in sources {
            for (key, value) in defaults.persistentDomain(forName: source) ?? [:]
            where current[key] == nil && !["dataRoot", "uiTestControlDirectory"].contains(key) {
                current[key] = value
            }
        }
        current["migratedLegacyPreferences"] = true
        defaults.setPersistentDomain(current, forName: destination)
    }
}
