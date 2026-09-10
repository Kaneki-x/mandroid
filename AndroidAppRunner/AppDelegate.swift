import AppKit
import EmulatorKit
import Observation

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    let coordinator = RunnerCoordinator()
    private(set) lazy var windows = WindowManager(coordinator: coordinator)
    private var setupWindow: SetupWindowController?
    private var libraryWindow: LibraryWindowController?
    private var stateObservation: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(delegate: self)
        NSApp.activate(ignoringOtherApps: true)
        observeState()
        coordinator.start()
    }

    /// Re-evaluates which top-level window should be visible whenever the
    /// coordinator state changes.
    private func observeState() {
        stateObservation = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let state = withObservationTracking { self.coordinator.state } onChange: {}
                self.apply(state)
                await withCheckedContinuation { cont in
                    withObservationTracking { _ = self.coordinator.state } onChange: { cont.resume() }
                }
            }
        }
    }

    private func apply(_ state: RunnerState) {
        switch state {
        case .ready:
            setupWindow?.close(); setupWindow = nil
            showLibrary()
        case .idle:
            break
        default:
            libraryWindow?.close(); libraryWindow = nil
            windows.closeAll()
            showSetup()
        }
    }

    private func showSetup() {
        if setupWindow == nil { setupWindow = SetupWindowController(coordinator: coordinator) }
        setupWindow?.showWindow(nil)
    }

    @objc func showLibrary() {
        if libraryWindow == nil { libraryWindow = LibraryWindowController(coordinator: coordinator, windows: windows) }
        libraryWindow?.showWindow(nil)
        libraryWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showDeviceScreen(_ sender: Any?) { windows.showDeviceScreen() }
    @objc func openPlayStore(_ sender: Any?) {
        Task { await coordinator.openPlayStore() }
        windows.showDeviceScreen()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if coordinator.state.isReady { showLibrary() } else { showSetup() }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard coordinator.session != nil else { return .terminateNow }
        Task { @MainActor in
            windows.closeAll()
            await coordinator.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL, url.pathExtension.lowercased() == "apk" {
                Task { try? await coordinator.installAPK(url) }
            } else if url.scheme == "androidrunner" {
                URLSchemeHandler(delegate: self).handle(url)
            }
        }
    }
}
