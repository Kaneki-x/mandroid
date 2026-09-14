import Foundation

/// Keyboard focus policy. Android routes keys to the display that last
/// received a touch (spike item 5). The router remembers which display we
/// last touched and, when a window becomes key for a different display,
/// moves Android's focus by re-delivering the app's launcher intent on that
/// display (`am start --display`), which does not relaunch the activity.
public actor InputRouter {
    private let adb: ADBClient
    private var lastTouchedAndroidDisplay: Int?

    public init(adb: ADBClient) { self.adb = adb }

    public func noteTouch(androidDisplayID: Int) {
        lastTouchedAndroidDisplay = androidDisplayID
    }

    /// Ensures keys will land on `session`'s display. Cheap when the display
    /// is already focused.
    public func ensureKeyboardFocus(on session: AppSession) async {
        guard lastTouchedAndroidDisplay != session.slot.androidDisplayID else { return }
        do {
            try await adb.startActivity(component: session.launcherComponent, displayID: session.slot.androidDisplayID)
            lastTouchedAndroidDisplay = session.slot.androidDisplayID
        } catch {
            Log.input.warning("focus nudge failed: \(error.localizedDescription)")
        }
    }

    /// Display 0 (device screen window) has no launcher component; a focus
    /// move there uses the home launcher's task.
    public func ensureKeyboardFocusOnDeviceScreen() async {
        guard lastTouchedAndroidDisplay != 0 else { return }
        _ = try? await adb.shell("am start --display 0 -a android.intent.action.MAIN -c android.intent.category.HOME")
        lastTouchedAndroidDisplay = 0
    }

    public func forget(androidDisplayID: Int) {
        if lastTouchedAndroidDisplay == androidDisplayID { lastTouchedAndroidDisplay = nil }
    }
}
