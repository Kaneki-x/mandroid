import Foundation

/// A parsed `repository2-3.xml` / `sys-img2-3.xml` manifest from
/// `dl.google.com/android/repository/`.
///
/// Traps handled here (see DESIGN §3.4): several entries share one `path`
/// (channels), archive URLs are relative to the manifest's directory, a
/// missing `host-arch` means universal, licenses are per manifest, and
/// packages may declare `<dependency>` minimum revisions.
public struct RepositoryManifest: Sendable {
    public struct Revision: Sendable, Hashable, Comparable, CustomStringConvertible {
        public var major: Int, minor: Int, micro: Int
        public init(major: Int, minor: Int = 0, micro: Int = 0) {
            self.major = major; self.minor = minor; self.micro = micro
        }
        public static func < (a: Revision, b: Revision) -> Bool {
            (a.major, a.minor, a.micro) < (b.major, b.minor, b.micro)
        }
        public var description: String {
            minor == 0 && micro == 0 ? "\(major)" : "\(major).\(minor).\(micro)"
        }
    }

    public struct Archive: Sendable, Hashable {
        public var hostOS: String?      // "macosx", "linux", "windows" or nil
        public var hostArch: String?    // "x64", "aarch64" or nil (universal)
        public var url: URL             // absolute
        public var size: Int64
        public var sha1: String
    }

    public struct Dependency: Sendable, Hashable {
        public var path: String
        public var minRevision: Revision?
    }

    public struct Package: Sendable, Hashable {
        public var path: String
        public var revision: Revision
        public var displayName: String
        public var channel: String?       // "channel-0" (stable) … "channel-3" (canary)
        public var licenseRef: String?
        public var archives: [Archive]
        public var dependencies: [Dependency]
        // sys-img details
        public var apiLevel: String?
        public var tagID: String?
        public var abi: String?

        public var isStable: Bool { channel == nil || channel == "channel-0" }
    }

    public struct License: Sendable, Hashable {
        public var id: String
        public var text: String
        /// SHA-1 of the license text, as written to `<sdk>/licenses/<id>`.
        public var hash: String { SHA1.hex(of: Data(text.utf8)) }
    }

    public var packages: [Package]
    public var licenses: [String: License]
    public var channels: [String: String]   // "channel-0" → "stable"

    // MARK: Queries

    public enum HostArch: String, Sendable { case x64, aarch64
        public static var current: HostArch {
            #if arch(arm64)
            return .aarch64
            #else
            return .x64
            #endif
        }
    }

    /// The newest stable package for `path` that has an archive for macOS on
    /// `arch`. Falls back to any channel if `stableOnly` is false.
    public func package(path: String, arch: HostArch = .current, stableOnly: Bool = true) -> (Package, Archive)? {
        let candidates = packages
            .filter { $0.path == path && (!stableOnly || $0.isStable) }
            .sorted { $0.revision > $1.revision }
        for p in candidates {
            if let a = p.archive(forMacOS: arch) { return (p, a) }
        }
        return nil
    }

    /// Newest stable system image matching the tag and abi, highest API first.
    public func systemImages(tag: String, abi: String, stableOnly: Bool = true) -> [(Package, Archive)] {
        packages
            .filter { $0.tagID == tag && $0.abi == abi && (!stableOnly || $0.isStable) && $0.path.contains(";\(tag);") }
            .compactMap { p in p.archive(forMacOS: .current).map { (p, $0) } }
            .sorted { apiSortKey($0.0.apiLevel) > apiSortKey($1.0.apiLevel) }
    }

    private func apiSortKey(_ s: String?) -> Double { Double(s ?? "") ?? 0 }

    // MARK: Parsing

    public static func parse(data: Data, baseURL: URL) throws -> RepositoryManifest {
        let delegate = ManifestParserDelegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw EmulatorKitError.manifest(parser.parserError?.localizedDescription ?? "invalid XML")
        }
        if let err = delegate.error { throw err }
        return RepositoryManifest(packages: delegate.packages, licenses: delegate.licenses, channels: delegate.channels)
    }

    /// Well-known manifest locations.
    public static let repositoryURL = URL(string: "https://dl.google.com/android/repository/repository2-3.xml")!
    public static func systemImageManifestURL(tag: String) -> URL {
        URL(string: "https://dl.google.com/android/repository/sys-img/\(tag)/sys-img2-3.xml")!
    }
}

extension RepositoryManifest.Package {
    public func archive(forMacOS arch: RepositoryManifest.HostArch) -> RepositoryManifest.Archive? {
        // Prefer an exact arch match, then universal (no host-arch), never a
        // different architecture.
        let mac = archives.filter { $0.hostOS == nil || $0.hostOS == "macosx" }
        if let exact = mac.first(where: { $0.hostArch == arch.rawValue }) { return exact }
        return mac.first(where: { $0.hostArch == nil })
    }
}

// MARK: - XML parsing

private final class ManifestParserDelegate: NSObject, XMLParserDelegate {
    let baseURL: URL
    var packages: [RepositoryManifest.Package] = []
    var licenses: [String: RepositoryManifest.License] = [:]
    var channels: [String: String] = [:]
    var error: Error?

    private var path: [String] = []
    private var text = ""
    private var current: RepositoryManifest.Package?
    private var currentArchive: (os: String?, arch: String?, url: String?, size: Int64?, sha1: String?)?
    private var currentDependency: RepositoryManifest.Dependency?
    private var currentLicenseID: String?
    private var currentChannelID: String?
    private var revision: (Int, Int, Int) = (0, 0, 0)
    private var inMinRevision = false
    private var inTag = false

    init(baseURL: URL) {
        self.baseURL = baseURL.deletingLastPathComponent()
    }

    private func local(_ name: String) -> String {
        if let i = name.firstIndex(of: ":") { return String(name[name.index(after: i)...]) }
        return name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        let name = local(elementName)
        path.append(name)
        text = ""
        switch name {
        case "remotePackage":
            current = RepositoryManifest.Package(path: attributes["path"] ?? "", revision: .init(major: 0),
                                                 displayName: "", channel: nil, licenseRef: nil, archives: [],
                                                 dependencies: [], apiLevel: nil, tagID: nil, abi: nil)
            revision = (0, 0, 0)
        case "archive":
            currentArchive = (nil, nil, nil, nil, nil)
        case "uses-license":
            current?.licenseRef = attributes["ref"]
        case "channelRef":
            current?.channel = attributes["ref"]
        case "dependency":
            currentDependency = .init(path: attributes["path"] ?? "", minRevision: nil)
        case "min-revision":
            inMinRevision = true; revision = (0, 0, 0)
        case "revision" where current != nil && currentDependency == nil:
            revision = (0, 0, 0)
        case "license":
            currentLicenseID = attributes["id"]
        case "channel":
            currentChannelID = attributes["id"]
        case "tag":
            inTag = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = local(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "major": revision.0 = Int(value) ?? 0
        case "minor": revision.1 = Int(value) ?? 0
        case "micro": revision.2 = Int(value) ?? 0
        case "revision":
            if current != nil, currentDependency == nil, !inMinRevision {
                current?.revision = .init(major: revision.0, minor: revision.1, micro: revision.2)
            }
        case "min-revision":
            currentDependency?.minRevision = .init(major: revision.0, minor: revision.1, micro: revision.2)
            inMinRevision = false
        case "dependency":
            if let d = currentDependency { current?.dependencies.append(d) }
            currentDependency = nil
        case "display-name": current?.displayName = value
        case "api-level": current?.apiLevel = value
        case "abi": current?.abi = value
        case "id" where inTag: current?.tagID = value
        case "tag": inTag = false
        case "host-os": currentArchive?.os = value
        case "host-arch": currentArchive?.arch = value
        case "url" where currentArchive != nil: currentArchive?.url = value
        case "size" where currentArchive != nil: currentArchive?.size = Int64(value)
        case "checksum" where currentArchive != nil: currentArchive?.sha1 = value.lowercased()
        case "archive":
            if let a = currentArchive, let u = a.url, let size = a.size, let sha = a.sha1 {
                let url = URL(string: u, relativeTo: baseURL)?.absoluteURL ?? baseURL.appendingPathComponent(u)
                current?.archives.append(.init(hostOS: a.os, hostArch: a.arch, url: url, size: size, sha1: sha))
            }
            currentArchive = nil
        case "remotePackage":
            if let p = current, !p.path.isEmpty { packages.append(p) }
            current = nil
        case "license":
            if let id = currentLicenseID { licenses[id] = .init(id: id, text: text) }
            currentLicenseID = nil
        case "channel":
            if let id = currentChannelID { channels[id] = value }
            currentChannelID = nil
        default: break
        }
        path.removeLast()
        text = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = EmulatorKitError.manifest(parseError.localizedDescription)
    }
}
