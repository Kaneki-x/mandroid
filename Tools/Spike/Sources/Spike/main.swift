import AppKit
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf

typealias EC = Android_Emulation_Control_EmulatorController
typealias Client = EC.Client<HTTP2ClientTransport.Posix>

let port = Int(ProcessInfo.processInfo.environment["GRPC_PORT"] ?? "8554")!
let bigResponse: CallOptions = { var o = CallOptions.defaults; o.maxResponseMessageBytes = 64 << 20; o.maxRequestMessageBytes = 64 << 20; return o }()

func withClient<T: Sendable>(_ body: @Sendable @escaping (Client) async throws -> T) async throws -> T {
    let transport = try HTTP2ClientTransport.Posix(
        target: .ipv4(host: "127.0.0.1", port: port),
        transportSecurity: .plaintext)
    return try await withGRPCClient(transport: transport) { grpc in
        try await body(Client(wrapping: grpc))
    }
}

func adb(_ args: String...) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/Volumes/DATA/workspace/android/platform-tools/adb")
    p.arguments = args
    let out = Pipe(); p.standardOutput = out; p.standardError = out
    try! p.run(); p.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

func now() -> Double { Date().timeIntervalSince1970 }

func savePNG(_ img: Android_Emulation_Control_Image, to path: String) {
    let w = Int(img.format.width), h = Int(img.format.height)
    let data = img.image as NSData
    guard data.length >= w * h * 4 else { print("short frame \(data.length) < \(w*h*4)"); return }
    let cs = CGColorSpaceCreateDeviceRGB()
    let provider = CGDataProvider(data: data)!
    let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                     space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(w)x\(h) bytes=\(data.length) seq=\(img.seq)")
}

func touch(_ client: Client, display: Int, x: Int, y: Int, id: Int = 0, pressure: Int) async throws {
    var t = Android_Emulation_Control_Touch()
    t.x = Int32(x); t.y = Int32(y); t.identifier = Int32(id); t.pressure = Int32(pressure)
    var te = Android_Emulation_Control_TouchEvent(); te.touches = [t]; te.display = Int32(display)
    _ = try await client.sendTouch(te)
}

let args = CommandLine.arguments.dropFirst()
guard let cmd = args.first else {
    print("""
    usage: spike <cmd> ...
      status
      displays
      set <id:w:h:dpi:flags>...          (full set, display 0 implied)
      shot <display> <w> <h> <out.png>
      fps <display> <w> <h> <seconds>
      tap <display> <x> <y>
      swipe <display> <x1> <y1> <x2> <y2> [steps]
      nudge <display> <x> <y>            (MouseEvent buttons=0)
      key <text>                          (sendKey keypress text)
      keyname <name>                      (sendKey keydown/up key=name)
      wheel <display> <dy>
      mmap <display> <w> <h> <path> <seconds>
      window <display> <w> <h>            (live AppKit window; taps forwarded)
      notify <seconds>
    """)
    exit(1)
}
let a = Array(args.dropFirst())

func run() async throws {
    switch cmd {
    case "status":
        try await withClient { c in
            let s = try await c.getStatus(Google_Protobuf_Empty())
            print("version=\(s.version) uptime=\(s.uptime) booted=\(s.booted)")
            print(s.hardwareConfig.entry.filter { $0.key.hasPrefix("hw.lcd") || $0.key.contains("display") }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
        }
    case "displays":
        try await withClient { c in
            let d = try await c.getDisplayConfigurations(Google_Protobuf_Empty())
            print("maxDisplays=\(d.maxDisplays) userConfigurable=\(d.userConfigurable)")
            for x in d.displays { print("  display=\(x.display) \(x.width)x\(x.height) dpi=\(x.dpi) flags=\(x.flags)") }
        }
    case "set":
        try await withClient { c in
            var req = Android_Emulation_Control_DisplayConfigurations()
            for spec in a {
                let p = spec.split(separator: ":").map { UInt32($0)! }
                var d = Android_Emulation_Control_DisplayConfiguration()
                d.display = p[0]; d.width = p[1]; d.height = p[2]; d.dpi = p[3]; d.flags = p[4]
                req.displays.append(d)
            }
            let t0 = now()
            let d = try await c.setDisplayConfigurations(req)
            print("set took \(Int((now()-t0)*1000))ms maxDisplays=\(d.maxDisplays) userConfigurable=\(d.userConfigurable)")
            for x in d.displays { print("  display=\(x.display) \(x.width)x\(x.height) dpi=\(x.dpi) flags=\(x.flags)") }
        }
    case "shot":
        try await withClient { c in
            var f = Android_Emulation_Control_ImageFormat()
            f.format = .rgba8888; f.display = UInt32(a[0])!; f.width = UInt32(a[1])!; f.height = UInt32(a[2])!
            let img = try await c.getScreenshot(f, options: bigResponse)
            savePNG(img, to: a[3])
        }
    case "fps":
        try await withClient { c in
            var f = Android_Emulation_Control_ImageFormat()
            f.format = .rgba8888; f.display = UInt32(a[0])!; f.width = UInt32(a[1])!; f.height = UInt32(a[2])!
            let secs = Double(a[3])!
            try await c.streamScreenshot(f, options: bigResponse) { resp in
                var n = 0, bytes = 0, firstSeq: UInt32 = 0, lastSeq: UInt32 = 0
                let t0 = now(); var tFirst = 0.0
                for try await img in resp.messages {
                    if n == 0 { tFirst = now(); firstSeq = img.seq; print("first frame after \(Int((tFirst-t0)*1000))ms \(img.format.width)x\(img.format.height) bytes=\(img.image.count)") }
                    n += 1; bytes += img.image.count; lastSeq = img.seq
                    if now() - t0 > secs { break }
                }
                let dt = now() - tFirst
                print(String(format: "frames=%d in %.1fs => %.1f fps, %.1f MB/s, seq %d..%d", n, dt, Double(n-1)/dt, Double(bytes)/dt/1e6, firstSeq, lastSeq))
            }
        }
    case "tap":
        try await withClient { c in
            let d = Int(a[0])!, x = Int(a[1])!, y = Int(a[2])!
            try await touch(c, display: d, x: x, y: y, pressure: 1000)
            try await Task.sleep(for: .milliseconds(60))
            try await touch(c, display: d, x: x, y: y, pressure: 0)
            print("tapped display \(d) at \(x),\(y)")
        }
    case "swipe":
        try await withClient { c in
            let d = Int(a[0])!, x1 = Int(a[1])!, y1 = Int(a[2])!, x2 = Int(a[3])!, y2 = Int(a[4])!
            let steps = a.count > 5 ? Int(a[5])! : 20
            try await c.streamInputEvent { writer in
                func ev(_ x: Int, _ y: Int, _ p: Int) -> Android_Emulation_Control_InputEvent {
                    var t = Android_Emulation_Control_Touch(); t.x = Int32(x); t.y = Int32(y); t.pressure = Int32(p)
                    var te = Android_Emulation_Control_TouchEvent(); te.touches = [t]; te.display = Int32(d)
                    var e = Android_Emulation_Control_InputEvent(); e.touchEvent = te; return e
                }
                try await writer.write(ev(x1, y1, 1000))
                for i in 1...steps {
                    try await Task.sleep(for: .milliseconds(8))
                    try await writer.write(ev(x1 + (x2-x1)*i/steps, y1 + (y2-y1)*i/steps, 1000))
                }
                try await writer.write(ev(x2, y2, 0))
            } onResponse: { _ in }
            print("swiped")
        }
    case "scrollloop":
        try await withClient { c in
            let d = Int(a[0])!, secs = Double(a[1])!
            try await c.streamInputEvent { writer in
                func ev(_ x: Int, _ y: Int, _ p: Int) -> Android_Emulation_Control_InputEvent {
                    var t = Android_Emulation_Control_Touch(); t.x = Int32(x); t.y = Int32(y); t.pressure = Int32(p)
                    var te = Android_Emulation_Control_TouchEvent(); te.touches = [t]; te.display = Int32(d)
                    var e = Android_Emulation_Control_InputEvent(); e.touchEvent = te; return e
                }
                let t0 = now(); var up = true
                while now() - t0 < secs {
                    let (y1, y2) = up ? (1500, 400) : (400, 1500)
                    try await writer.write(ev(400, y1, 1000))
                    for i in 1...40 {
                        try await Task.sleep(for: .milliseconds(16))
                        try await writer.write(ev(400, y1 + (y2-y1)*i/40, 1000))
                    }
                    try await writer.write(ev(400, y2, 0))
                    try await Task.sleep(for: .milliseconds(100))
                    up.toggle()
                }
            } onResponse: { _ in }
        }
    case "nudge":
        try await withClient { c in
            var m = Android_Emulation_Control_MouseEvent()
            m.display = Int32(a[0])!; m.x = Int32(a[1])!; m.y = Int32(a[2])!; m.buttons = 0
            _ = try await c.sendMouse(m)
            print("nudged")
        }
    case "key":
        try await withClient { c in
            var k = Android_Emulation_Control_KeyboardEvent()
            k.eventType = .keypress; k.text = a[0]
            _ = try await c.sendKey(k); print("sent text")
        }
    case "keyname":
        try await withClient { c in
            var k = Android_Emulation_Control_KeyboardEvent()
            k.eventType = .keydown; k.key = a[0]
            _ = try await c.sendKey(k)
            k.eventType = .keyup
            _ = try await c.sendKey(k); print("sent key \(a[0])")
        }
    case "wheel":
        try await withClient { c in
            var w = Android_Emulation_Control_WheelEvent()
            w.display = Int32(a[0])!; w.dy = Int32(a[1])!
            try await c.injectWheel { writer in try await writer.write(w) } onResponse: { _ in }
            print("wheel sent")
        }
    case "mmap":
        try await withClient { c in
            var f = Android_Emulation_Control_ImageFormat()
            f.format = .rgba8888; f.display = UInt32(a[0])!; f.width = UInt32(a[1])!; f.height = UInt32(a[2])!
            f.transport.channel = .mmap; f.transport.handle = a[3]
            let secs = Double(a[4])!
            try await c.streamScreenshot(f, options: bigResponse) { resp in
                var n = 0; let t0 = now()
                for try await img in resp.messages {
                    if n < 3 { print("frame seq=\(img.seq) \(img.format.width)x\(img.format.height) inline bytes=\(img.image.count) handle=\(img.format.transport.handle) ts=\(img.timestampUs)")
                        let path = a[3].replacingOccurrences(of: "file://", with: "")
                        if let d = FileManager.default.contents(atPath: path) {
                            print("  file size=\(d.count) first bytes=\(Array(d.prefix(16)))")
                        } else { print("  file missing at \(path)") }
                    }
                    n += 1
                    if now() - t0 > secs { break }
                }
                print("mmap frames=\(n) in \(secs)s")
            }
        }
    case "notify":
        try await withClient { c in
            let secs = Double(a[0])!
            try await c.streamNotification(Google_Protobuf_Empty()) { resp in
                let t0 = now()
                for try await n in resp.messages {
                    print("notification: \(n)")
                    if now() - t0 > secs { break }
                }
            }
        }
    case "window":
        try await runWindow(display: Int(a[0])!, width: Int(a[1])!, height: Int(a[2])!)
    default:
        print("unknown \(cmd)"); exit(1)
    }
}

// MARK: - Live window

final class FrameView: NSView {
    var display = 0
    var onTouch: ((Int, Int, Int) -> Void)?
    var pixelW = 1, pixelH = 1
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    func map(_ e: NSEvent) -> (Int, Int) {
        let p = convert(e.locationInWindow, from: nil)
        return (Int(p.x / bounds.width * CGFloat(pixelW)), Int(p.y / bounds.height * CGFloat(pixelH)))
    }
    override func mouseDown(with e: NSEvent) { let (x, y) = map(e); onTouch?(x, y, 1000) }
    override func mouseDragged(with e: NSEvent) { let (x, y) = map(e); onTouch?(x, y, 1000) }
    override func mouseUp(with e: NSEvent) { let (x, y) = map(e); onTouch?(x, y, 0) }
}

@MainActor
func runWindow(display: Int, width: Int, height: Int) async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width / 2, height: height / 2),
                       styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    win.title = "display \(display)"
    let view = FrameView(frame: win.contentView!.bounds)
    view.autoresizingMask = [.width, .height]
    view.wantsLayer = true
    view.pixelW = width; view.pixelH = height
    win.contentView = view
    win.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    let transport = try HTTP2ClientTransport.Posix(target: .ipv4(host: "127.0.0.1", port: port), transportSecurity: .plaintext)
    let grpc = GRPCClient(transport: transport)
    Task { try await grpc.runConnections() }
    let client = Client(wrapping: grpc)

    // touch channel
    let (stream, cont) = AsyncStream<Android_Emulation_Control_InputEvent>.makeStream()
    Task {
        try await client.streamInputEvent { writer in
            for await e in stream { try await writer.write(e) }
        } onResponse: { _ in }
    }
    view.onTouch = { x, y, p in
        var t = Android_Emulation_Control_Touch(); t.x = Int32(x); t.y = Int32(y); t.pressure = Int32(p)
        var te = Android_Emulation_Control_TouchEvent(); te.touches = [t]; te.display = Int32(display)
        var e = Android_Emulation_Control_InputEvent(); e.touchEvent = te
        cont.yield(e)
    }
    Task {
        var f = Android_Emulation_Control_ImageFormat()
        f.format = .rgba8888; f.display = UInt32(display); f.width = UInt32(width); f.height = UInt32(height)
        try await client.streamScreenshot(f, options: bigResponse) { resp in
            var n = 0; var t0 = now()
            for try await img in resp.messages {
                let w = Int(img.format.width), h = Int(img.format.height)
                let data = img.image as NSData
                guard data.length >= w*h*4 else { continue }
                let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w*4,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                 provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                await MainActor.run { view.layer?.contents = cg }
                n += 1
                if now() - t0 > 5 { print(String(format: "%.1f fps", Double(n)/(now()-t0))); n = 0; t0 = now() }
            }
        }
    }
    app.run()
}

if cmd == "window" {
    Task { try await run() }
    RunLoop.main.run()
} else {
    let sem = DispatchSemaphore(value: 0)
    Task {
        do { try await run() } catch { print("error: \(error)") }
        sem.signal()
    }
    sem.wait()
}
