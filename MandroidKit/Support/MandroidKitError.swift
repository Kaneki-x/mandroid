import Foundation

/// Errors surfaced by MandroidKit. Every case carries a human-readable
/// message suitable for an alert.
public enum MandroidKitError: Error, LocalizedError, Sendable, Equatable {
    case manifest(String)
    case download(String)
    case checksumMismatch(expected: String, actual: String, file: String)
    case unarchive(String)
    case avd(String)
    case emulator(String)
    case adb(String)
    case grpc(String)
    case display(String)
    case timeout(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .manifest(let m): return "SDK manifest: \(m)"
        case .download(let m): return "Download failed: \(m)"
        case .checksumMismatch(let e, let a, let f):
            return "Checksum mismatch for \(f): expected \(e), got \(a)"
        case .unarchive(let m): return "Unpacking failed: \(m)"
        case .avd(let m): return "Virtual device: \(m)"
        case .emulator(let m): return "Emulator: \(m)"
        case .adb(let m): return "adb: \(m)"
        case .grpc(let m): return "Emulator connection: \(m)"
        case .display(let m): return "Display: \(m)"
        case .timeout(let m): return "Timed out: \(m)"
        case .cancelled: return "Cancelled"
        }
    }
}
