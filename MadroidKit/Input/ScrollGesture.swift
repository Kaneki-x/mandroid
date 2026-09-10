import Foundation

/// Turns trackpad scroll deltas into a synthesised touch drag. Android has
/// no wheel device on the phone image, so a two-finger scroll becomes a
/// finger that goes down where the cursor is, follows the accumulated
/// delta, and lifts after `idleTimeout` without new deltas.
public struct ScrollGesture: Sendable {
    public enum Output: Sendable, Equatable {
        case down(x: Int, y: Int)
        case move(x: Int, y: Int)
        case up(x: Int, y: Int)
    }

    public private(set) var isActive = false
    private var x: Double = 0, y: Double = 0
    private let maxX: Int, maxY: Int
    public static let identifier = 1  // separate from the mouse's identifier 0

    public init(displayWidth: Int, displayHeight: Int) {
        maxX = max(displayWidth - 1, 0); maxY = max(displayHeight - 1, 0)
    }

    /// `dx/dy` in display pixels (already scaled). Positive dy moves the
    /// finger down, matching AppKit's natural-scrolling sign convention.
    public mutating func scroll(atX startX: Int, y startY: Int, dx: Double, dy: Double) -> [Output] {
        var out: [Output] = []
        if !isActive {
            isActive = true
            x = Double(startX); y = Double(startY)
            out.append(.down(x: startX, y: startY))
        }
        x += dx; y += dy
        let cx = Int(x.rounded()).clamped(0, maxX), cy = Int(y.rounded()).clamped(0, maxY)
        out.append(.move(x: cx, y: cy))
        // If we ran into an edge, lift and restart so scrolling can continue.
        if cx != Int(x.rounded()) || cy != Int(y.rounded()) {
            out.append(.up(x: cx, y: cy))
            isActive = false
        }
        return out
    }

    public mutating func end() -> Output? {
        guard isActive else { return nil }
        isActive = false
        return .up(x: Int(x.rounded()).clamped(0, maxX), y: Int(y.rounded()).clamped(0, maxY))
    }
}
