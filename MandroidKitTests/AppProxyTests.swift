import Foundation
import Testing
@testable import MandroidKit

@Suite struct AppProxyTests {
    @Test func validatesAndNormalizesEndpoints() throws {
        #expect(try HTTPProxyEndpoint(host: " LOCALHOST ", port: 8080).androidHost == "10.0.2.2")
        #expect(try HTTPProxyEndpoint(host: "[::1]", port: 8080).androidHost == "10.0.2.2")
        #expect(try HTTPProxyEndpoint(host: "[2001:db8::1]", port: 3128).host == "2001:db8::1")
        #expect(try HTTPProxyEndpoint(host: "proxy.example", port: 65535).androidHost == "proxy.example")
        for host in ["", "host/path", "http://proxy", "host;echo", "two hosts", "user@host"] {
            #expect(throws: (any Error).self) { try HTTPProxyEndpoint(host: host, port: 8080) }
        }
        for port in [0, -1, 65536] {
            #expect(throws: (any Error).self) { try HTTPProxyEndpoint(host: "localhost", port: port) }
        }
    }

    @Test func eachAppKeepsItsOwnProxyAcrossReloadAndRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try AppProxyStore.load(at: root).isEmpty)
        let a = try HTTPProxyEndpoint(host: "localhost", port: 8081)
        let b = try HTTPProxyEndpoint(host: "proxy.example", port: 8082)
        try AppProxyStore.save(["com.example.a": a, "com.example.b": b], at: root)
        var saved = try AppProxyStore.load(at: root)
        #expect(saved["com.example.a"] == a)
        #expect(saved["com.example.b"] == b)
        saved["com.example.a"] = nil
        try AppProxyStore.save(saved, at: root)
        #expect(try AppProxyStore.load(at: root) == ["com.example.b": b])
    }

    @Test func invalidSavedEndpointsAreNotSilentlyAccepted() throws {
        let data = Data(#"{"com.example.app":{"host":"localhost","port":0}}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode([String: HTTPProxyEndpoint].self, from: data) }
    }

    @Test func internalHelperIsNotShownAsAnInstalledUserApp() {
        let apps = InstalledApps.parse("package:io.github.madeye.mandroid.proxy versionCode:1\npackage:com.example.app versionCode:2")
        #expect(apps.map(\.package) == ["com.example.app"])
    }
}
