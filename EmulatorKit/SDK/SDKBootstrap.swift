import Foundation

/// One downloadable SDK component and where it lands on disk.
public struct SDKComponent: Sendable, Identifiable, Hashable {
    public var id: String { package.path }
    public var package: RepositoryManifest.Package
    public var archive: RepositoryManifest.Archive
    /// Directory that will contain the package content (e.g. `<sdk>/emulator`).
    public var installDirectory: URL
    public var displayName: String { package.displayName }
    public var sizeBytes: Int64 { archive.size }
}

/// What still has to be downloaded to reach a bootable state.
public struct BootstrapPlan: Sendable {
    public var components: [SDKComponent]
    public var licenses: [RepositoryManifest.License]
    public var systemImagePath: String
    public var totalBytes: Int64 { components.reduce(0) { $0 + $1.sizeBytes } }
    public var isEmpty: Bool { components.isEmpty }
}

public enum BootstrapPhase: Sendable, Equatable {
    case fetchingManifests
    case downloading(component: String, progress: DownloadProgress)
    case extracting(component: String)
    case finished
}

/// Downloads and installs emulator, platform-tools and a system image into
/// the isolated SDK root, without Java or sdkmanager.
public actor SDKBootstrap {
    public let paths: SDKPaths
    private let downloader: Downloader
    private let session: URLSession

    public static let defaultTag = "google_apis_playstore"
    public static var defaultABI: String {
        #if arch(arm64)
        return "arm64-v8a"
        #else
        return "x86_64"
        #endif
    }

    public init(paths: SDKPaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
        self.downloader = Downloader(session: session)
    }

    // MARK: Installed state

    /// Reads `Pkg.Revision` from a component's `source.properties`.
    public nonisolated func installedRevision(at directory: URL) -> RepositoryManifest.Revision? {
        let file = directory.appendingPathComponent("source.properties")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "Pkg.Revision" {
                let nums = parts[1].split(separator: ".").compactMap { Int($0) }
                guard let major = nums.first else { return nil }
                return .init(major: major, minor: nums.count > 1 ? nums[1] : 0, micro: nums.count > 2 ? nums[2] : 0)
            }
        }
        return nil
    }

    /// The system image directory currently installed, if any
    /// (`<sdk>/system-images/<api>/<tag>/<abi>` containing `system.img`).
    public nonisolated func installedSystemImage() -> (packagePath: String, directory: URL)? {
        let fm = FileManager.default
        guard let apis = try? fm.contentsOfDirectory(atPath: paths.systemImagesDir.path) else { return nil }
        var found: [(String, URL, Double)] = []
        for api in apis {
            let apiDir = paths.systemImagesDir.appendingPathComponent(api)
            for tag in (try? fm.contentsOfDirectory(atPath: apiDir.path)) ?? [] {
                let tagDir = apiDir.appendingPathComponent(tag)
                for abi in (try? fm.contentsOfDirectory(atPath: tagDir.path)) ?? [] {
                    let dir = tagDir.appendingPathComponent(abi)
                    if fm.fileExists(atPath: dir.appendingPathComponent("system.img").path) {
                        let level = Double(api.replacingOccurrences(of: "android-", with: "")) ?? 0
                        found.append(("system-images;\(api);\(tag);\(abi)", dir, level))
                    }
                }
            }
        }
        return found.sorted { $0.2 > $1.2 }.first.map { ($0.0, $0.1) }
    }

    public nonisolated var isReady: Bool {
        FileManager.default.isExecutableFile(atPath: paths.emulatorBinary.path)
            && FileManager.default.isExecutableFile(atPath: paths.adbBinary.path)
            && installedSystemImage() != nil
    }

    // MARK: Planning

    public func fetchManifests(tag: String = SDKBootstrap.defaultTag) async throws
        -> (repository: RepositoryManifest, systemImages: RepositoryManifest) {
        async let repo = fetchManifest(RepositoryManifest.repositoryURL)
        async let img = fetchManifest(RepositoryManifest.systemImageManifestURL(tag: tag))
        return try await (repo, img)
    }

    private func fetchManifest(_ url: URL) async throws -> RepositoryManifest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EmulatorKitError.manifest("could not fetch \(url.lastPathComponent)")
        }
        // Keep a copy for diagnostics.
        try? data.write(to: paths.cache.appendingPathComponent(url.lastPathComponent))
        return try RepositoryManifest.parse(data: data, baseURL: url)
    }

    /// Builds the plan of missing components. `preferredAPI` (e.g. "36.1")
    /// selects a system image; otherwise the newest stable one is used.
    public func makePlan(tag: String = SDKBootstrap.defaultTag,
                         abi: String = SDKBootstrap.defaultABI,
                         preferredAPI: String? = nil) async throws -> BootstrapPlan {
        let (repo, imgs) = try await fetchManifests(tag: tag)
        return try Self.plan(repository: repo, systemImages: imgs, paths: paths, tag: tag, abi: abi,
                             preferredAPI: preferredAPI, installedRevision: installedRevision(at:))
    }

    /// Pure planning function (unit-testable).
    public static func plan(repository repo: RepositoryManifest,
                            systemImages imgs: RepositoryManifest,
                            paths: SDKPaths,
                            tag: String,
                            abi: String,
                            preferredAPI: String?,
                            installedRevision: (URL) -> RepositoryManifest.Revision?) throws -> BootstrapPlan {
        guard let (emuPkg, emuArchive) = repo.package(path: "emulator") else {
            throw EmulatorKitError.manifest("no stable emulator for this Mac in the repository")
        }
        guard let (ptPkg, ptArchive) = repo.package(path: "platform-tools") else {
            throw EmulatorKitError.manifest("no platform-tools in the repository")
        }
        let images = imgs.systemImages(tag: tag, abi: abi)
        let candidates = images.filter { pkg, _ in
            // Respect the image's minimum emulator revision.
            if let dep = pkg.dependencies.first(where: { $0.path == "emulator" }), let min = dep.minRevision {
                return emuPkg.revision >= min
            }
            return true
        }
        let chosen: (RepositoryManifest.Package, RepositoryManifest.Archive)?
        if let preferredAPI {
            chosen = candidates.first { $0.0.apiLevel == preferredAPI } ?? candidates.first
        } else {
            chosen = candidates.first
        }
        guard let (imgPkg, imgArchive) = chosen else {
            throw EmulatorKitError.manifest("no \(tag) \(abi) system image available")
        }

        var components: [SDKComponent] = []
        func need(_ pkg: RepositoryManifest.Package, _ archive: RepositoryManifest.Archive, _ dir: URL) {
            if let installed = installedRevision(dir), installed >= pkg.revision { return }
            components.append(SDKComponent(package: pkg, archive: archive, installDirectory: dir))
        }
        need(ptPkg, ptArchive, paths.platformToolsDir)
        need(emuPkg, emuArchive, paths.emulatorDir)
        need(imgPkg, imgArchive, paths.directory(forPackagePath: imgPkg.path))

        var licenses: [RepositoryManifest.License] = []
        for (pkg, manifest) in [(ptPkg, repo), (emuPkg, repo), (imgPkg, imgs)] {
            if let ref = pkg.licenseRef, let lic = manifest.licenses[ref], !licenses.contains(lic) {
                licenses.append(lic)
            }
        }
        return BootstrapPlan(components: components, licenses: licenses, systemImagePath: imgPkg.path)
    }

    // MARK: Execution

    public func run(_ plan: BootstrapPlan, progress: @escaping @Sendable (BootstrapPhase) -> Void) async throws {
        try paths.createDirectories()
        try writeLicenses(plan.licenses)
        for component in plan.components {
            let name = component.displayName
            let zip = paths.downloads.appendingPathComponent(component.archive.url.lastPathComponent)
            try await downloader.download(component.archive.url, to: zip,
                                          expectedSize: component.archive.size,
                                          sha1: component.archive.sha1) { p in
                progress(.downloading(component: name, progress: p))
            }
            progress(.extracting(component: name))
            try await install(zip: zip, into: component.installDirectory)
            try? FileManager.default.removeItem(at: zip)
        }
        progress(.finished)
    }

    /// Extracts into a staging directory, then moves the zip's single
    /// top-level folder to `destination` (replacing any previous install).
    private func install(zip: URL, into destination: URL) async throws {
        let fm = FileManager.default
        let staging = paths.downloads.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try await Unarchiver.extract(zip: zip, into: staging)
        let entries = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        let source: URL
        if entries.count == 1, (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            source = entries[0]
        } else {
            source = staging
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: source, to: destination)
    }

    private func writeLicenses(_ licenses: [RepositoryManifest.License]) throws {
        try FileManager.default.createDirectory(at: paths.licenses, withIntermediateDirectories: true)
        for lic in licenses {
            let file = paths.licenses.appendingPathComponent(lic.id)
            let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if !existing.contains(lic.hash) {
                try (existing + (existing.isEmpty ? "" : "\n") + lic.hash + "\n").write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
}
