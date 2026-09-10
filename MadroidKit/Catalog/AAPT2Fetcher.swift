import Foundation

/// Downloads the `aapt2` binary (a universal Mach-O inside Google Maven's
/// `aapt2-<version>-osx.jar`, no JVM needed) into `<root>/tools/aapt2`.
public actor AAPT2Fetcher {
    public let paths: SDKPaths
    private let session: URLSession
    /// Known-good fallback if maven-metadata cannot be fetched.
    public static let fallbackVersion = "9.4.0-15978811"
    /// Download hosts to try, most preferred first.
    private let mirrors: [DownloadMirror]

    public init(paths: SDKPaths, mirrors: [DownloadMirror] = DownloadMirror.order(for: .auto), session: URLSession = .shared) {
        self.paths = paths
        self.mirrors = mirrors.isEmpty ? [.google] : mirrors
        self.session = session
    }

    public nonisolated var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: paths.aapt2Binary.path)
    }

    /// Returns the binary URL, downloading it on first use.
    public func ensureInstalled() async throws -> URL {
        if isInstalled { return paths.aapt2Binary }
        let (version, mirror) = await latestStableVersion()
        let jar = paths.downloads.appendingPathComponent("aapt2-\(version)-osx.jar")
        try paths.createDirectories()
        let downloader = Downloader(session: session)
        var lastError: Error?
        for candidate in [mirror] + mirrors.filter({ $0 != mirror }) {
            let jarURL = candidate.aapt2Base.appendingPathComponent("\(version)/aapt2-\(version)-osx.jar")
            do {
                try await downloader.download(jarURL, to: jar, expectedSize: nil, sha1: nil) { _ in }
                lastError = nil
                break
            } catch {
                Log.sdk.error("aapt2 from \(candidate.host) failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        if let lastError { throw lastError }
        // The jar is a zip; extract just the binary.
        let r = try await Subprocess.run(URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-p", jar.path, "aapt2"])
        guard r.status == 0, !r.stdout.isEmpty else { throw MadroidKitError.unarchive("aapt2 missing from \(jar.lastPathComponent)") }
        try r.stdout.write(to: paths.aapt2Binary, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.aapt2Binary.path)
        await Unarchiver.stripQuarantine(at: paths.aapt2Binary)
        try? FileManager.default.removeItem(at: jar)
        Log.sdk.info("installed aapt2 \(version)")
        return paths.aapt2Binary
    }

    /// Highest stable version in maven-metadata.xml from the first mirror
    /// that answers, with the mirror it came from; the known-good fallback
    /// version and the preferred mirror when none does.
    func latestStableVersion() async -> (version: String, mirror: DownloadMirror) {
        for mirror in mirrors {
            var request = URLRequest(url: mirror.aapt2Base.appendingPathComponent("maven-metadata.xml"))
            request.timeoutInterval = 20
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let text = String(decoding: data, as: UTF8.self)
            if let v = Self.pickStable(fromMavenMetadata: text) { return (v, mirror) }
        }
        return (Self.fallbackVersion, mirrors[0])
    }

    public static func pickStable(fromMavenMetadata text: String) -> String? {
        var versions: [String] = []
        var rest = text[...]
        while let r = rest.range(of: "<version>") {
            rest = rest[r.upperBound...]
            guard let end = rest.range(of: "</version>") else { break }
            let v = String(rest[..<end.lowerBound])
            if !v.contains("alpha"), !v.contains("beta"), !v.contains("rc"), !v.contains("dev") { versions.append(v) }
            rest = rest[end.upperBound...]
        }
        return versions.max { a, b in
            let ka = a.split(whereSeparator: { $0 == "." || $0 == "-" }).compactMap { Int($0) }
            let kb = b.split(whereSeparator: { $0 == "." || $0 == "-" }).compactMap { Int($0) }
            return ka.lexicographicallyPrecedes(kb)
        }
    }
}
