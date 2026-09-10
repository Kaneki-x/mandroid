import AppKit
import EmulatorKit

/// Tracks the per-app windows and the device screen window.
@MainActor
final class WindowManager {
    let coordinator: RunnerCoordinator
    private(set) var appWindows: [String: AppWindowController] = [:]
    private(set) var deviceWindow: AppWindowController?

    init(coordinator: RunnerCoordinator) { self.coordinator = coordinator }

    /// Default logical size for a new app window: a phone-like portrait
    /// rectangle that fits the main screen.
    func defaultAppSize() -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let height = min(900, visible.height - 40)
        return NSSize(width: (height * 420 / 900).rounded(), height: height)
    }

    func open(package: String) {
        if let existing = appWindows[package] {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let size = defaultAppSize()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Task { @MainActor in
            do {
                let app = try await coordinator.openApp(package: package,
                                                        width: Int(size.width * scale),
                                                        height: Int(size.height * scale),
                                                        dpi: Int(160 * scale))
                let wc = AppWindowController(coordinator: coordinator, target: .app(app), logicalSize: size)
                wc.onClose = { [weak self] in self?.appWindows[package] = nil }
                appWindows[package] = wc
                wc.showWindow(nil)
                wc.window?.makeKeyAndOrderFront(nil)
            } catch {
                presentError(error, title: "Could not open \(package)")
            }
        }
    }

    func showDeviceScreen() {
        if let deviceWindow {
            deviceWindow.showWindow(nil)
            deviceWindow.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard let session = coordinator.session else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        var size = NSSize(width: CGFloat(session.deviceWidth) / scale, height: CGFloat(session.deviceHeight) / scale)
        if size.height > visible.height - 40 {
            let f = (visible.height - 40) / size.height
            size = NSSize(width: (size.width * f).rounded(), height: (size.height * f).rounded())
        }
        let wc = AppWindowController(coordinator: coordinator, target: .device, logicalSize: size)
        wc.onClose = { [weak self] in self?.deviceWindow = nil }
        deviceWindow = wc
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        for wc in appWindows.values { wc.close() }
        appWindows = [:]
        deviceWindow?.close()
        deviceWindow = nil
    }

    var keyAppWindow: AppWindowController? {
        (NSApp.keyWindow?.windowController as? AppWindowController)
    }

    func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
