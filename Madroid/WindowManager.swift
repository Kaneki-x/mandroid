import AppKit
import MadroidKit

/// Tracks the per-app windows and the device screen window.
@MainActor
final class WindowManager {
    let coordinator: RunnerCoordinator
    private(set) var appWindows: [String: AppWindowController] = [:]
    private(set) var deviceWindow: AppWindowController?

    init(coordinator: RunnerCoordinator) { self.coordinator = coordinator }

    /// Default logical size for a new app window: a tablet-sized landscape
    /// rectangle that fits the main screen, unless portrait is selected.
    func defaultAppSize() -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let s = RunnerSettings.load().defaultWindowSize(screenWidth: visible.width, screenHeight: visible.height)
        return NSSize(width: s.width, height: s.height)
    }

    func open(package: String) {
        Log.file("open \(package)")
        if let existing = appWindows[package] {
            if !UITestMode.enabled {
                existing.showWindow(nil)
                existing.window?.makeKeyAndOrderFront(nil)
            }
            if existing.isParked { existing.resume() }
            return
        }
        let size = defaultAppSize()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Task { @MainActor in
            do {
                try await makeRoomForNewWindow()
                let app = try await coordinator.openApp(package: package,
                                                        width: Int(size.width * scale),
                                                        height: Int(size.height * scale),
                                                        dpi: Int(160 * scale))
                let wc = AppWindowController(coordinator: coordinator, target: .app(app), logicalSize: size)
                wc.onClose = { [weak self] in self?.appWindows[package] = nil }
                wc.makeRoom = { [weak self] in try await self?.makeRoomForNewWindow() }
                appWindows[package] = wc
                if !UITestMode.enabled {
                    wc.showWindow(nil)
                    wc.window?.makeKeyAndOrderFront(nil)
                }
            } catch {
                presentError(error, title: "Could not open \(package)")
            }
        }
    }

    /// LRU parking: when all three displays are taken, pause the app window
    /// that was used least recently so a new one can open.
    func makeRoomForNewWindow() async throws {
        guard coordinator.freeSlots <= 0 else { return }
        let candidates = appWindows.values.filter { !$0.isParked }
        guard let victim = candidates.min(by: { $0.lastActivated < $1.lastActivated }) else {
            throw MadroidKitError.display("all \(DisplaySlotPool.capacity) app windows are in use")
        }
        await victim.park()
    }

    func showDeviceScreen() {
        if let deviceWindow {
            if !UITestMode.enabled {
                deviceWindow.showWindow(nil)
                deviceWindow.window?.makeKeyAndOrderFront(nil)
            }
            return
        }
        guard let session = coordinator.session else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        var size = NSSize(width: CGFloat(session.deviceWidth) / scale, height: CGFloat(session.deviceHeight) / scale)
        let fit = min(1, (visible.width - 40) / size.width, (visible.height - 40) / size.height)
        size = NSSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
        let wc = AppWindowController(coordinator: coordinator, target: .device, logicalSize: size)
        wc.onClose = { [weak self] in self?.deviceWindow = nil }
        deviceWindow = wc
        if !UITestMode.enabled {
            wc.showWindow(nil)
            wc.window?.makeKeyAndOrderFront(nil)
        }
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

    private(set) var lastError: String?

    func presentError(_ error: Error, title: String) {
        lastError = "\(title): \(error.localizedDescription)"
        Log.file("ERROR \(title): \(error.localizedDescription)")
        guard !UITestMode.enabled else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
