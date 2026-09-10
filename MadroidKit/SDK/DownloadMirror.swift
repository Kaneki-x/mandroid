import Foundation

/// Where SDK components (emulator, platform-tools, system images) and aapt2
/// are downloaded from. Google's own hosts are unreachable from mainland
/// China, so a mirror can be chosen explicitly or picked automatically from
/// the Mac's region and time zone. Manifests are fetched from the mirror, so
/// the relative archive URLs inside them resolve to the same mirror.
public struct DownloadMirror: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// Mirror of `https://dl.google.com/android/repository/` (trailing slash).
    public let repositoryBase: URL
    /// Mirror of Google Maven, `https://dl.google.com/dl/android/maven2/` (trailing slash).
    public let mavenBase: URL

    public static let google = DownloadMirror(
        id: "google", name: "Google (dl.google.com)",
        repositoryBase: URL(string: "https://dl.google.com/android/repository/")!,
        mavenBase: URL(string: "https://dl.google.com/dl/android/maven2/")!)

    /// Tencent Cloud mirrors the SDK repository; Aliyun proxies Google Maven.
    /// (`dl.google.cn` no longer resolves.)
    public static let china = DownloadMirror(
        id: "china", name: "China mirror (Tencent Cloud, Aliyun)",
        repositoryBase: URL(string: "https://mirrors.cloud.tencent.com/AndroidSDK/")!,
        mavenBase: URL(string: "https://maven.aliyun.com/repository/google/")!)

    public static let all: [DownloadMirror] = [google, china]

    public var repositoryManifestURL: URL { repositoryBase.appendingPathComponent("repository2-3.xml") }
    public func systemImageManifestURL(tag: String) -> URL {
        repositoryBase.appendingPathComponent("sys-img/\(tag)/sys-img2-3.xml")
    }
    public var aapt2Base: URL { mavenBase.appendingPathComponent("com/android/tools/build/aapt2/") }
    public var host: String { repositoryBase.host ?? id }

    /// Rewrites a URL that lives under one of this mirror's bases to the same
    /// path on `other`; nil when `url` is not under either base.
    public func rewrite(_ url: URL, to other: DownloadMirror) -> URL? {
        let s = url.absoluteString
        for (mine, theirs) in [(repositoryBase, other.repositoryBase), (mavenBase, other.mavenBase)] {
            let prefix = mine.absoluteString
            if s.hasPrefix(prefix) { return URL(string: theirs.absoluteString + s.dropFirst(prefix.count)) }
        }
        return nil
    }

    // MARK: Selection

    public enum Preference: String, Sendable, CaseIterable, Hashable {
        case auto, google, china
    }

    /// Mirrors to try, most preferred first. Only China users ever download
    /// from the China mirror: `auto` selects it when the Mac's region or time
    /// zone is mainland China, and the user can force it. Google is the origin,
    /// so it stays as the fallback behind the mirror; the reverse never happens
    /// (a Google-first list has no mirror fallback).
    public static func order(for preference: Preference,
                             regionCode: String? = Locale.current.region?.identifier,
                             timeZoneID: String = TimeZone.current.identifier) -> [DownloadMirror] {
        switch preference {
        case .google: return [google]
        case .china: return [china, google]
        case .auto: return looksLikeMainlandChina(regionCode: regionCode, timeZoneID: timeZoneID) ? [china, google] : [google]
        }
    }

    static func looksLikeMainlandChina(regionCode: String?, timeZoneID: String) -> Bool {
        if regionCode?.uppercased() == "CN" { return true }
        return ["Asia/Shanghai", "Asia/Chongqing", "Asia/Chungking", "Asia/Harbin", "Asia/Urumqi", "Asia/Kashgar", "PRC"]
            .contains(timeZoneID)
    }
}
