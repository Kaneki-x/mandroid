import Foundation
import Testing
@testable import MandroidKit

@Suite struct APKBadgingTests {
    @Test func parsesShadowsocks() throws {
        let b = try #require(APKBadging.parse(try Fixtures.text("aapt2-badging-shadowsocks.txt")))
        #expect(b.package == "com.github.shadowsocks")
        #expect(b.versionCode == 5030550)
        #expect(b.versionName == "5.3.5-nightly")
        #expect(b.label == "Shadowsocks")
        #expect(b.labels["zh-TW"] == "影梭")
        #expect(b.label(for: Locale(identifier: "zh_TW")) == "影梭")
        #expect(b.label(for: Locale(identifier: "en_US")) == "Shadowsocks")
        #expect(b.bestIconPath == "res/mipmap-anydpi-v26/ic_launcher.xml")
        #expect(b.launchableActivity == "com.github.shadowsocks.MainActivity")
        #expect(b.targetSdk == 36)
    }

    @Test func minimalOutput() throws {
        let text = """
        package: name='a.b' versionCode='7' versionName='1'
        application: label='Hello' icon='res/x.png'
        """
        let b = try #require(APKBadging.parse(text))
        #expect(b.label == "Hello")
        #expect(b.bestIconPath == "res/x.png")
        #expect(APKBadging.parse("garbage") == nil)
    }

    @Test func ignoresPseudoDensities() throws {
        let text = """
        package: name='a.b' versionCode='1' versionName='1'
        application-icon-160:'res/mdpi.png'
        application-icon-640:'res/xxxhdpi.png'
        application-icon-65534:'res/mdpi.png'
        """
        #expect(try #require(APKBadging.parse(text)).bestIconPath == "res/xxxhdpi.png")
    }
}

@Suite struct InstalledAppsTests {
    @Test func parsesVersionCodes() {
        let out = InstalledApps.parse("package:com.b versionCode:12\npackage:com.a versionCode:3\npackage:com.c\n")
        #expect(out.map(\.package) == ["com.a", "com.b", "com.c"])
        #expect(out.map(\.versionCode) == [3, 12, 0])
    }
}

@Suite struct TaskListParserTests {
    let sample = """
      RootTask id=33 bounds=[0,0][840,1800] displayId=2 userId=0
       configuration={...}
        taskId=33: com.android.camera2/com.android.camera.CameraLauncher bounds=[0,0][840,1800] userId=0 visible=true
      RootTask id=1 bounds=[0,0][1080,2400] displayId=0 userId=0
        taskId=2: com.google.android.apps.nexuslauncher/.NexusLauncherActivity bounds=[0,0][1080,2400]
    """
    @Test func displays() {
        #expect(TaskListParser.displaysWithTasks(sample) == [0, 2])
        #expect(TaskListParser.packages(onDisplay: 2, in: sample) == ["com.android.camera2"])
        #expect(TaskListParser.packages(onDisplay: 5, in: sample).isEmpty)
    }
}

@Suite struct AAPT2FetcherTests {
    @Test func picksNewestStable() throws {
        let v = AAPT2Fetcher.pickStable(fromMavenMetadata: try Fixtures.text("aapt2-maven-metadata.xml"))
        #expect(v == "9.4.0-15978811")
        #expect(AAPT2Fetcher.pickStable(fromMavenMetadata: "<versions><version>8.1.0-1</version><version>8.10.0-2</version><version>9.0.0-alpha01-3</version></versions>") == "8.10.0-2")
    }
}

@Suite struct IconExtractorTests {
    @Test func densityRanking() {
        #expect(IconExtractor.rank("res/mipmap-xxxhdpi-v4/ic_launcher.webp") > IconExtractor.rank("res/mipmap-xhdpi-v4/ic_launcher.webp"))
        #expect(IconExtractor.rank("res/mipmap-anydpi-v26/ic_launcher.xml") == 1)
    }
}

@Suite struct ClipboardEchoGuardTests {
    @Test func suppressesEchoBothWays() {
        var g = ClipboardEchoGuard()
        #expect(g.shouldSendToGuest("a"))
        g.noteSentToGuest("a")
        #expect(!g.shouldAcceptFromGuest("a"))      // guest echoes what we sent
        #expect(g.shouldAcceptFromGuest("b"))
        g.noteReceivedFromGuest("b")
        #expect(!g.shouldSendToGuest("b"))          // host echoes what came from the guest
        #expect(g.shouldSendToGuest("c"))
        #expect(!g.shouldSendToGuest(""))
    }
}
