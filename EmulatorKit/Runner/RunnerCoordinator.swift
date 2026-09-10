import Foundation
import Observation

/// Main-actor state machine that takes the app from "nothing installed" to a
/// booted emulator, and owns app sessions afterwards.
@MainActor
@Observable
public final class RunnerCoordinator {
    public private(set) var state: RunnerState = .idle
    public private(set) var session: EmulatorSession?
    public private(set) var sessions: [String: AppSession] = [:]   // by package
    public private(set) var installedPackages: [String] = []

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
                    let plan = try await bootstrap.makePlan()
                    if plan.isEmpty { await boot() } else { state = .needsSetup(plan) }
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
                throw EmulatorKitError.avd("no system image installed")
            }
            var config = AVDConfig(systemImagePath: image.packagePath)
            config.name = avdName
            if !avdStore.exists(avdName) {
                try avdStore.write(config)
            } else {
                try avdStore.stripPersistedDisplays(avdName)
            }

            guard let console = PortAllocator.freeConsolePort(),
                  let grpc = PortAllocator.freePort(in: 8554...8654),
                  let adbPort = PortAllocator.freePort(in: 5137...5237) else {
                throw EmulatorKitError.emulator("no free ports")
            }
            var options = EmulatorLaunchOptions(avdName: avdName, consolePort: console, grpcPort: grpc, adbServerPort: adbPort)
            options.coldBoot = coldBoot

            setStage("Starting emulator")
            let process = try EmulatorProcess(paths: paths, options: options)
            try process.start()
            let adb = ADBClient(paths: paths, serverPort: adbPort, serial: options.serial)

            let connection = try EmulatorConnection(port: grpc)
            setStage("Connecting to emulator")
            do {
                try await connection.waitUntilReachable(timeout: .seconds(90))
            } catch {
                process.terminate()
                throw EmulatorKitError.emulator("did not start:\n\(process.tailLog(lines: 12))")
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
            state = .ready
            await refreshInstalledPackages()
            watchProcess(session)
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
        _ = try? await session.adb.server(["kill-server"])
        session.connection.shutdown()
        self.session = nil
        self.sessions = [:]
        state = .idle
    }

    // MARK: Apps

    public func refreshInstalledPackages() async {
        guard let session else { return }
        installedPackages = (try? await session.adb.listThirdPartyPackages()) ?? []
    }

    /// Creates a display and launches the app on it.
    public func openApp(package: String, width: Int, height: Int, dpi: Int) async throws -> AppSession {
        guard let session else { throw EmulatorKitError.emulator("not running") }
        if let existing = sessions[package] { return existing }
        guard let component = try await session.adb.launcherComponent(of: package) else {
            throw EmulatorKitError.adb("\(package) has no launcher activity")
        }
        let slot = try await session.displays.acquire(width: width, height: height, dpi: dpi)
        do {
            try await session.adb.startActivity(component: component, displayID: slot.androidDisplayID)
        } catch {
            try? await session.displays.release(slot.emulatorIndex)
            throw error
        }
        await session.router.noteTouch(androidDisplayID: slot.androidDisplayID)
        let app = AppSession(package: package, launcherComponent: component, slot: slot)
        sessions[package] = app
        return app
    }

    public func closeApp(_ app: AppSession) async {
        guard let session else { return }
        sessions[app.package] = nil
        try? await session.adb.forceStop(app.package)
        try? await session.displays.release(app.slot.emulatorIndex)
        await session.router.forget(androidDisplayID: app.slot.androidDisplayID)
    }

    public func resizeApp(_ app: AppSession, width: Int, height: Int, dpi: Int) async throws -> AppSession {
        guard let session else { throw EmulatorKitError.emulator("not running") }
        let slot = try await session.displays.resize(app.slot.emulatorIndex, width: width, height: height, dpi: dpi)
        var updated = app
        updated.slot = slot
        sessions[app.package] = updated
        return updated
    }

    public func installAPK(_ url: URL) async throws {
        guard let session else { throw EmulatorKitError.emulator("not running") }
        try await session.adb.install(apk: url)
        await refreshInstalledPackages()
    }

    public func uninstall(package: String) async throws {
        guard let session else { throw EmulatorKitError.emulator("not running") }
        if let app = sessions[package] { await closeApp(app) }
        try await session.adb.uninstall(package)
        await refreshInstalledPackages()
    }

    /// Opens the Play Store on the device screen (display 0).
    public func openPlayStore() async {
        guard let session else { return }
        _ = try? await session.adb.shell("am start --display 0 -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n com.android.vending/.AssetBrowserActivity")
    }
}
