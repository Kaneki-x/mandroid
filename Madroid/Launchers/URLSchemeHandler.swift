import AppKit
import MadroidKit

/// Handles `madroid://` URLs.
///
/// - `madroid://launch/<package>` opens (or focuses) an app window
/// - `madroid://device` shows the device screen
/// - `madroid://library` shows the library
///
/// Debug builds add `madroid://debug/...` hooks used by
/// `Scripts/integration-test.sh` to drive the UI without accessibility
/// permissions (see `DebugHooks`).
@MainActor
struct URLSchemeHandler {
    let delegate: AppDelegate

    func handle(_ url: URL) {
        guard url.scheme == "madroid" else { return }
        let host = url.host ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        Log.ui.info("url \(url.absoluteString, privacy: .public)")
        switch host {
        case "launch":
            guard let pkg = parts.first else { return }
            whenReady { delegate.windows.open(package: pkg) }
        case "device":
            whenReady { delegate.windows.showDeviceScreen() }
        case "library":
            delegate.showLibrary()
        #if DEBUG
        case "debug":
            DebugHooks(delegate: delegate).handle(path: parts, query: url.queryItems)
        #endif
        default:
            break
        }
    }

    /// Runs `action` once the emulator is booted (waits up to 5 minutes).
    private func whenReady(_ action: @escaping @MainActor () -> Void) {
        let coordinator = delegate.coordinator
        Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(300)
            while !coordinator.state.isReady && ContinuousClock.now < deadline {
                if case .failed = coordinator.state { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if coordinator.state.isReady { action() }
        }
    }
}

extension URL {
    var queryItems: [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            out[item.name] = item.value ?? ""
        }
        return out
    }
}
