#if DEBUG
import AppKit
import CoreGraphics
import MandroidKit
import ScreenCaptureKit

/// Debug-only real screen recording of Mandroid's windows with
/// ScreenCaptureKit (needs the Screen Recording permission, granted to
/// Mandroid itself). `mandroid://debug/screenperm` asks for the permission;
/// `mandroid://debug/record` uses this recorder when the permission is
/// present and falls back to `DebugRecorder` (window compositing) otherwise.
@MainActor
final class DebugScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    static var current: DebugScreenRecorder?

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        let granted = CGRequestScreenCaptureAccess()
        Log.file("screenperm: request → \(granted ? "granted" : "not granted (relaunch after enabling in System Settings)")")
    }

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private let file: URL
    private var stopTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var recordingFinished = false
    private var recordingWaiter: CheckedContinuation<Void, Never>?

    init(file: URL) { self.file = file }

    func start(seconds: Double, fps: Int, allWindows: Bool) async throws {
        guard seconds.isFinite, seconds > 0, seconds <= 3600, (1...120).contains(fps) else {
            throw MandroidKitError.emulator("invalid recording duration or frame rate")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw MandroidKitError.emulator("no display to record")
        }
        let filter: SCContentFilter
        if allWindows {
            filter = SCContentFilter(display: display, excludingWindows: [])
        } else {
            let pid = ProcessInfo.processInfo.processIdentifier
            let ours = content.windows.filter { $0.owningApplication?.processID == pid && $0.isOnScreen }
            filter = SCContentFilter(display: display, including: ours)
        }
        let config = SCStreamConfiguration()
        config.width = display.width * 2
        config.height = display.height * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.showsCursor = true
        config.capturesAudio = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let recConfig = SCRecordingOutputConfiguration()
        try? FileManager.default.removeItem(at: file)
        recConfig.outputURL = file
        recConfig.outputFileType = .mp4
        recConfig.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: recConfig, delegate: self)
        try stream.addRecordingOutput(output)
        self.stream = stream
        self.output = output
        try await stream.startCapture()
        Log.file("record(screen): start \(config.width)x\(config.height) @\(fps) fps → \(file.path)")
        stopTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            await self?.stop()
        }
    }

    func stop() async {
        if let finishTask { await finishTask.value; return }
        stopTask?.cancel(); stopTask = nil
        guard let stream else { return }
        let task = Task { @MainActor in
            do {
                try await stream.stopCapture()
                if !recordingFinished {
                    await withCheckedContinuation { recordingWaiter = $0 }
                }
            }
            catch { Log.file("record(screen): stop failed \(error.localizedDescription)") }
            self.stream = nil
            self.output = nil
            if DebugScreenRecorder.current === self { DebugScreenRecorder.current = nil }
        }
        finishTask = task
        await task.value
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Log.file("record(screen): finished → \(file.path)")
        Task { @MainActor in recordingDidEnd() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Log.file("record(screen): recording failed \(error.localizedDescription)")
        Task { @MainActor in
            recordingDidEnd()
            await stop()
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.file("record(screen): stopped with error \(error.localizedDescription)")
        Task { @MainActor in
            recordingDidEnd()
            await stop()
        }
    }
    private func recordingDidEnd() {
        recordingFinished = true
        recordingWaiter?.resume()
        recordingWaiter = nil
    }
}
#endif
