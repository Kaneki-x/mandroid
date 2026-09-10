import Foundation

/// Maps points in a top-left-origin view of `viewSize` (points) onto a
/// display of `displaySize` (pixels) that is drawn aspect-fit and centred.
public struct CoordinateMapper: Sendable, Hashable {
    public var viewWidth: Double
    public var viewHeight: Double
    public var displayWidth: Int
    public var displayHeight: Int

    public init(viewWidth: Double, viewHeight: Double, displayWidth: Int, displayHeight: Int) {
        self.viewWidth = viewWidth; self.viewHeight = viewHeight
        self.displayWidth = displayWidth; self.displayHeight = displayHeight
    }

    /// Scale from display pixels to view points and the letterbox offset.
    public var fit: (scale: Double, offsetX: Double, offsetY: Double) {
        guard displayWidth > 0, displayHeight > 0, viewWidth > 0, viewHeight > 0 else { return (1, 0, 0) }
        let scale = min(viewWidth / Double(displayWidth), viewHeight / Double(displayHeight))
        let drawnW = Double(displayWidth) * scale, drawnH = Double(displayHeight) * scale
        return (scale, (viewWidth - drawnW) / 2, (viewHeight - drawnH) / 2)
    }

    /// View point → display pixel, clamped to the display bounds.
    public func toDisplay(x: Double, y: Double) -> (x: Int, y: Int) {
        let f = fit
        let px = (x - f.offsetX) / f.scale
        let py = (y - f.offsetY) / f.scale
        return (Int(px.rounded()).clamped(0, displayWidth - 1), Int(py.rounded()).clamped(0, displayHeight - 1))
    }

    /// Converts a delta in view points to display pixels (no clamping).
    public func deltaToDisplay(dx: Double, dy: Double) -> (dx: Double, dy: Double) {
        let s = fit.scale
        return (dx / s, dy / s)
    }
}

extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(Swift.max(self, lo), Swift.max(lo, hi)) }
}
