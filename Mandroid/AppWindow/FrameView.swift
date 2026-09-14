import AppKit
import MandroidKit

/// Displays frames on a layer and forwards pointer, scroll and key input.
final class FrameView: NSView {
    var displayWidth = 1
    var displayHeight = 1
    var onTouch: ((_ x: Int, _ y: Int, _ identifier: Int, _ pressure: Int) -> Void)?
    var onKey: ((KeyAction) -> Void)?
    var onFirstTouch: (() -> Void)?

    private var scrollGesture: ScrollGesture?
    private var scrollIdleTimer: Timer?
    private var lastFrameSequence: UInt32 = 0
    private(set) var hasFrame = false
    private(set) var renderedPixelSize = NSSize.zero
    private var mouseIsDown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .trilinear
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    // MARK: Frames

    static func cgImage(_ frame: Frame) -> CGImage? {
        guard frame.isComplete, frame.width > 0, frame.height > 0,
              let provider = CGDataProvider(data: frame.pixels as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: frame.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    static func pngData(_ frame: Frame) -> Data? {
        guard let cg = cgImage(frame) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    func display(_ frame: Frame) {
        guard let image = Self.cgImage(frame) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
        renderedPixelSize = NSSize(width: frame.width, height: frame.height)
        hasFrame = true
        lastFrameSequence = frame.sequence
    }

    // MARK: Pointer

    private var mapper: CoordinateMapper {
        CoordinateMapper(viewWidth: bounds.width, viewHeight: bounds.height,
                         displayWidth: displayWidth, displayHeight: displayHeight)
    }

    private func point(_ event: NSEvent) -> (Int, Int) {
        let p = convert(event.locationInWindow, from: nil)
        return mapper.toDisplay(x: p.x, y: p.y)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        endScroll()
        mouseIsDown = true
        onFirstTouch?()
        let (x, y) = point(event)
        onTouch?(x, y, 0, 1000)
    }

    override func mouseDragged(with event: NSEvent) {
        guard mouseIsDown else { return }
        let (x, y) = point(event)
        onTouch?(x, y, 0, 1000)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseIsDown else { return }
        mouseIsDown = false
        let (x, y) = point(event)
        onTouch?(x, y, 0, 0)
    }

    override func rightMouseDown(with event: NSEvent) {
        // Right click = Back, a common desktop-Android convention.
        onKey?(.key("GoBack"))
    }

    // MARK: Scroll → synthesised drag

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || (event.phase == [] && event.momentumPhase == []) {
            // fresh gesture (or a legacy mouse wheel tick)
        }
        if event.phase == .ended || event.phase == .cancelled { scheduleScrollEnd(after: 0.05); return }
        if event.momentumPhase == .ended { endScroll(); return }
        let m = mapper
        let p = convert(event.locationInWindow, from: nil)
        var dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { dx *= 10; dy *= 10 }
        let d = m.deltaToDisplay(dx: dx, dy: dy)
        if scrollGesture == nil { scrollGesture = ScrollGesture(displayWidth: displayWidth, displayHeight: displayHeight) }
        let start = m.toDisplay(x: p.x, y: p.y)
        onFirstTouch?()
        for out in scrollGesture!.scroll(atX: start.x, y: start.y, dx: d.dx, dy: d.dy) {
            emit(out)
        }
        scheduleScrollEnd(after: 0.12)
    }

    private func emit(_ out: ScrollGesture.Output) {
        switch out {
        case .down(let x, let y), .move(let x, let y): onTouch?(x, y, ScrollGesture.identifier, 1000)
        case .up(let x, let y): onTouch?(x, y, ScrollGesture.identifier, 0)
        }
    }

    private func scheduleScrollEnd(after interval: TimeInterval) {
        scrollIdleTimer?.invalidate()
        scrollIdleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endScroll() }
        }
    }

    private func endScroll() {
        scrollIdleTimer?.invalidate(); scrollIdleTimer = nil
        if let out = scrollGesture?.end() { emit(out) }
        scrollGesture = nil
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let action = KeyMap.action(for: keyInput(event))
        if case .ignore = action { super.keyDown(with: event); return }
        onKey?(action)
    }

    override func keyUp(with event: NSEvent) {}

    /// ⌘ shortcuts that should reach Android instead of the menu bar.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        let action = KeyMap.action(for: keyInput(event))
        switch action {
        case .chord, .key:
            onKey?(action)
            return true
        default:
            return false
        }
    }

    private func keyInput(_ e: NSEvent) -> KeyInput {
        let f = e.modifierFlags
        return KeyInput(keyCode: e.keyCode, characters: e.characters ?? "",
                        charactersIgnoringModifiers: e.charactersIgnoringModifiers ?? "",
                        command: f.contains(.command), control: f.contains(.control),
                        option: f.contains(.option), shift: f.contains(.shift), isRepeat: e.isARepeat)
    }
}
