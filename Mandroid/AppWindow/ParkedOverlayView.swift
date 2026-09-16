import AppKit

/// Native controls over the retained guest frame; removed synchronously on resume.
final class ParkedOverlayView: NSView {
    var onResume: (() -> Void)?
    private let title = NSTextField(labelWithString: "App paused")
    private let detail = NSTextField(wrappingLabelWithString: "Paused to make room for another app. Resume to continue where you left off.")
    private let button = NSButton(title: "Resume", target: nil, action: nil)
    private let progress = NSProgressIndicator()

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        let panel = NSVisualEffectView()
        panel.material = .hudWindow
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 16
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.alignment = .center
        detail.alignment = .center
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 13)
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(resumeApp)
        button.setAccessibilityHelp("Resume this Android app. You can also press Return or Space.")
        progress.style = .spinning
        progress.controlSize = .small
        progress.isHidden = true
        let stack = NSStackView(views: [title, detail, progress, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: centerYAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -24),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func appear() {
        guard !HostStyle.reduceMotion else { return }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 1
        }
    }

    func setResuming(_ resuming: Bool, error: String? = nil) {
        button.isEnabled = !resuming
        title.stringValue = resuming ? "Resuming…" : "App paused"
        detail.stringValue = error ?? "Paused to make room for another app. Resume to continue where you left off."
        progress.isHidden = !resuming || HostStyle.reduceMotion
        if resuming && !HostStyle.reduceMotion { progress.startAnimation(nil) }
        else { progress.stopAnimation(nil) }
    }

    @objc private func resumeApp() { if button.isEnabled { onResume?() } }
    override func keyDown(with event: NSEvent) {
        if [UInt16(36), 49, 76].contains(event.keyCode), event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            resumeApp()
        } else { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(button) }
    override func scrollWheel(with event: NSEvent) {}
}
