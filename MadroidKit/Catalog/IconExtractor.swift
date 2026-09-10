import Foundation

/// Pulls a raster launcher icon out of an APK. Adaptive icons (`.xml`) are
/// resolved by looking for a raster with the same base name at the highest
/// available density; if none exists the caller draws a letter tile.
public enum IconExtractor {
    static let densityRank: [String: Int] = [
        "xxxhdpi": 640, "xxhdpi": 480, "xhdpi": 320, "hdpi": 240, "mdpi": 160, "ldpi": 120, "anydpi": 1, "nodpi": 100,
    ]

    /// Returns PNG/WebP bytes or nil.
    public static func icon(fromAPK apk: URL, badging: APKBadging) async throws -> Data? {
        guard let path = badging.bestIconPath else { return nil }
        if !path.hasSuffix(".xml") {
            return try await entry(path, in: apk)
        }
        // Adaptive icon: find a raster sibling.
        let base = (path as NSString).lastPathComponent.replacingOccurrences(of: ".xml", with: "")
        let entries = try await listEntries(in: apk)
        let candidates = entries.filter { e in
            let name = (e as NSString).lastPathComponent
            return (name == "\(base).png" || name == "\(base).webp") && e.hasPrefix("res/")
        }
        guard let best = candidates.max(by: { rank($0) < rank($1) }) else {
            // Try the round icon or foreground as a last resort.
            guard let alt = entries.first(where: { $0.hasPrefix("res/") && ($0.hasSuffix("\(base)_round.png") || $0.hasSuffix("\(base)_round.webp")) }) else { return nil }
            return try await entry(alt, in: apk)
        }
        return try await entry(best, in: apk)
    }

    static func rank(_ entry: String) -> Int {
        let dir = (entry as NSString).deletingLastPathComponent
        let qualifiers = ((dir as NSString).lastPathComponent).split(separator: "-").map(String.init)
        return qualifiers.compactMap { densityRank[$0] }.first ?? 0
    }

    static func listEntries(in apk: URL) async throws -> [String] {
        let r = try await Subprocess.run(URL(fileURLWithPath: "/usr/bin/zipinfo"), arguments: ["-1", apk.path])
        guard r.status == 0 else { throw MadroidKitError.unarchive("zipinfo failed for \(apk.lastPathComponent)") }
        return r.stdoutText.split(whereSeparator: \.isNewline).map(String.init)
    }

    static func entry(_ name: String, in apk: URL) async throws -> Data? {
        let r = try await Subprocess.run(URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-p", apk.path, name])
        guard r.status == 0, !r.stdout.isEmpty else { return nil }
        return r.stdout
    }
}
