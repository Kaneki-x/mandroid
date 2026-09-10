import AppKit
import EmulatorKit

/// `HostClipboard` over the general NSPasteboard.
struct PasteboardClipboard: HostClipboard {
    func changeCount() -> Int { NSPasteboard.general.changeCount }
    func readString() -> String? { NSPasteboard.general.string(forType: .string) }
    func writeString(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}
