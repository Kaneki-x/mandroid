import Foundation
import Observation

/// Main-actor state machine that takes the app from "nothing installed" to a
/// booted emulator, and owns app sessions afterwards.
@MainActor
@Observable
public final class RunnerCoordinator {
    public private(set) var state: RunnerState = .idle {
        didSet {
            // Download progress ticks arrive every couple of MB; log each
            // component once instead of every tick.
            if case .settingUp(.downloading(let name, _)) = state {
                if case .settingUp(.downloading(let previous, _)) = oldValue, previous == name { return }
                Log.runner.notice("state → downloading \(name, privacy: .public)")
                Log.file("state → downloading \(name)")
                return
            }
            Log.runner.notice("state → \(String(describing: self.state).prefix(200), privacy: .public)")
            Log.file("state → \(String(describing: self.state).prefix(200))")
        }
    }
    public private(set) var session: EmulatorSession?
    public private(set) var sessions: [String: AppSession] = [:]   // by package
    /// Apps whose window is parked: the task still exists in Android (moved to
    /// display 0) but its slot has been released.
    public private(set) var parked: [String: AppSession] = [:]
    public private(set) var apps: [AppInfo] = []
    public var installedPackages: [String] { apps.map(\.package) }
    public private(set) var catalog: AppCatalog?
    public private(set) var clipboard: ClipboardSync?
    /// Set by the app to enable clipboard sync (needs AppKit's pasteboard).
    public var hostClipboard: (any HostClipboard)?

    public let paths: SDKPaths
    public let bootstrap: SDKBootstrap
    public let avdStore: AVDStore
    public var avdName = "runner"

    private var bootTask: Task<Void, Never>?

    public init(paths: SDKPaths = .default) {
        self.paths = paths
        self.bootstrap = SDKBootstrap(paths: paths)
        self.avdStore = AVDStore(paths: paths)
    }

    // MARK: Lifecycle

    /// Decides between setup and boot.
    public func start() {
        guard case .idle = state else { return }
        state = .checking
        Task {
            if bootstrap.isReady {
                await boot()
            } else {
                do {
                    await bootstrap.setMirrors(RunnerSettings.load().mirrors)
                    let plan = try await bootstrap.makePlan()
                    if plan.isEmpty {
                        await boot()
                    } else if UserDefaults.standard.bool(forKey: "autoSetup") {
                        // `-autoSetup YES` skips the confirmation (integration tests).
                        runSetup(plan)
                    } else {
                        state = .needsSetup(plan)
                    }
                } catch {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    public func runSetup(_ plan: BootstrapPlan) {
        state = .settingUp(.fetchingManifests)
        Task {
            do {
                try await bootstrap.run(plan) { phase in
                    Task { @MainActor in self.state = .settingUp(phase) }
                }
                await boot()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    public func retry() {
        state = .idle
        start()
    }

    private func setStage(_ s: String) { state = .booting(s) }

    public func boot(coldBoot: Bool = false) async {
        guard session == nil else { return }
        do {
            setStage("Preparing virtual device")
            guard let image = bootstrap.installedSystemImage() else {
                throw MadroidKitError.avd("no system image installed")
            }
            var config = AVDConfig(systemImagePath: image.packagePath)
            config.name = avdName
            RunnerSettings.load().apply(to: &config)
            // (Re)write the ini files every boot: picks up RAM/core changes and
            // drops hw.displayN.* keys the emulator persisted. User data and
            // snapshots live in other files and are untouched.
            try avdStore.write(config)

            guard let console = PortAllocator.freeConsolePort(),
                  let grpc = PortAllocator.freePort(in: 8554...8654),
                  let adbPort = PortAllocator.freePort(in: 5137...5237) else {
                throw MadroidKitError.emulator("no free ports")
            }
            var options = EmulatorLaunchOptions(avdName: avdName, consolePort: console, grpcPort: grpc, adbServerPort: adbPort)
            options.coldBoot = coldBoot

            setStage("Starting adb")
            let adb = ADBClient(paths: paths, serverPort: adbPort, serial: options.serial)
            try await adb.startServer()

            setStage("Starting emulator")
            let process = try EmulatorProcess(paths: paths, options: options)
            try process.start()

            let connection = try EmulatorConnection(port: grpc)
            setStage("Connecting to emulator")
            do {
                try await connection.waitUntilReachable(timeout: .seconds(90))
            } catch {
                process.terminate()
                await adb.killServer()
                throw MadroidKitError.emulator("did not start:\n\(process.tailLog(lines: 12))")
            }

            try await BootWaiter.waitForBoot(adb: adb, process: process) { stage in
                let text: String
                switch stage {
                case .waitingForProcess, .waitingForADB: text = "Waiting for Android"
                case .waitingForBoot: text = "Android is booting"
                case .booted: text = "Finishing up"
                }
                Task { @MainActor in self.setStage(text) }
            }
            await GuestSetup.apply(adb: adb)

            let client = EmulatorClient(connection: connection)
            let pool = DisplaySlotPool(client: client, adb: adb)
            try await pool.reset()

            let session = EmulatorSession(
                options: options, process: process, adb: adb, connection: connection, client: client,
                displays: pool, input: InputChannel(client: client), router: InputRouter(adb: adb),
                frames: GRPCFrameStream(client: client),
                deviceWidth: config.lcdWidth, deviceHeight: config.lcdHeight, deviceDpi: config.lcdDensity)
            self.session = session
            self.catalog = AppCatalog(paths: paths, adb: adb, mirrors: RunnerSettings.load().mirrors)
            if let hostClipboard {
                let sync = ClipboardSync(client: client, host: hostClipboard)
                await sync.start()
                self.clipboard = sync
            }
            state = .ready
            watchProcess(session)
            await refreshApps()
        } catch {
            Log.runner.error("boot failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    private func watchProcess(_ session: EmulatorSession) {
        Task {
            let status = await session.process.waitForExit()
            guard self.session?.options.consolePort == session.options.consolePort else { return }
            self.session = nil
            self.sessions = [:]
            self.parked = [:]
            if case .shuttingDown = state { state = .idle } else {
                state = .failed("The emulator stopped unexpectedly (exit code \(status)).")
            }
        }
    }

    /// Clean shutdown: stop apps, ask QEMU to power off (saves the quickboot
    /// snapshot), then escalate to SIGTERM/SIGKILL. Never leaves an orphan.
    public func shutdown() async {
        guard let session else { return }
        state = .shuttingDown
        await clipboard?.stop()
        clipboard = nil
        await session.input.close()
        try? await session.displays.reset()
        _ = try? await session.adb.run(["emu", "kill"], timeout: .seconds(5))
        let exited = await withTaskGroup(of: Bool.self) { group in
            group.addTask { _ = await session.process.waitForExit(); return true }
            group.addTask { try? await Task.sleep(for: .seconds(15)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if !exited {
            session.process.terminate()
            try? await Task.sleep(for: .seconds(3))
            session.process.kill()
        }
        await session.adb.killServer()
        session.connection.shutdown()
        self.session = nil
        self.sessions = [:]
        self.parked = [:]
        self.apps = []
        state = .idle
    }

    // MARK: Apps

    private var refreshTask: Task<Void, Never>?

    /// Reloads the app list: cached entries immediately, then labels/icons
    /// for anything new as they resolve.
    public func refreshApps() async {
        guard let catalog else { return }
        refreshTask?.cancel()
        if let quick = try? await catalog.cached() { apps = quick }
        refreshTask = Task { [weak self] in
            do {
                _ = try await catalog.refresh { list in
                    Task { @MainActor in self?.apps = list }
                }
            } catch {
                Log.runner.warning("catalog refresh failed: \(error.localizedDescription)")
            }
        }
    }

    /// Kept for callers that only need package names.
    public func refreshInstalledPackages() async { await refreshApps() }

    public func app(for package: String) -> AppInfo? { apps.first { $0.package == package } }

    private func launcherComponent(for package: String) async throws -> String {
        if let c = app(for: package)?.launcherComponent { return c }
        guard let session, let c = try await session.adb.launcherComponent(of: package) else {
            throw MadroidKitError.adb("\(package) has no launcher activity")
        }
        return c
    }

    /// Creates a display and launches (or brings back) the app on it.
    public func openApp(package: String, width: Int, height: Int, dpi: Int) async throws -> AppSession {
        guard let session else { throw MadroidKitError.emulator("not running") }
        if let existing = sessions[package] { return existing }
        let component = try await launcherComponent(for: package)
        let slot: DisplaySlot
        do {
            slot = try await session.displays.acquire(width: width, height: height, dpi: dpi)
        } catch {
            Log.file("openApp \(package): acquire failed: \(error.localizedDescription)")
            throw error
        }
        do {
            try await session.adb.startActivity(component: component, displayID: slot.androidDisplayID)
        } catch {
            Log.file("openApp \(package): am start failed: \(error.localizedDescription)")
            try? await session.displays.release(slot.emulatorIndex)
            throw error
        }
        Log.file("openApp \(package) → slot \(slot.emulatorIndex) display \(slot.androidDisplayID) \(slot.width)x\(slot.height)")
        await session.router.noteTouch(androidDisplayID: slot.androidDisplayID)
        let app = AppSession(package: package, launcherComponent: component, slot: slot)
        sessions[package] = app
        parked[package] = nil
        return app
    }

    /// Frees the slot but keeps the Android task alive (it moves to display 0).
    public func parkApp(_ app: AppSession) async {
        guard let session else { return }
        sessions[app.package] = nil
        parked[app.package] = app
        try? await session.displays.release(app.slot.emulatorIndex)
        await session.router.forget(androidDisplayID: app.slot.androidDisplayID)
    }

    public var freeSlots: Int {
        DisplaySlotPool.capacity - sessions.count
    }

    public func closeApp(_ app: AppSession) async {
        guard let session else { return }
        sessions[app.package] = nil
        parked[app.package] = nil
        try? await session.adb.forceStop(app.package)
        try? await session.displays.release(app.slot.emulatorIndex)
        await session.router.forget(androidDisplayID: app.slot.androidDisplayID)
    }

    /// True while Android still hosts a task on the app's display.
    public func isAppAlive(_ app: AppSession) async -> Bool {
        guard let session else { return false }
        return (try? await session.adb.hasTasks(onDisplay: app.slot.androidDisplayID)) ?? true
    }

    public func resizeApp(_ app: AppSession, width: Int, height: Int, dpi: Int) async throws -> AppSession {
        guard let session else { throw MadroidKitError.emulator("not running") }
        let slot = try await session.displays.resize(app.slot.emulatorIndex, width: width, height: height, dpi: dpi)
        var updated = app
        updated.slot = slot
        sessions[app.package] = updated
        return updated
    }

    public func installAPK(_ url: URL) async throws {
        guard let session else { throw MadroidKitError.emulator("not running") }
        try await session.adb.install(apk: url)
        await refreshApps()
    }

    public func uninstall(package: String) async throws {
        guard let session else { throw MadroidKitError.emulator("not running") }
        if let app = sessions[package] ?? parked[package] { await closeApp(app) }
        try await session.adb.uninstall(package)
        await catalog?.invalidate(package: package)
        await refreshApps()
    }

    /// Saves a PNG of the given display to `url`.
    public func screenshot(display: Int, width: Int, height: Int) async throws -> Frame {
        guard let session else { throw MadroidKitError.emulator("not running") }
        let img = try await session.client.screenshot(display: display, width: width, height: height)
        return Frame(width: Int(img.format.width), height: Int(img.format.height), pixels: img.image,
                     sequence: img.seq, timestampUs: img.timestampUs)
    }

    /// Restarts the emulator (cold boot when requested).
    public func restart(coldBoot: Bool = false) async {
        await shutdown()
        await boot(coldBoot: coldBoot)
    }

    /// Opens the Play Store on the device screen (display 0).
    public func openPlayStore() async {
        guard let session else { return }
        _ = try? await session.adb.shell("am start --display 0 -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n com.android.vending/.AssetBrowserActivity")
    }
}
