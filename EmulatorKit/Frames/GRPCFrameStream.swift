import Foundation
import GRPCCore

/// `streamScreenshot` over gRPC. The emulator sends a frame only when the
/// display content changes and scales server-side to the requested size.
public struct GRPCFrameStream: FrameStream {
    let client: EmulatorClient
    public init(client: EmulatorClient) { self.client = client }

    public func frames(display: Int, width: Int, height: Int) -> AsyncThrowingStream<Frame, Error> {
        let (stream, continuation) = AsyncThrowingStream<Frame, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let controller = client.controller
        let task = Task {
            var format = PBImageFormat()
            format.format = .rgba8888
            format.display = UInt32(display)
            format.width = UInt32(width)
            format.height = UInt32(height)
            do {
                try await controller.streamScreenshot(format, options: EmulatorConnection.largeMessageOptions) { response in
                    for try await image in response.messages {
                        if Task.isCancelled { break }
                        let frame = Frame(width: Int(image.format.width), height: Int(image.format.height),
                                          pixels: image.image, sequence: image.seq, timestampUs: image.timestampUs)
                        guard frame.isComplete else { continue }
                        continuation.yield(frame)
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
