import AppKit
import MandroidKit

/// Offscreen UI automation is Debug-only and requires an isolated data root.
@MainActor
enum UITestMode {
    static var controlDirectory: URL? {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "uiTestControlDirectory") else { return nil }
        guard let root = SDKPaths.overrideRoot?.resolvingSymlinksInPath(),
              !(AppMigration.legacyNames + ["Mandroid"]).contains(where: {
                  root == SDKPaths.applicationSupport.appendingPathComponent($0).resolvingSymlinksInPath()
              }),
              root.lastPathComponent.hasPrefix("mandroid-ui-"),
              URL(fileURLWithPath: path).resolvingSymlinksInPath().deletingLastPathComponent() == root else {
            fatalError("Offscreen tests require a dedicated mandroid-ui- data root and control directory inside it")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
        #else
        return nil
        #endif
    }
    static var enabled: Bool { controlDirectory != nil }

    static func receiveCommands(delegate: AppDelegate) async {
        #if DEBUG
        guard let directory = controlDirectory else { return }
        while !Task.isCancelled {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: nil)) ?? []
            for file in files.filter({ $0.pathExtension == "command" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if let text = try? String(contentsOf: file, encoding: .utf8),
                   let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    try? FileManager.default.removeItem(at: file)
                    delegate.application(NSApp, open: [url])
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #endif
    }
}
