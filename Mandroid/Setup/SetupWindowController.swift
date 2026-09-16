import AppKit
import MandroidKit
import SwiftUI

final class SetupWindowController: NSWindowController {
    init(coordinator: RunnerCoordinator) {
        let host = NSHostingController(rootView: SetupView(coordinator: coordinator))
        let window = NSWindow(contentViewController: host)
        window.title = "Mandroid"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.setContentSize(NSSize(width: 520, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
