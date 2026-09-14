import Foundation

extension ADBClient {
    public static let proxyAgentPackage = "io.github.madeye.mandroid.proxy"

    /// Applies all per-app endpoints together. The guest acknowledges this exact revision.
    public func applyAppProxies(_ proxies: [String: HTTPProxyEndpoint]) async throws {
        let installed = Set(InstalledApps.parse(try await shell("pm list packages -3 --show-versioncode")).map(\.package))
        let selected = proxies.filter { installed.contains($0.key) }
        let agent = Self.proxyAgentPackage
        if selected.isEmpty {
            let packages = try await shell("pm list packages \(Self.shellQuote(agent))")
            if !packages.contains("package:\(agent)") { return }
        } else {
            try await deployProxyAgent()
            try await shell("appops set \(agent) ACTIVATE_VPN allow")
        }
        struct Configuration: Encodable {
            let revision: String
            let apps: [String: HTTPProxyEndpoint]
        }
        let revision = UUID().uuidString
        let endpoints = try selected.mapValues { try HTTPProxyEndpoint(host: $0.androidHost, port: $0.port) }
        let configuration = try JSONEncoder().encode(Configuration(revision: revision, apps: endpoints)).base64EncodedString()
        let start = try await shell("am start -W -n \(agent)/.ConfigureActivity --es config \(Self.shellQuote(configuration))")
        guard !start.contains("Error:"), !start.contains("Permission Denial") else {
            throw MandroidKitError.adb("Could not configure Android app proxies: \(start)")
        }
        struct Status: Decodable { let revision: String; let error: String; let active: Bool }
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let result = try await shell("content call --uri content://\(agent).status --method status")
            if let range = result.range(of: "status="),
               let encoded = result[range.upperBound...].split(whereSeparator: { $0 == "}" || $0 == "," || $0.isWhitespace }).first,
               let data = Data(base64Encoded: String(encoded)),
               let status = try? JSONDecoder().decode(Status.self, from: data), status.revision == revision {
                guard status.error.isEmpty else { throw MandroidKitError.adb(status.error) }
                guard status.active == !selected.isEmpty else { throw MandroidKitError.adb("Android app proxy did not become active") }
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw MandroidKitError.timeout("Android did not confirm app proxy settings")
    }
}
