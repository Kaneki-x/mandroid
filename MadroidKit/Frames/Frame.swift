import Foundation

/// One RGBA8888 frame, rows top-down, 4 bytes per pixel, no padding.
public struct Frame: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: Data
    public let sequence: UInt32
    public let timestampUs: UInt64

    public var bytesPerRow: Int { width * 4 }
    public var isComplete: Bool {
        guard width > 0, height > 0 else { return false }
        let (area, areaOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = area.multipliedReportingOverflow(by: 4)
        return !areaOverflow && !byteOverflow && pixels.count >= bytes
    }
}

/// Source of frames for one display. Implementations may drop frames when
/// the consumer is slower than the producer; sequence numbers expose gaps.
public protocol FrameStream: Sendable {
    /// Streams frames until cancelled or the emulator ends the stream.
    func frames(display: Int, width: Int, height: Int) -> AsyncThrowingStream<Frame, Error>
}
