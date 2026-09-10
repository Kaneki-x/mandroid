import OSLog

/// Loggers per subsystem area. Use `Log.sdk.info("…")` etc.
public enum Log {
    public static let subsystem = "io.github.madeye.madroid"
    public static let sdk = Logger(subsystem: subsystem, category: "sdk")
    public static let emulator = Logger(subsystem: subsystem, category: "emulator")
    public static let adb = Logger(subsystem: subsystem, category: "adb")
    public static let grpc = Logger(subsystem: subsystem, category: "grpc")
    public static let display = Logger(subsystem: subsystem, category: "display")
    public static let input = Logger(subsystem: subsystem, category: "input")
    public static let runner = Logger(subsystem: subsystem, category: "runner")
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Also appends to `<root>/logs/app.log` (unified logging is not always
    /// readable from a shell). Cheap enough for events, not for per-frame use.
    public static func file(_ message: String, paths: SDKPaths = .default) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = paths.logs.appendingPathComponent("app.log")
        fileQueue.async {
            if let h = try? FileHandle(forWritingTo: url) {
                _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(line.utf8)); try? h.close()
            } else {
                try? FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    private static let fileQueue = DispatchQueue(label: "io.github.madeye.madroid.filelog")
}
import Foundation
