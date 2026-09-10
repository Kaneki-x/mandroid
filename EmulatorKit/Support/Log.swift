import OSLog

/// Loggers per subsystem area. Use `Log.sdk.info("…")` etc.
public enum Log {
    public static let subsystem = "io.github.madeye.androidapprunner"
    public static let sdk = Logger(subsystem: subsystem, category: "sdk")
    public static let emulator = Logger(subsystem: subsystem, category: "emulator")
    public static let adb = Logger(subsystem: subsystem, category: "adb")
    public static let grpc = Logger(subsystem: subsystem, category: "grpc")
    public static let display = Logger(subsystem: subsystem, category: "display")
    public static let input = Logger(subsystem: subsystem, category: "input")
    public static let runner = Logger(subsystem: subsystem, category: "runner")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
