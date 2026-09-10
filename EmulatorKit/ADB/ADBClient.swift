import Foundation

/// Thin async wrapper over the `adb` binary bound to one server port and one
/// device serial. All calls run through `Subprocess`.
public actor ADBClient {
    public let binary: URL
    public let serverPort: Int
    public let serial: String
    private let environment: [String: String]

    public init(paths: SDKPaths, serverPort: Int, serial: String) {
        self.binary = paths.adbBinary
        self.serverPort = serverPort
        self.serial = serial
        self.environment = paths.environment(adbServerPort: serverPort)
    }

    /// Runs `adb -P <port> -s <serial> <args>` and returns stdout. Throws on a
    /// non-zero exit with stderr in the message.
    @discardableResult
    public func run(_ args: [String], timeout: Duration = .seconds(30)) async throws -> String {
        let all = ["-P", String(serverPort), "-s", serial] + args
        let r = try await withThrowingTaskGroup(of: SubprocessResult.self) { group in
            group.addTask { try await Subprocess.run(self.binary, arguments: all, environment: self.environment) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw EmulatorKitError.timeout("adb \(args.joined(separator: " "))")
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
        guard r.status == 0 else {
            throw EmulatorKitError.adb("\(args.first ?? "") failed (\(r.status)): \(r.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))\(r.stdoutText.isEmpty ? "" : " " + r.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return r.stdoutText
    }

    public func shell(_ command: String, timeout: Duration = .seconds(30)) async throws -> String {
        try await run(["shell", command], timeout: timeout)
    }

    /// Server-level command without `-s` (e.g. `kill-server`, `devices`).
    public func server(_ args: [String]) async throws -> String {
        let r = try await Subprocess.run(binary, arguments: ["-P", String(serverPort)] + args, environment: environment)
        guard r.status == 0 else { throw EmulatorKitError.adb(r.stderrText) }
        return r.stdoutText
    }

    /// Starts the adb server on our port and waits for it. Done before the
    /// emulator launches: the emulator's own adb calls have short timeouts
    /// and, if no server is listening yet, every one of them forks another
    /// server that then fights for the port.
    public func startServer(timeout: Duration = .seconds(90)) async throws {
        let r = try await withThrowingTaskGroup(of: SubprocessResult.self) { group in
            group.addTask { try await Subprocess.run(self.binary, arguments: ["-P", String(self.serverPort), "start-server"], environment: self.environment) }
            group.addTask { try await Task.sleep(for: timeout); throw EmulatorKitError.timeout("adb start-server") }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
        guard r.status == 0 else { throw EmulatorKitError.adb("start-server failed: \(r.stderrText)") }
    }

    public func killServer() async {
        _ = try? await Subprocess.run(binary, arguments: ["-P", String(serverPort), "kill-server"], environment: environment)
    }

    // MARK: Convenience

    public func getprop(_ name: String) async throws -> String {
        try await shell("getprop \(name)").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func isBootCompleted() async -> Bool {
        (try? await getprop("sys.boot_completed")) == "1"
    }

    public func dumpsysDisplay() async throws -> String { try await shell("dumpsys display") }

    public func listThirdPartyPackages() async throws -> [String] {
        PackageListParser.parse(try await shell("pm list packages -3"))
    }

    /// `com.example/.MainActivity` for the launcher activity of `package`.
    public func launcherComponent(of package: String) async throws -> String? {
        let out = try await shell("cmd package resolve-activity --brief -c android.intent.category.LAUNCHER \(package)")
        return out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.contains("/") && !$0.hasPrefix("priority") }
    }

    public func startActivity(component: String, displayID: Int) async throws {
        let out = try await shell("am start --display \(displayID) -n \(component)")
        if out.contains("Error") { throw EmulatorKitError.adb(out.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    public func forceStop(_ package: String) async throws {
        try await shell("am force-stop \(package)")
    }

    public func install(apk: URL) async throws {
        try await run(["install", "-r", "-g", apk.path], timeout: .seconds(300))
    }

    public func uninstall(_ package: String) async throws {
        try await run(["uninstall", package], timeout: .seconds(120))
    }

    /// True if any task is currently hosted on the given logical display.
    public func hasTasks(onDisplay displayID: Int) async throws -> Bool {
        let out = try await shell("am stack list")
        return TaskListParser.displaysWithTasks(out).contains(displayID)
    }

    public func keyevent(_ key: String, displayID: Int? = nil) async throws {
        let d = displayID.map { "-d \($0) " } ?? ""
        try await shell("input \(d)keyevent \(key)")
    }
}
