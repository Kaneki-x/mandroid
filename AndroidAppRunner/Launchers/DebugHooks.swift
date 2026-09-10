#if DEBUG
import AppKit
import EmulatorKit

/// Debug-only automation entry points, reachable through
/// `open "androidrunner://debug/<command>?…"`. They exist so the integration
/// script can drive and inspect the real UI from a shell without Screen
/// Recording or Accessibility permissions.
///
/// - `debug/snapshot?dir=<path>` renders every window's content view to
///   `<path>/<title>.png` and writes `<path>/state.txt`
/// - `debug/click?pkg=<pkg>&x=<pt>&y=<pt>` synthesises a mouse click in that
///   app window's view coordinates (`pkg=device` for the device screen)
/// - `debug/drag?pkg=&x1=&y1=&x2=&y2=` synthesises a drag
/// - `debug/scroll?pkg=&x=&y=&dy=<pt>` synthesises trackpad scroll deltas
/// - `debug/type?pkg=&text=<text>` synthesises key presses for each character
/// - `debug/key?pkg=&code=<keyCode>[&cmd=1][&shift=1]` one key press
/// - `debug/resize?pkg=&w=&h=` resizes the window content
/// - `debug/close?pkg=` closes the window
/// - `debug/quit` terminates the app (exercises the shutdown path)
@MainActor
struct DebugHooks {
    let delegate: AppDelegate

    func handle(path: [String], query q: [String: String]) {
        guard let cmd = path.first else { return }
        switch cmd {
        case "snapshot": snapshot(dir: q["dir"] ?? NSTemporaryDirectory())
        case "click":
            guard let wc = controller(q["pkg"]), let x = Double(q["x"] ?? ""), let y = Double(q["y"] ?? "") else { return }
            synthesizeDrag(in: wc, from: CGPoint(x: x, y: y), to: CGPoint(x: x, y: y), steps: 0)
        case "drag":
            guard let wc = controller(q["pkg"]), let x1 = Double(q["x1"] ?? ""), let y1 = Double(q["y1"] ?? ""),
                  let x2 = Double(q["x2"] ?? ""), let y2 = Double(q["y2"] ?? "") else { return }
            synthesizeDrag(in: wc, from: CGPoint(x: x1, y: y1), to: CGPoint(x: x2, y: y2), steps: 12)
        case "scroll":
            guard let wc = controller(q["pkg"]), let x = Double(q["x"] ?? ""), let y = Double(q["y"] ?? ""),
                  let dy = Double(q["dy"] ?? "") else { return }
            synthesizeScroll(in: wc, at: CGPoint(x: x, y: y), dy: dy)
        case "type":
            guard let wc = controller(q["pkg"]), let text = q["text"] else { return }
            for ch in text { synthesizeKey(in: wc, characters: String(ch), keyCode: 0, flags: []) }
        case "key":
            guard let wc = controller(q["pkg"]), let code = UInt16(q["code"] ?? "") else { return }
            var flags: NSEvent.ModifierFlags = []
            if q["cmd"] == "1" { flags.insert(.command) }
            if q["shift"] == "1" { flags.insert(.shift) }
            synthesizeKey(in: wc, characters: q["chars"] ?? "", keyCode: code, flags: flags)
        case "resize":
            guard let wc = controller(q["pkg"]), let w = Double(q["w"] ?? ""), let h = Double(q["h"] ?? "") else { return }
            wc.window?.setContentSize(NSSize(width: w, height: h))
        case "close":
            controller(q["pkg"])?.window?.performClose(nil)
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func controller(_ pkg: String?) -> AppWindowController? {
        guard let pkg else { return nil }
        if pkg == "device" { return delegate.windows.deviceWindow }
        return delegate.windows.appWindows[pkg]
    }

    // MARK: Snapshot

    private func snapshot(dir: String) {
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var lines: [String] = ["state=\(delegate.coordinator.state)"]
        for window in NSApp.windows where window.isVisible {
            guard let view = window.contentView else { continue }
            let title = window.title.isEmpty ? "untitled-\(window.windowNumber)" : window.title
            let safe = title.replacingOccurrences(of: "/", with: "_")
            let scale = window.backingScaleFactor
            let size = view.bounds.size
            let px = (Int(size.width * scale), Int(size.height * scale))
            guard px.0 > 0, px.1 > 0,
                  let ctx = CGContext(data: nil, width: px.0, height: px.1, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { continue }
            ctx.scaleBy(x: scale, y: scale)
            if let layer = view.layer {
                // Layer tree renders top-down for flipped hosts; flip for CG.
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
                layer.render(in: ctx)
            }
            if let image = ctx.makeImage() {
                let rep = NSBitmapImageRep(cgImage: image)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: base.appendingPathComponent("\(safe).png"))
                }
            }
            lines.append("window=\(title) frame=\(NSStringFromRect(window.frame)) key=\(window.isKeyWindow)")
        }
        lines.append("sessions=\(delegate.coordinator.sessions.keys.sorted())")
        lines.append("packages=\(delegate.coordinator.installedPackages)")
        try? lines.joined(separator: "\n").write(to: base.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Synthetic events

    private func windowPoint(_ wc: AppWindowController, _ p: CGPoint) -> (NSWindow, NSPoint)? {
        guard let window = wc.window, let view = window.contentView else { return nil }
        // p is in the view's flipped coordinates (origin top-left, points).
        let inView = NSPoint(x: p.x, y: p.y)
        return (window, view.convert(inView, to: nil))
    }

    private func synthesizeDrag(in wc: AppWindowController, from a: CGPoint, to b: CGPoint, steps: Int) {
        guard let (window, start) = windowPoint(wc, a), let view = window.contentView as? FrameView else { return }
        window.makeKeyAndOrderFront(nil)
        func ev(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        if let e = ev(.leftMouseDown, start) { view.mouseDown(with: e) }
        Task { @MainActor in
            if steps > 0 {
                for i in 1...steps {
                    try? await Task.sleep(for: .milliseconds(16))
                    let p = CGPoint(x: a.x + (b.x - a.x) * Double(i) / Double(steps), y: a.y + (b.y - a.y) * Double(i) / Double(steps))
                    if let (_, wp) = windowPoint(wc, p), let e = ev(.leftMouseDragged, wp) { view.mouseDragged(with: e) }
                }
            } else {
                try? await Task.sleep(for: .milliseconds(60))
            }
            if let (_, wp) = windowPoint(wc, b), let e = ev(.leftMouseUp, wp) { view.mouseUp(with: e) }
        }
    }

    private func synthesizeScroll(in wc: AppWindowController, at p: CGPoint, dy: Double) {
        guard let (window, wp) = windowPoint(wc, p), let view = window.contentView as? FrameView else { return }
        // Build precise scroll events through CGEvent; deliver in 8 steps.
        Task { @MainActor in
            let steps = 8
            for i in 0..<steps {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                       wheel1: Int32(dy / Double(steps)), wheel2: 0, wheel3: 0) else { return }
                cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: i == 0 ? 1 : 2)  // began / changed
                let screen = window.convertPoint(toScreen: wp)
                let flipped = CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - screen.y)
                cg.location = flipped
                if let e = NSEvent(cgEvent: cg) { view.scrollWheel(with: e) }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func synthesizeKey(in wc: AppWindowController, characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let window = wc.window, let view = window.contentView as? FrameView else { return }
        window.makeKeyAndOrderFront(nil)
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, characters: characters,
                                       charactersIgnoringModifiers: characters.lowercased(), isARepeat: false, keyCode: keyCode) else { return }
        if flags.contains(.command) {
            _ = view.performKeyEquivalent(with: e)
        } else {
            view.keyDown(with: e)
        }
    }
}
#endif
