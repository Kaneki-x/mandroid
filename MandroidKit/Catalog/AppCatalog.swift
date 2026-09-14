import Foundation

/// A third-party app installed on the device, with presentation metadata.
public struct AppInfo: Sendable, Hashable, Identifiable, Codable {
    public var id: String { package }
    public var package: String
    public var label: String
    public var versionCode: Int
    public var versionName: String
    public var launcherComponent: String?
    /// PNG or WebP file in the cache, if an icon could be extracted.
    public var iconFile: URL?

    public init(package: String, label: String, versionCode: Int, versionName: String,
                launcherComponent: String?, iconFile: URL?) {
        self.package = package; self.label = label; self.versionCode = versionCode
        self.versionName = versionName; self.launcherComponent = launcherComponent; self.iconFile = iconFile
    }
}

/// Parses `pm list packages -3 --show-versioncode`.
public enum InstalledApps {
    public static func parse(_ text: String) -> [(package: String, versionCode: Int)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("package:") else { return nil }
            let parts = s.dropFirst("package:".count).split(separator: " ")
            guard let pkg = parts.first, pkg != ADBClient.proxyAgentPackage else { return nil }
            let vc = parts.dropFirst().first { $0.hasPrefix("versionCode:") }
                .flatMap { Int($0.dropFirst("versionCode:".count)) } ?? 0
            return (String(pkg), vc)
        }.sorted { $0.package < $1.package }
    }
}

/// Builds and caches `AppInfo` for installed packages. Labels and icons come
/// from `aapt2 dump badging` on the pulled base APK; results are cached per
/// package + versionCode under `<root>/cache/apps/`.
public actor AppCatalog {
    public let paths: SDKPaths
    private let adb: ADBClient
    private let aapt2: AAPT2Fetcher

    public init(paths: SDKPaths, adb: ADBClient, mirrors: [DownloadMirror] = DownloadMirror.order(for: .auto)) {
        self.paths = paths
        self.adb = adb
        self.aapt2 = AAPT2Fetcher(paths: paths, mirrors: mirrors)
    }

    private var cacheDir: URL { paths.cache.appendingPathComponent("apps", isDirectory: true) }
    private func entryDir(_ pkg: String, _ vc: Int) -> URL { cacheDir.appendingPathComponent("\(pkg)-\(vc)", isDirectory: true) }

    /// Fast path: whatever is cached for the currently installed set, with
    /// package-name placeholders for the rest. Follow with `refresh`.
    public func cached() async throws -> [AppInfo] {
        let installed = InstalledApps.parse(try await adb.shell("pm list packages -3 --show-versioncode"))
        return installed.map { load($0.package, $0.versionCode) ?? placeholder($0.package, $0.versionCode) }
    }

    /// Fills in labels and icons for anything not cached. Calls `onUpdate`
    /// with the full list after each newly resolved app.
    public func refresh(onUpdate: @escaping @Sendable ([AppInfo]) -> Void) async throws -> [AppInfo] {
        let installed = InstalledApps.parse(try await adb.shell("pm list packages -3 --show-versioncode"))
        var result = installed.map { load($0.package, $0.versionCode) ?? placeholder($0.package, $0.versionCode) }
        onUpdate(result)
        var tool: URL?
        for (i, app) in installed.enumerated() where load(app.package, app.versionCode, requireCurrentIcon: true) == nil {
            try Task.checkCancellation()
            do {
                if tool == nil { tool = try await aapt2.ensureInstalled() }
                let info = try await resolve(package: app.package, versionCode: app.versionCode, aapt2: tool!)
                result[i] = info
                onUpdate(result)
            } catch {
                try Task.checkCancellation()
                Log.sdk.warning("catalog: \(app.package): \(error.localizedDescription)")
            }
        }
        pruneCache(keeping: Set(installed.map { "\($0.package)-\($0.versionCode)" }))
        return result
    }

    public func invalidate(package: String) {
        for dir in (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)) ?? []
        where dir.lastPathComponent.hasPrefix("\(package)-") {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: Internals

    private func placeholder(_ pkg: String, _ vc: Int) -> AppInfo {
        let last = pkg.split(separator: ".").last.map(String.init) ?? pkg
        return AppInfo(package: pkg, label: last.prefix(1).uppercased() + last.dropFirst(), versionCode: vc,
                       versionName: "", launcherComponent: nil, iconFile: nil)
    }

    // Version the extraction strategy independently from the installed APK.
    // Older metadata remains useful while its icon is repaired in the background.
    struct CacheEntry: Codable {
        var iconVersion: Int
        var app: AppInfo
    }

    private func load(_ pkg: String, _ vc: Int, requireCurrentIcon: Bool = false) -> AppInfo? {
        Self.loadCache(in: entryDir(pkg, vc), requireCurrentIcon: requireCurrentIcon)
    }

    static func loadCache(in dir: URL, requireCurrentIcon: Bool = false) -> AppInfo? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")) else { return nil }
        let entry = try? JSONDecoder().decode(CacheEntry.self, from: data)
        guard var info = entry?.app ?? (try? JSONDecoder().decode(AppInfo.self, from: data)) else { return nil }
        // Re-anchor the icon path in case the root moved.
        if info.iconFile != nil {
            let f = dir.appendingPathComponent("icon")
            info.iconFile = FileManager.default.fileExists(atPath: f.path) ? f : nil
        }
        if requireCurrentIcon && (entry?.iconVersion != 1 || info.iconFile == nil) { return nil }
        return info
    }

    private func resolve(package pkg: String, versionCode vc: Int, aapt2: URL) async throws -> AppInfo {
        let dir = entryDir(pkg, vc)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pathsOut = try await adb.shell("pm path \(ADBClient.shellQuote(pkg))")
        guard let remote = pathsOut.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix("package:") && $0.hasSuffix("base.apk") })?
            .dropFirst("package:".count)
            ?? pathsOut.split(whereSeparator: \.isNewline).first.map({ $0.trimmingCharacters(in: .whitespaces).dropFirst("package:".count) })
        else { throw MandroidKitError.adb("no apk path for \(pkg)") }
        let apk = dir.appendingPathComponent("base.apk")
        try await adb.run(["pull", String(remote), apk.path], timeout: .seconds(120))
        defer { try? FileManager.default.removeItem(at: apk) }

        let r = try await Subprocess.run(aapt2, arguments: ["dump", "badging", apk.path])
        guard r.status == 0, let badging = APKBadging.parse(r.stdoutText) else {
            throw MandroidKitError.adb("aapt2 badging failed for \(pkg): \(r.stderrText.prefix(200))")
        }
        var iconFile: URL?
        let renderedIcon = try? await adb.launcherIcon(of: pkg)
        let bytes: Data?
        if let renderedIcon {
            bytes = renderedIcon
        } else {
            // Keep a best-effort raster icon if Android rendering is temporarily unavailable.
            bytes = try? await IconExtractor.icon(fromAPK: apk, badging: badging)
        }
        if let bytes, !bytes.isEmpty {
            let f = dir.appendingPathComponent("icon")
            try bytes.write(to: f)
            iconFile = f
        }
        var component = badging.launchableActivity.map { "\(pkg)/\($0)" }
        if component == nil { component = try? await adb.launcherComponent(of: pkg) }
        let info = AppInfo(package: pkg, label: badging.label(), versionCode: badging.versionCode,
                           versionName: badging.versionName, launcherComponent: component, iconFile: iconFile)
        try JSONEncoder().encode(CacheEntry(iconVersion: renderedIcon == nil ? 0 : 1, app: info))
            .write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        return info
    }

    private func pruneCache(keeping: Set<String>) {
        for dir in (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)) ?? []
        where !keeping.contains(dir.lastPathComponent) {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}
