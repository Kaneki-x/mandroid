import Foundation
import Testing
@testable import MandroidKit

@Suite struct DeviceProfileTests {
    @Test func defaultPreservesExistingTabletGeometry() {
        let settings = RunnerSettings()
        var config = AVDConfig(systemImagePath: "system-images;android-36.1;google_apis_playstore;arm64-v8a")
        let original = config
        settings.apply(to: &config)
        #expect(config.lcdWidth == original.lcdWidth)
        #expect(config.lcdHeight == original.lcdHeight)
        #expect(config.lcdDensity == original.lcdDensity)
    }

    @Test func customProfilePersistsAndRejectsCorruptPreferences() throws {
        let suite = "device-profile-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = RunnerSettings()
        settings.deviceProfile = .custom
        settings.customDeviceWidthDP = 600
        settings.customDeviceHeightDP = 1000
        settings.customDeviceDensity = 240
        settings.save(to: defaults)
        #expect(RunnerSettings.load(from: defaults) == settings)
        #expect(settings.deviceDisplay.widthPixels == 900)
        #expect(settings.deviceDisplay.heightPixels == 1500)
        defaults.set("missing-profile", forKey: "deviceProfile")
        defaults.set(Int.max, forKey: "customDeviceWidthDP")
        defaults.set(-1, forKey: "customDeviceHeightDP")
        defaults.set(0, forKey: "customDeviceDensity")
        let loaded = RunnerSettings.load(from: defaults)
        #expect(loaded.deviceProfile == .tablet)
        #expect(loaded.customDeviceWidthDP == 400)
        #expect(loaded.customDeviceHeightDP == 900)
        #expect(loaded.customDeviceDensity == 320)
        let bounded = DeviceDisplay(widthDP: Int.max, heightDP: Int.min, density: Int.max)
        #expect(bounded.widthPixels == 4800)
        #expect(bounded.heightPixels == 960)
    }

    @Test func profileSwitchColdBootsOnceAndPreservesUserdata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AVDStore(paths: SDKPaths(root: root))
        var config = AVDConfig(systemImagePath: "system-images;android-36.1;google_apis_playstore;arm64-v8a")
        var settings = RunnerSettings()
        settings.apply(to: &config)
        #expect(try !store.write(config))
        let data = store.directory(for: config.name).appendingPathComponent("userdata-qemu.img")
        let marker = Data("installed apps and user data".utf8)
        try marker.write(to: data)
        for profile in [DeviceProfile.phone, .compactPhone, .custom, .tablet] {
            settings.deviceProfile = profile
            settings.apply(to: &config)
            #expect(try store.write(config))
            #expect(try !store.write(config))
            #expect(try Data(contentsOf: data) == marker)
            let ini = try String(contentsOf: store.directory(for: config.name).appendingPathComponent("config.ini"), encoding: .utf8)
            #expect(ini.contains("hw.lcd.width=\(settings.deviceDisplay.widthPixels)\n"))
            #expect(ini.contains("hw.lcd.density=\(settings.deviceDisplay.density)\n"))
            #expect(config.systemImagePath == "system-images;android-36.1;google_apis_playstore;arm64-v8a")
        }
    }

    @Test func numericLaunchArgumentsConfigureCustomDisplay() throws {
        let suite = "device-profile-args-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.setVolatileDomain([
            "deviceProfile": "custom", "customDeviceWidthDP": "600",
            "customDeviceHeightDP": "1000", "customDeviceDensity": "240",
        ], forName: UserDefaults.argumentDomain)
        let display = RunnerSettings.load(from: defaults).deviceDisplay
        #expect(display.widthPixels == 900)
        #expect(display.heightPixels == 1500)
        #expect(display.density == 240)
    }

    @Test func restartDependsOnEffectiveProfile() {
        let running = RunnerSettings()
        var edited = running
        edited.customDeviceWidthDP = 600
        #expect(!edited.requiresRestart(comparedTo: running))
        edited.deviceProfile = .custom
        #expect(edited.requiresRestart(comparedTo: running))
        edited.deviceProfile = .tablet
        #expect(!edited.requiresRestart(comparedTo: running))
        edited.deviceProfile = .phone
        #expect(edited.requiresRestart(comparedTo: running))
    }
}
