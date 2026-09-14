import AppKit
import MandroidKit

/// Handles `mandroid://` URLs.
///
/// - `mandroid://launch/<package>` opens (or focuses) an app window
/// - `mandroid://device` shows the device screen
/// - `mandroid://library` shows the library
///
/// Debug builds add `mandroid://debug/...` hooks used by
/// `Scripts/integration-test.sh` to drive the UI without accessibility
/// permissions (see `DebugHooks`).
@MainActor
struct URLSchemeHandler {
    let delegate: AppDelegate

    func handle(_ url: URL) {
        guard ["mandroid", "madroid", "androidapprunner"].contains(url.scheme?.lowercased() ?? "") else { return }
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
    func whenReady(_ action: @escaping @MainActor () -> Void) {
        let coordinator = delegate.coordinator
        Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(300)
            while !coordinator.state.isReady && ContinuousClock.now < deadline {
                if case .failed = coordinator.state { return }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
            if coordinator.state.isReady { action() } else {
                delegate.windows.presentError(MandroidKitError.timeout("Android did not become ready"), title: "Could not complete request")
            }
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
