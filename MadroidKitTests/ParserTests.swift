import Foundation
import Testing
@testable import MadroidKit

@Suite struct DumpsysDisplayParserTests {
    @Test func builtInOnly() throws {
        let d = DumpsysDisplayParser.parse(try Fixtures.text("dumpsys-display-0only.txt"))
        #expect(d.count == 1)
        #expect(d[0].displayID == 0)
        #expect(d[0].uniqueID.hasPrefix("local:"))
        #expect(d[0].width == 1080 && d[0].height == 2400)
        #expect(d[0].densityDpi == 420)
        #expect(d[0].emulatorIndex == nil)
    }

    @Test func oneSecondary() throws {
        let d = DumpsysDisplayParser.parse(try Fixtures.text("dumpsys-display-1secondary.txt"))
        #expect(d.count == 2)
        let v = try #require(d.first { $0.displayID == 2 })
        #expect(v.uniqueID == "virtual:com.android.emulator.multidisplay:1234562")
        #expect(v.emulatorIndex == 1)
        #expect(v.width == 840 && v.height == 1800)
        #expect(v.densityDpi == 320)
        #expect(v.name == "Emulator 2D Display")
    }

    @Test func threeSecondaries() throws {
        let d = DumpsysDisplayParser.parse(try Fixtures.text("dumpsys-display-3secondary.txt"))
        #expect(d.map(\.displayID) == [0, 2, 3, 4])
        #expect(d.map(\.emulatorIndex) == [nil, 1, 2, 3])
        #expect(d[2].width == 842)
    }
}

@Suite struct PackageListParserTests {
    @Test func parsesAndSorts() {
        let out = PackageListParser.parse("package:com.b.app\npackage:com.a.app\n\nnoise\n")
        #expect(out == ["com.a.app", "com.b.app"])
    }
}

@Suite struct AVDConfigTests {
    @Test func rendersTemplate() {
        var c = AVDConfig(systemImagePath: "system-images;android-36.1;google_apis_playstore;arm64-v8a")
        c.name = "runner"
        let ini = c.renderConfigINI()
        #expect(ini.contains("image.sysdir.1=system-images/android-36.1/google_apis_playstore/arm64-v8a/\n"))
        #expect(ini.contains("PlayStore.enabled=true\n"))
        #expect(ini.contains("hw.cpu.arch=arm64\n"))
        #expect(ini.contains("target=android-36.1\n"))
        #expect(ini.contains("skin.path=_no_skin\n"))
        #expect(ini.contains("showDeviceFrame=no\n"))
        #expect(!ini.contains("hw.device.name"))
        #expect(!ini.contains("hw.display1"))
        let ptr = c.renderPointerINI(avdDirectory: URL(fileURLWithPath: "/x/avd/runner.avd"))
        #expect(ptr.contains("path=/x/avd/runner.avd\n"))
        #expect(ptr.contains("path.rel=avd/runner.avd\n"))
    }

    @Test func x86Image() {
        let c = AVDConfig(systemImagePath: "system-images;android-35;google_apis;x86_64")
        #expect(c.cpuArch == "x86_64")
        #expect(c.playStoreEnabled == false)
        #expect(c.renderConfigINI().contains("tag.display=Google APIs\n"))
    }

    @Test func stripPersistedDisplays() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("aar-\(UUID().uuidString)")
        let store = AVDStore(paths: SDKPaths(root: tmp))
        var c = AVDConfig(systemImagePath: "system-images;android-36.1;google_apis_playstore;arm64-v8a")
        c.name = "t"
        try store.write(c)
        let file = store.directory(for: "t").appendingPathComponent("config.ini")
        try (try String(contentsOf: file, encoding: .utf8) + "hw.display1.width = 840\nhw.display1.height = 1800\n").write(to: file, atomically: true, encoding: .utf8)
        try store.stripPersistedDisplays("t")
        #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("hw.display1"))
        try? FileManager.default.removeItem(at: tmp)
    }
}
