import AppKit
import EmulatorKit
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
        window.setContentSize(NSSize(width: 520, height: 420))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Library")
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
