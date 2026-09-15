#if DEBUG
import AppKit
import AVFoundation
import MandroidKit

/// Debug-only screencast recorder that works without Screen Recording
/// permission. It composites Mandroid's own window layers onto a canvas the
/// size of the main screen and encodes it with AVAssetWriter.
///
/// `mandroid://debug/record?secs=30&fps=15&file=/path/out.mp4&scale=1`
@MainActor
final class DebugRecorder {
    static var current: DebugRecorder?

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let fps: Int
    private let scale: CGFloat
    private let screen: NSRect
    private let size: (w: Int, h: Int)
    private var frame = 0
    private var timer: Timer?
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var finishTask: Task<Void, Never>?
    private let deadline: Date
    private let file: URL

    init?(file: URL, seconds: Double, fps: Int, scale: CGFloat) {
        guard let main = NSScreen.main, seconds.isFinite, seconds > 0, seconds <= 3600,
              (1...120).contains(fps), scale.isFinite, scale > 0, scale <= 4 else { return nil }
        self.screen = main.frame
        self.fps = fps
        self.scale = scale
        self.size = (Int(screen.width * scale) & ~1, Int(screen.height * scale) & ~1)
        guard size.w > 0, size.h > 0 else { return nil }
        self.file = file
        self.deadline = Date().addingTimeInterval(seconds)
        try? FileManager.default.removeItem(at: file)
        guard let writer = try? AVAssetWriter(outputURL: file, fileType: .mp4) else { return nil }
        self.writer = writer
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.w,
            AVVideoHeightKey: size.h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.w,
            kCVPixelBufferHeightKey as String: size.h,
        ])
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
    }

    func start() {
        Log.file("record: start \(size.w)x\(size.h) @\(fps) fps → \(file.path)")
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() async {
        if let finishTask { await finishTask.value; return }
        timer?.invalidate(); timer = nil
        input.markAsFinished()
        let task = Task { @MainActor in
            await writer.finishWriting()
            if writer.status == .completed {
                Log.file("record: finished \(frame) frames → \(file.path)")
            } else {
                Log.file("record: failed \(writer.error?.localizedDescription ?? "no video frames")")
            }
            if DebugRecorder.current === self { DebugRecorder.current = nil }
        }
        finishTask = task
        await task.value
    }

    private func tick() {
        guard finishTask == nil else { return }
        if Date() >= deadline {
            timer?.invalidate(); timer = nil
            Task { await stop() }
            return
        }
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buffer = pb else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: size.w, height: size.h,
                               bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            draw(into: ctx)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        if adaptor.append(buffer, withPresentationTime: CMTime(seconds: elapsed, preferredTimescale: 60_000)) {
            frame += 1
        } else {
            timer?.invalidate(); timer = nil
            Task { await stop() }
        }
    }

    /// Desktop-like backdrop, then every visible Mandroid window back to front
    /// at its on-screen position.
    private func draw(into ctx: CGContext) {
        ctx.scaleBy(x: scale, y: scale)
        let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: [CGColor(red: 0.16, green: 0.20, blue: 0.30, alpha: 1),
                                     CGColor(red: 0.07, green: 0.08, blue: 0.13, alpha: 1)] as CFArray,
                            locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: screen.height), end: CGPoint(x: screen.width, y: 0), options: [])
        for window in NSApp.orderedWindows.reversed() where window.isVisible && window.alphaValue > 0 {
            guard let content = window.contentView, let frameView = content.superview ?? Optional(content),
                  let layer = frameView.layer else { continue }
            let f = window.frame
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: CGColor(gray: 0, alpha: 0.5))
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.addPath(CGPath(roundedRect: CGRect(x: f.minX - screen.minX, y: f.minY - screen.minY, width: f.width, height: f.height),
                               cornerWidth: 11, cornerHeight: 11, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: CGRect(x: f.minX - screen.minX, y: f.minY - screen.minY, width: f.width, height: f.height),
                               cornerWidth: 11, cornerHeight: 11, transform: nil))
            ctx.clip()
            ctx.translateBy(x: f.minX - screen.minX, y: f.minY - screen.minY)
            // The window's frame layer is not flipped, so it renders directly
            // into CG's bottom-up space.
            layer.render(in: ctx)
            ctx.restoreGState()
        }
    }
}
#endif
