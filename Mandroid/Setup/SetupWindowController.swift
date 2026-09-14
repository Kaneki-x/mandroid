import AppKit
import MandroidKit
import SwiftUI

final class SetupWindowController: NSWindowController {
    init(coordinator: RunnerCoordinator) {
        let host = NSHostingController(rootView: SetupView(coordinator: coordinator))
        let window = NSWindow(contentViewController: host)
        window.title = "Mandroid"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
