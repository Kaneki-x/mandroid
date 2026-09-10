import Foundation
import Testing
@testable import MadroidKit

@Suite struct CoordinateMapperTests {
    @Test func exactFit() {
        let m = CoordinateMapper(viewWidth: 420, viewHeight: 900, displayWidth: 840, displayHeight: 1800)
        #expect(m.toDisplay(x: 0, y: 0) == (0, 0))
        #expect(m.toDisplay(x: 210, y: 450) == (420, 900))
        #expect(m.toDisplay(x: 420, y: 900) == (839, 1799))
    }

    @Test func letterboxedWideWindow() {
        // Display 840x1800 drawn into 1000x900 view → scale 0.5, offset x=(1000-420)/2=290
        let m = CoordinateMapper(viewWidth: 1000, viewHeight: 900, displayWidth: 840, displayHeight: 1800)
        #expect(m.fit.scale == 0.5)
        #expect(m.fit.offsetX == 290)
        #expect(m.toDisplay(x: 290, y: 0) == (0, 0))
        #expect(m.toDisplay(x: 100, y: 0).x == 0)          // clamped in the bar
        #expect(m.toDisplay(x: 710, y: 900) == (839, 1799))
        #expect(m.deltaToDisplay(dx: 10, dy: -5) == (20, -10))
    }
}

@Suite struct KeyMapTests {
    func k(_ code: UInt16, _ ch: String, cmd: Bool = false, ctrl: Bool = false, shift: Bool = false, opt: Bool = false) -> KeyInput {
        KeyInput(keyCode: code, characters: ch, charactersIgnoringModifiers: ch.lowercased(), command: cmd, control: ctrl, option: opt, shift: shift)
    }

    @Test func printable() {
        #expect(KeyMap.action(for: k(0, "a")) == .text("a"))
        #expect(KeyMap.action(for: k(0, "A", shift: true)) == .text("A"))
        #expect(KeyMap.action(for: k(49, " ")) == .text(" "))
        #expect(KeyMap.action(for: k(31, "ø", opt: true)) == .text("ø"))
    }

    @Test func specials() {
        #expect(KeyMap.action(for: k(36, "\r")) == .key("Enter"))
        #expect(KeyMap.action(for: k(51, "\u{7f}")) == .key("Backspace"))
        #expect(KeyMap.action(for: k(53, "\u{1b}")) == .key("GoBack"))
        #expect(KeyMap.action(for: k(126, "\u{F700}")) == .key("ArrowUp"))
        #expect(KeyMap.action(for: k(126, "\u{F700}", shift: true)) == .chord(["Shift", "ArrowUp"]))
        #expect(KeyMap.action(for: k(122, "\u{F704}")) == .ignore)   // F1
    }

    @Test func commandShortcuts() {
        #expect(KeyMap.action(for: k(33, "[", cmd: true)) == .key("GoBack"))
        #expect(KeyMap.action(for: k(4, "H", cmd: true, shift: true)) == .key("GoHome"))
        #expect(KeyMap.action(for: k(8, "c", cmd: true)) == .chord(["Control", "c"]))
        #expect(KeyMap.action(for: k(9, "v", cmd: true)) == .chord(["Control", "v"]))
        #expect(KeyMap.action(for: k(6, "Z", cmd: true, shift: true)) == .chord(["Control", "Shift", "z"]))
        #expect(KeyMap.action(for: k(13, "w", cmd: true)) == .ignore)   // menu owns ⌘W
        #expect(KeyMap.action(for: k(12, "q", cmd: true)) == .ignore)
    }
}

@Suite struct ScrollGestureTests {
    @Test func downMoveUp() {
        var g = ScrollGesture(displayWidth: 800, displayHeight: 1600)
        let first = g.scroll(atX: 400, y: 800, dx: 0, dy: -30)
        #expect(first == [.down(x: 400, y: 800), .move(x: 400, y: 770)])
        #expect(g.scroll(atX: 999, y: 999, dx: 0, dy: -30) == [.move(x: 400, y: 740)])
        #expect(g.end() == .up(x: 400, y: 740))
        #expect(g.end() == nil)
    }

    @Test func liftsAtEdge() {
        var g = ScrollGesture(displayWidth: 800, displayHeight: 1600)
        let out = g.scroll(atX: 400, y: 20, dx: 0, dy: -50)
        #expect(out.last == .up(x: 400, y: 0))
        #expect(!g.isActive)
    }
}

@Suite struct DisplaySlotPoolTests {
    @Test func sanitizeLimits() {
        #expect(DisplaySlotPool.sanitize(width: 840, height: 1800, dpi: 320) == (840, 1800, 320))
        // 320 dp minimum at 320 dpi = 640 px
        #expect(DisplaySlotPool.sanitize(width: 100, height: 100, dpi: 320) == (640, 640, 320))
        // dpi clamps to 640, where 320 dp = 1280 px; odd widths round down.
        #expect(DisplaySlotPool.sanitize(width: 1281, height: 9000, dpi: 1000) == (1280, 7680, 640))
    }
}

@Suite struct RunnerSettingsTests {
    @Test func landscapeDefault() {
        var s = RunnerSettings()
        #expect(s.landscapeByDefault)
        let l = s.defaultWindowSize(screenWidth: 1440, screenHeight: 900)
        #expect(l.width > l.height)
        #expect(abs(l.width / l.height - 1.6) < 0.01)
        s.landscapeByDefault = false
        let p = s.defaultWindowSize(screenWidth: 1440, screenHeight: 900)
        #expect(p.height > p.width)
        // Clamps to the screen.
        let small = RunnerSettings().defaultWindowSize(screenWidth: 800, screenHeight: 600)
        #expect(small.width <= 760 && small.height <= 560)
    }
}


@Suite struct DownloadMirrorTests {
    @Test func autoOutsideChinaUsesGoogleOnly() {
        #expect(DownloadMirror.order(for: .auto, regionCode: "US", timeZoneID: "America/Los_Angeles") == [.google])
        #expect(DownloadMirror.order(for: .auto, regionCode: "TW", timeZoneID: "Asia/Taipei") == [.google])
        #expect(DownloadMirror.order(for: .auto, regionCode: nil, timeZoneID: "Europe/Berlin") == [.google])
    }

    @Test func autoInChinaPrefersMirrorWithGoogleFallback() {
        #expect(DownloadMirror.order(for: .auto, regionCode: "CN", timeZoneID: "America/New_York") == [.china, .google])
        #expect(DownloadMirror.order(for: .auto, regionCode: "US", timeZoneID: "Asia/Shanghai") == [.china, .google])
    }

    @Test func explicitChoices() {
        #expect(DownloadMirror.order(for: .google, regionCode: "CN", timeZoneID: "Asia/Shanghai") == [.google])
        #expect(DownloadMirror.order(for: .china, regionCode: "US", timeZoneID: "UTC") == [.china, .google])
    }

    @Test func rewriteKeepsPathOnOtherMirror() {
        let sysimg = URL(string: "https://mirrors.cloud.tencent.com/AndroidSDK/sys-img/google_apis_playstore/arm64-v8a-36.1_r04.zip")!
        #expect(DownloadMirror.china.rewrite(sysimg, to: .google)?.absoluteString
                == "https://dl.google.com/android/repository/sys-img/google_apis_playstore/arm64-v8a-36.1_r04.zip")
        let jar = DownloadMirror.google.aapt2Base.appendingPathComponent("9.4.0-15978811/aapt2-9.4.0-15978811-osx.jar")
        #expect(DownloadMirror.google.rewrite(jar, to: .china)?.absoluteString
                == "https://maven.aliyun.com/repository/google/com/android/tools/build/aapt2/9.4.0-15978811/aapt2-9.4.0-15978811-osx.jar")
        #expect(DownloadMirror.google.rewrite(URL(string: "https://example.com/x.zip")!, to: .china) == nil)
    }

    @Test func manifestURLs() {
        #expect(DownloadMirror.china.repositoryManifestURL.absoluteString == "https://mirrors.cloud.tencent.com/AndroidSDK/repository2-3.xml")
        #expect(DownloadMirror.google.systemImageManifestURL(tag: "google_apis_playstore").absoluteString
                == "https://dl.google.com/android/repository/sys-img/google_apis_playstore/sys-img2-3.xml")
    }
}
