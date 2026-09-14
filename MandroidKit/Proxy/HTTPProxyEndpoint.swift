import Foundation

public struct HTTPProxyEndpoint: Codable, Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) throws {
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:"))
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(allowed.contains), (1...65535).contains(port) else {
            throw MandroidKitError.adb("Enter a proxy hostname or IP address and a port from 1 to 65535.")
        }
        self.host = host
        self.port = port
    }

    enum CodingKeys: String, CodingKey { case host, port }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(host: values.decode(String.self, forKey: .host), port: values.decode(Int.self, forKey: .port))
    }

    /// Android Emulator's alias for the Mac's loopback interface.
    public var androidHost: String { ["localhost", "127.0.0.1", "::1"].contains(host) ? "10.0.2.2" : host }
}

public enum AppProxyStore {
    public static func load(at root: URL) throws -> [String: HTTPProxyEndpoint] {
        let file = root.appendingPathComponent("app-proxies.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        return try JSONDecoder().decode([String: HTTPProxyEndpoint].self, from: Data(contentsOf: file))
    }
    public static func save(_ proxies: [String: HTTPProxyEndpoint], at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(proxies).write(to: root.appendingPathComponent("app-proxies.json"), options: .atomic)
    }
}
