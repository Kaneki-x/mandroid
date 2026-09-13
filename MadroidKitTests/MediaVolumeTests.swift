import Foundation
import Testing
@testable import MadroidKit

@Suite struct MediaVolumeTests {
    @Test func parsesAndroidOutput() throws {
        let volume = try #require(MediaVolume.parse("[V] volume is 5 in range [0..15]\n"))
        #expect(volume.percent == 33)
        #expect(volume.level(forPercent: 50) == 8)
        #expect(volume.level(forPercent: -10) == 0)
        #expect(volume.level(forPercent: 200) == 15)
    }
    @Test func supportsDifferentRanges() throws {
        let volume = try #require(MediaVolume.parse("[V] volume is 7 in range [2..12]"))
        #expect(volume.percent == 50)
        #expect(volume.level(forPercent: 0) == 2)
        #expect(volume.level(forPercent: 100) == 12)
    }
    @Test func rejectsInvalidResponses() {
        for value in ["Error", "volume is 2 in range [0..0]", "volume is 20 in range [0..15]"] {
            #expect(MediaVolume.parse(value) == nil)
        }
    }
    @Test func preservesGuestUntilExplicitlySet() throws {
        let name = "MediaVolumeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = RunnerSettings.load(from: defaults)
        #expect(settings.mediaVolumePercent == nil)
        settings.mediaVolumePercent = 0
        settings.save(to: defaults)
        #expect(RunnerSettings.load(from: defaults).mediaVolumePercent == 0)
        defaults.set(101, forKey: "mediaVolumePercent")
        #expect(RunnerSettings.load(from: defaults).mediaVolumePercent == nil)
    }
}
