import AppKit
import MadroidKit
import Observation

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        if UserDefaults.standard.string(forKey: "uiTestControlDirectory") != nil, !UITestMode.enabled {
            fatalError("Offscreen UI tests require a Debug build")
        }
        migrateFromAndroidAppRunner()
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(UITestMode.enabled ? .prohibited : .regular)
        app.run()
    }

    let coordinator = RunnerCoordinator()

    /// One-time migration from the app's previous name (Android App Runner):
    /// the data folder moves to `Application Support/Madroid` and the
    /// preferences are copied into the new defaults domain. The move is
    /// refused while the old app is still running, since its emulator has the
    /// folder open.
    private static let legacyBundleID = "io.github.madeye.androidapprunner"

    private static func migrateFromAndroidAppRunner() {
        let fm = FileManager.default
        guard SDKPaths.overrideRoot == nil,
              !fm.fileExists(atPath: SDKPaths.default.root.path),
              fm.fileExists(atPath: SDKPaths.legacyRoot.path) else { return }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: legacyBundleID).isEmpty {
            let alert = NSAlert()
            alert.messageText = "Quit Android App Runner first"
            alert.informativeText = "Madroid is the new name of Android App Runner. Quit the old app so its data can be moved over, then open Madroid again."
            alert.runModal()
            exit(0)
        }
        if SDKPaths.migrateLegacyRootIfNeeded(),
           let old = UserDefaults.standard.persistentDomain(forName: legacyBundleID) {
            for (key, value) in old where UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(value, forKey: key)
            }
            Log.file("migrated data and settings from Android App Runner")
        }
    }
    private(set) lazy var windows = WindowManager(coordinator: coordinator)
    private var setupWindow: SetupWindowController?
    private var libraryWindow: LibraryWindowController?
    private var settingsWindow: SettingsWindowController?
    private var stateObservation: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UITestMode.enabled { coordinator.hostClipboard = PasteboardClipboard() }
        NSApp.mainMenu = MainMenu.build(delegate: self)
        if !UITestMode.enabled { NSApp.activate(ignoringOtherApps: true) }
        if UITestMode.enabled { Task { await UITestMode.receiveCommands(delegate: self) } }
        observeState()
        observeApps()
        coordinator.start()
    }

    /// Re-evaluates which top-level window should be visible whenever the
    /// coordinator state changes.
    private var appsObservation: Task<Void, Never>?

    private func observeApps() {
        appsObservation = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let apps = withObservationTracking { self.coordinator.apps } onChange: {}
                if !UITestMode.enabled, !apps.isEmpty, UserDefaults.standard.object(forKey: "launcherStubs") as? Bool ?? true {
                    LauncherStubBuilder.sync(apps)
                }
                await withCheckedContinuation { cont in
                    withObservationTracking { _ = self.coordinator.apps } onChange: { cont.resume() }
                }
            }
        }
    }

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
        if !UITestMode.enabled { setupWindow?.showWindow(nil) }
    }

    @objc func showLibrary() {
        if libraryWindow == nil { libraryWindow = LibraryWindowController(coordinator: coordinator, windows: windows) }
        if !UITestMode.enabled {
            libraryWindow?.showWindow(nil)
            libraryWindow?.window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc func showDeviceScreen(_ sender: Any?) { windows.showDeviceScreen() }
    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(coordinator: coordinator, windows: windows) }
        if !UITestMode.enabled {
            settingsWindow?.showWindow(nil)
            settingsWindow?.window?.makeKeyAndOrderFront(nil)
        }
    }
    @objc func restartEmulator(_ sender: Any?) {
        windows.closeAll()
        Task { await coordinator.restart() }
    }
    @objc func coldBootEmulator(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Cold boot the emulator?"
        alert.informativeText = "Running apps will be closed and Android will boot from scratch instead of restoring the saved snapshot. Installed apps and data are kept."
        alert.addButton(withTitle: "Cold Boot")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        windows.closeAll()
        Task { await coordinator.restart(coldBoot: true) }
    }
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
            } else if url.scheme == "madroid" {
                URLSchemeHandler(delegate: self).handle(url)
            }
        }
    }
}
