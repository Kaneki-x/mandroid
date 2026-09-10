import AppKit
import EmulatorKit

/// One macOS window showing one emulator display: either an app on a
/// secondary display or the built-in device screen (display 0).
final class AppWindowController: NSWindowController, NSWindowDelegate {
    enum Target {
        case app(AppSession)
        case device
    }

    let coordinator: RunnerCoordinator
    private(set) var target: Target
    var onClose: (() -> Void)?

    private let frameView = FrameView(frame: .zero)
    private var frameTask: Task<Void, Never>?
    private var resizeDebounce: Task<Void, Never>?

    var emulatorDisplay: Int {
        if case .app(let s) = target { return s.slot.emulatorIndex } else { return 0 }
    }
    var androidDisplayID: Int {
        if case .app(let s) = target { return s.slot.androidDisplayID } else { return 0 }
    }
    private var pixelSize: (Int, Int) {
        switch target {
        case .app(let s): return (s.slot.width, s.slot.height)
        case .device: return (coordinator.session?.deviceWidth ?? 1080, coordinator.session?.deviceHeight ?? 2400)
        }
    }

    init(coordinator: RunnerCoordinator, target: Target, logicalSize: NSSize) {
        self.coordinator = coordinator
        self.target = target
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: logicalSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 240, height: 240)
        window.backgroundColor = .black
        window.contentView = frameView
        super.init(window: window)
        window.delegate = self
        switch target {
        case .app(let s):
            window.title = Self.displayName(for: s.package)
            window.setFrameAutosaveName("app:\(s.package)")
        case .device:
            window.title = "Device Screen"
            window.setFrameAutosaveName("device")
            window.contentAspectRatio = logicalSize
        }
        if window.frame.origin == .zero { window.center() }
        frameView.frame = window.contentView!.bounds
        configureInput()
        startFrames()
    }

    required init?(coder: NSCoder) { fatalError() }

    static func displayName(for package: String) -> String {
        // Phase 2 replaces this with aapt2 labels.
        let last = package.split(separator: ".").last.map(String.init) ?? package
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    // MARK: Input plumbing

    private func configureInput() {
        let (w, h) = pixelSize
        frameView.displayWidth = w
        frameView.displayHeight = h
        frameView.onTouch = { [weak self] x, y, id, pressure in
            guard let self, let session = coordinator.session else { return }
            let display = emulatorDisplay
            Task { await session.input.touch(display: display, x: x, y: y, identifier: id, pressure: pressure) }
        }
        frameView.onFirstTouch = { [weak self] in
            guard let self, let session = coordinator.session else { return }
            let id = androidDisplayID
            Task { await session.router.noteTouch(androidDisplayID: id) }
        }
        frameView.onKey = { [weak self] action in
            guard let self, let session = coordinator.session else { return }
            Task {
                await self.ensureFocus()
                await session.input.perform(action)
            }
        }
    }

    private func ensureFocus() async {
        guard let session = coordinator.session else { return }
        switch target {
        case .app(let s): await session.router.ensureKeyboardFocus(on: s)
        case .device: await session.router.ensureKeyboardFocusOnDeviceScreen()
        }
    }

    // MARK: Frames

    private func startFrames() {
        frameTask?.cancel()
        guard let session = coordinator.session else { return }
        let display = emulatorDisplay
        let (w, h) = pixelSize
        let stream = session.frames
        frameTask = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                do {
                    for try await frame in stream.frames(display: display, width: w, height: h) {
                        if Task.isCancelled { return }
                        self?.frameView.display(frame)
                    }
                    return
                } catch {
                    attempt += 1
                    Log.ui.warning("frame stream for display \(display) failed: \(error.localizedDescription)")
                    if attempt > 5 { return }
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        }
    }

    // MARK: Window delegate

    func windowDidBecomeKey(_ notification: Notification) {
        window?.makeFirstResponder(frameView)
        Task { await ensureFocus() }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard case .app = target else { return }
        scheduleReconfigure()
    }

    func windowDidResize(_ notification: Notification) {
        guard case .app = target, window?.inLiveResize == false else { return }
        scheduleReconfigure()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard case .app = target else { return }
        scheduleReconfigure()
    }

    /// Resizes the virtual display in place to the window's physical pixels
    /// (1 dp = 1 pt). Debounced so a drag produces a single reconfiguration.
    private func scheduleReconfigure() {
        resizeDebounce?.cancel()
        resizeDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, let window, case .app(let app) = target else { return }
            let scale = window.backingScaleFactor
            let size = frameView.bounds.size
            let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
            guard w != app.slot.width || h != app.slot.height else { return }
            do {
                let updated = try await coordinator.resizeApp(app, width: w, height: h, dpi: Int(160 * scale))
                target = .app(updated)
                configureInput()
                startFrames()
            } catch {
                Log.ui.error("resize failed: \(error.localizedDescription)")
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        frameTask?.cancel()
        resizeDebounce?.cancel()
        if case .app(let app) = target {
            Task { await coordinator.closeApp(app) }
        }
        onClose?()
    }

    // MARK: Menu actions

    @objc func androidBack(_ sender: Any?) { sendKey(.key("GoBack")) }
    @objc func androidHome(_ sender: Any?) { sendKey(.key("GoHome")) }
    @objc func androidRecents(_ sender: Any?) { sendKey(.key("AppSwitch")) }

    private func sendKey(_ action: KeyAction) {
        guard let session = coordinator.session else { return }
        Task {
            await ensureFocus()
            await session.input.perform(action)
        }
    }
}
