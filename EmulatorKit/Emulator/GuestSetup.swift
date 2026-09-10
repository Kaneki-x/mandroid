import Foundation

/// One-time and every-boot guest tweaks.
public enum GuestSetup {
    /// Settings that make a phone image behave for a windowed desktop:
    /// hardware keyboard without the IME popping up, screen never sleeping.
    public static func apply(adb: ADBClient) async {
        let commands = [
            "settings put secure show_ime_with_hard_keyboard 0",
            "settings put system screen_off_timeout 2147483647",
            "svc power stayon true",
            "settings put global window_animation_scale 1.0",
        ]
        for c in commands {
            do { _ = try await adb.shell(c) } catch { Log.emulator.warning("guest setup '\(c)' failed: \(error.localizedDescription)") }
        }
    }
}
