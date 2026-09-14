import AppKit
import MadroidKit

/// Creates `~/Applications/Android Apps/<Label>.app` stubs so Android apps
/// show up in Spotlight, Launchpad and the Dock. Each stub is a tiny shell
/// script bundle that opens `madroid://launch/<package>`; its icon is
/// the app's launcher icon applied as a Finder custom icon.
@MainActor
enum LauncherStubBuilder {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Android Apps", isDirectory: true)
    }

    static let marker = "io.github.madeye.madroid.stub"
    /// Marker written by the app before it was renamed; such stubs are
    /// still ours (they get rewritten with the new URL scheme).
    static let legacyMarker = "io.github.madeye.androidapprunner.stub"

    /// Rebuilds the stub set to match `apps`; stale stubs we created are removed.
    static func sync(_ apps: [AppInfo], at directory: URL = directory) {
        let fm = FileManager.default
        do { try fm.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return }
        var wanted = Set<String>()
        for app in apps {
            // Package identity prevents equal labels (including case-only
            // differences on APFS) from overwriting one another.
            let name = "\(safeName(app.label)) (\(SHA1.hex(of: Data(app.package.utf8)).prefix(12)))"
            wanted.insert("\(name).app")
            let bundle = directory.appendingPathComponent("\(name).app", isDirectory: true)
            guard !fm.fileExists(atPath: bundle.path) || isOurs(bundle) else { continue }
            if needsUpdate(bundle, app: app) {
                try? write(bundle, app: app)
            }
        }
        for entry in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where entry.pathExtension == "app" && !wanted.contains(entry.lastPathComponent) && isOurs(entry) {
            try? fm.removeItem(at: entry)
        }
    }

    static func remove(package: String, label: String) {
        for bundle in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
            if isOurs(bundle), plist?["AndroidPackage"] as? String == package {
                try? FileManager.default.removeItem(at: bundle)
            }
        }
    }

    // MARK: Internals

    private static func safeName(_ label: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\")
        let cleaned = label.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        // Leave space for the identity suffix within the filesystem limit.
        var limited = cleaned
        while limited.utf8.count > 180 { limited.removeLast() }
        return limited.isEmpty ? "Android App" : limited
    }

    private static func isOurs(_ bundle: URL) -> Bool {
        guard let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) else { return false }
        return plist[marker] != nil || plist[legacyMarker] != nil
    }

    private static func needsUpdate(_ bundle: URL, app: AppInfo) -> Bool {
        guard let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) else { return true }
        return plist["AndroidPackage"] as? String != app.package
            || plist["AndroidVersionCode"] as? Int != app.versionCode
            || plist[marker] == nil
    }

    private static func write(_ bundle: URL, app: AppInfo) throws {
        let fm = FileManager.default
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        try? fm.removeItem(at: bundle)
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)

        let script = """
        #!/bin/sh
        exec /usr/bin/open \(ADBClient.shellQuote("madroid://launch/" + app.package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!))

        """
        let exe = macos.appendingPathComponent("launch")
        try script.write(to: exe, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        let bundleID = "io.github.madeye.madroid.stub." + app.package
        let plist: [String: Any] = [
            "CFBundleName": app.label,
            "CFBundleDisplayName": app.label,
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": "launch",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": app.versionName.isEmpty ? "1.0" : app.versionName,
            "CFBundleVersion": String(app.versionCode),
            "LSMinimumSystemVersion": "15.0",
            "LSUIElement": true,           // no Dock bounce for the script itself
            "NSHighResolutionCapable": true,
            "AndroidPackage": app.package,
            "AndroidVersionCode": app.versionCode,
            marker: true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try "APPL????".write(to: contents.appendingPathComponent("PkgInfo"), atomically: true, encoding: .utf8)

        if let file = app.iconFile, let image = NSImage(contentsOf: file) {
            NSWorkspace.shared.setIcon(roundedIcon(image), forFile: bundle.path, options: [])
        }
        Log.ui.info("wrote launcher stub \(bundle.lastPathComponent, privacy: .public)")
    }

    /// Android icons are square; macOS expects the rounded-rect silhouette.
    private static func roundedIcon(_ source: NSImage) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let out = NSImage(size: size)
        out.lockFocus()
        let inset = NSRect(x: 51, y: 51, width: 410, height: 410)
        NSBezierPath(roundedRect: inset, xRadius: 92, yRadius: 92).addClip()
        source.draw(in: inset, from: .zero, operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        return out
    }
}
