import Foundation

/// The parts of `aapt2 dump badging` we use.
public struct APKBadging: Sendable, Hashable {
    public var package: String
    public var versionCode: Int
    public var versionName: String
    public var label: String
    public var labels: [String: String]          // locale → label
    public var icons: [Int: String]              // density → path inside the APK
    public var launchableActivity: String?
    public var targetSdk: Int?

    /// Best label for the current locale, falling back to the default.
    public func label(for locale: Locale = .current) -> String {
        if let code = locale.language.languageCode?.identifier {
            let region = locale.region?.identifier
            if let region, let l = labels["\(code)-\(region)"] { return l }
            if let l = labels[code] { return l }
        }
        return label
    }

    /// Highest real-density icon path. aapt2 also lists pseudo densities
    /// (65534 = anydpi, 65535 = nodpi) that usually point at the mdpi asset,
    /// so those only count when nothing else exists.
    public var bestIconPath: String? {
        let real = icons.filter { $0.key <= 640 }
        return (real.isEmpty ? icons : real).max { $0.key < $1.key }?.value
    }

    public static func parse(_ text: String) -> APKBadging? {
        var b = APKBadging(package: "", versionCode: 0, versionName: "", label: "", labels: [:], icons: [:], launchableActivity: nil, targetSdk: nil)
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("package:") {
                b.package = attr("name", in: line) ?? ""
                b.versionCode = Int(attr("versionCode", in: line) ?? "") ?? 0
                b.versionName = attr("versionName", in: line) ?? ""
            } else if line.hasPrefix("application-label:") {
                b.label = quoted(line)
            } else if line.hasPrefix("application-label-") {
                let key = line.dropFirst("application-label-".count).prefix { $0 != ":" }
                b.labels[String(key)] = quoted(line)
            } else if line.hasPrefix("application-icon-") {
                let key = line.dropFirst("application-icon-".count).prefix { $0 != ":" }
                if let d = Int(key) { b.icons[d] = quoted(line) }
            } else if line.hasPrefix("application:") {
                if b.label.isEmpty { b.label = attr("label", in: line) ?? "" }
                if b.icons.isEmpty, let icon = attr("icon", in: line), !icon.isEmpty { b.icons[0] = icon }
            } else if line.hasPrefix("launchable-activity:") {
                b.launchableActivity = attr("name", in: line)
            } else if line.hasPrefix("targetSdkVersion:") {
                b.targetSdk = Int(quoted(line))
            }
        }
        guard !b.package.isEmpty else { return nil }
        if b.label.isEmpty { b.label = b.package }
        return b
    }

    private static func attr(_ name: String, in line: String) -> String? {
        guard let r = line.range(of: " \(name)='") else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.firstIndex(of: "'") else { return nil }
        return String(rest[..<end])
    }

    /// Value after the first `:'` up to the closing quote.
    private static func quoted(_ line: String) -> String {
        guard let r = line.range(of: ":'") else { return "" }
        let rest = line[r.upperBound...]
        guard let end = rest.lastIndex(of: "'") else { return String(rest) }
        return String(rest[..<end])
    }
}
