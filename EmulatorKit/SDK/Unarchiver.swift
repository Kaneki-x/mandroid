import Foundation

/// Zip extraction via `/usr/bin/ditto -x -k` (keeps code signatures, resource
/// forks and symlinks intact) followed by quarantine stripping.
public enum Unarchiver {
    public static func extract(zip: URL, into destination: URL) async throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let r = try await Subprocess.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                         arguments: ["-x", "-k", zip.path, destination.path])
        guard r.status == 0 else {
            throw EmulatorKitError.unarchive("ditto exited \(r.status): \(r.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        await stripQuarantine(at: destination)
    }

    /// Removes `com.apple.quarantine` recursively; errors are ignored because
    /// the attribute is usually absent.
    public static func stripQuarantine(at url: URL) async {
        _ = try? await Subprocess.run(URL(fileURLWithPath: "/usr/bin/xattr"),
                                      arguments: ["-dr", "com.apple.quarantine", url.path])
    }

    /// Lists the top-level directory names inside a zip (for zips that wrap
    /// their content in a single folder, e.g. `emulator/`).
    public static func topLevelEntries(zip: URL) async throws -> [String] {
        let r = try await Subprocess.run(URL(fileURLWithPath: "/usr/bin/zipinfo"), arguments: ["-1", zip.path])
        guard r.status == 0 else { throw EmulatorKitError.unarchive("zipinfo exited \(r.status)") }
        var names = Set<String>()
        for line in r.stdoutText.split(separator: "\n") {
            if let first = line.split(separator: "/").first { names.insert(String(first)) }
        }
        return names.sorted()
    }
}
