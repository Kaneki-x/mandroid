import Foundation

/// Waits for adb to see the device and for `sys.boot_completed`.
public enum BootWaiter {
    public enum Stage: Sendable, Equatable {
        case waitingForProcess, waitingForADB, waitingForBoot, booted
    }

    public static func waitForBoot(adb: ADBClient,
                                   process: EmulatorProcess,
                                   timeout: Duration = .seconds(240),
                                   onStage: @escaping @Sendable (Stage) -> Void) async throws {
        let deadline = ContinuousClock.now + timeout
        onStage(.waitingForADB)
        var sawDevice = false
        while ContinuousClock.now < deadline {
            if !process.isRunning {
                throw MandroidKitError.emulator("exited during boot:\n\(process.tailLog(lines: 15))")
            }
            if !sawDevice {
                if let devices = try? await adb.server(["devices"]),
                   devices.contains("\(adb.serial)\tdevice") {
                    sawDevice = true
                    onStage(.waitingForBoot)
                }
            } else if await adb.isBootCompleted() {
                onStage(.booted)
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw MandroidKitError.timeout("Android did not finish booting")
    }
}
