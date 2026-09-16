import AppKit
import MandroidKit
import SwiftUI

final class LibraryWindowController: NSWindowController {
    let coordinator: RunnerCoordinator
    let windows: WindowManager

    init(coordinator: RunnerCoordinator, windows: WindowManager) {
        self.coordinator = coordinator
        self.windows = windows
        let host = NSHostingController(rootView: LibraryView(coordinator: coordinator, windows: windows))
        let window = NSWindow(contentViewController: host)
        window.title = "Library"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 480))
        window.contentMinSize = NSSize(width: 460, height: 320)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        if !UITestMode.enabled { window.setFrameAutosaveName("Library") }
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
