import Foundation
import Testing
@testable import MandroidKit

@Suite struct AppMigrationTests {
    private func temporarySupport() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func movesMostRecentInstallationAndPreservesContents() throws {
        let root = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in AppMigration.legacyNames {
            let dir = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(name.utf8).write(to: dir.appendingPathComponent("userdata.img"))
        }
        #expect(try AppMigration.migrateData(in: root)?.lastPathComponent == "Madroid")
        #expect(try Data(contentsOf: root.appendingPathComponent("Mandroid/userdata.img")) == Data("Madroid".utf8))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("AndroidAppRunner/userdata.img").path))
        #expect(try AppMigration.migrateData(in: root) == nil)
    }

    @Test func upgradesOriginalAppName() throws {
        let root = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("AndroidAppRunner"), withIntermediateDirectories: true)
        #expect(try AppMigration.migrateData(in: root)?.lastPathComponent == "AndroidAppRunner")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Mandroid").path))
    }

    @Test func neverOverwritesExistingDestination() throws {
        let root = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Mandroid", "Madroid"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        #expect(try AppMigration.migrateData(in: root) == nil)
        #expect(try Data(contentsOf: root.appendingPathComponent("Mandroid")) == Data("Mandroid".utf8))
        #expect(try Data(contentsOf: root.appendingPathComponent("Madroid")) == Data("Madroid".utf8))
    }

    @Test func freshInstallHasNothingToMigrate() throws {
        let root = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try AppMigration.migrateData(in: root) == nil)
    }

    @Test func preferencesPreserveNewValuesAndMigrateOnlyOnce() throws {
        let prefix = "mandroid-migration-test-\(UUID().uuidString)"
        let domains = [prefix + "-new", prefix + "-recent", prefix + "-old"]
        let defaults = try #require(UserDefaults(suiteName: domains[0]))
        defer { for domain in domains { defaults.removePersistentDomain(forName: domain) } }
        defaults.setPersistentDomain(["ramMB": 8192], forName: domains[0])
        defaults.setPersistentDomain(["ramMB": 4096, "cores": 6, "dataRoot": "/old", "uiTestControlDirectory": "/test"], forName: domains[1])
        defaults.setPersistentDomain(["cores": 2, "landscapeByDefault": false], forName: domains[2])
        AppMigration.migratePreferences(defaults, destination: domains[0], sources: Array(domains.dropFirst()))
        #expect(defaults.integer(forKey: "ramMB") == 8192)
        #expect(defaults.integer(forKey: "cores") == 6)
        #expect(defaults.object(forKey: "landscapeByDefault") as? Bool == false)
        #expect(defaults.object(forKey: "dataRoot") == nil)
        #expect(defaults.object(forKey: "uiTestControlDirectory") == nil)
        defaults.removeObject(forKey: "cores")
        AppMigration.migratePreferences(defaults, destination: domains[0], sources: Array(domains.dropFirst()))
        #expect(defaults.object(forKey: "cores") == nil)
    }
}

@Suite @MainActor struct RenamedLauncherTests {
    @Test func oldStubsAreRewrittenWithNewScheme() throws {
        for marker in LauncherStubBuilder.legacyMarkers {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let app = AppInfo(package: "com.example.app", label: "Example", versionCode: 1,
                              versionName: "1", launcherComponent: nil, iconFile: nil)
            LauncherStubBuilder.sync([app], at: dir)
            let bundle = try #require(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
            let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
            let plist = try #require(NSMutableDictionary(contentsOf: plistURL))
            plist.removeObject(forKey: LauncherStubBuilder.marker)
            plist[marker] = true
            #expect(plist.write(to: plistURL, atomically: true))
            let executable = bundle.appendingPathComponent("Contents/MacOS/launch")
            try "old launcher".write(to: executable, atomically: true, encoding: .utf8)
            LauncherStubBuilder.sync([app], at: dir)
            #expect(try String(contentsOf: executable, encoding: .utf8).contains("mandroid://launch/com.example.app"))
            let updated = try #require(NSDictionary(contentsOf: plistURL))
            #expect(updated[LauncherStubBuilder.marker] as? Bool == true)
            #expect(updated["CFBundleIdentifier"] as? String == "io.github.madeye.mandroid.stub.com.example.app")
        }
    }
}
