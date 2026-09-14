import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf

public typealias EmulatorControllerClient =
    Android_Emulation_Control_EmulatorController.Client<HTTP2ClientTransport.Posix>

/// Long-lived gRPC client to one emulator's `EmulatorController` on
/// loopback. `withGRPCClient` is scoped, so the client is owned here and
/// its connection loop runs in a detached task until `shutdown()`.
public final class EmulatorConnection: Sendable {
    public let port: Int
    private let grpc: GRPCClient<HTTP2ClientTransport.Posix>
    private let runTask: Task<Void, Never>
    public let controller: EmulatorControllerClient

    /// Call options for screenshot RPCs. The NIO transport sizes its inbound
    /// decoder from `maxRequestMessageBytes` (spike item 10), so both limits
    /// are raised to 256 MiB to fit the largest supported 7680×7680 RGBA
    /// display (225 MiB), including the protobuf envelope.
    public static var largeMessageOptions: CallOptions {
        var o = CallOptions.defaults
        o.maxRequestMessageBytes = 256 << 20
        o.maxResponseMessageBytes = 256 << 20
        return o
    }

    public init(port: Int) throws {
        self.port = port
        let transport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: "127.0.0.1", port: port),
            transportSecurity: .plaintext
        )
        let grpc = GRPCClient(transport: transport)
        self.grpc = grpc
        self.controller = EmulatorControllerClient(wrapping: grpc)
        self.runTask = Task.detached {
            do { try await grpc.runConnections() } catch {
                Log.grpc.error("gRPC connection loop ended: \(error.localizedDescription)")
            }
        }
    }

    /// Polls `getStatus` until the emulator answers or the deadline passes.
    public func waitUntilReachable(timeout: Duration = .seconds(120)) async throws {
        let deadline = ContinuousClock.now + timeout
        var lastError: Error?
        while ContinuousClock.now < deadline {
            do {
                var opts = CallOptions.defaults
                opts.timeout = .seconds(3)
                _ = try await controller.getStatus(Google_Protobuf_Empty(), options: opts)
                return
            } catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw MadroidKitError.timeout("emulator gRPC on port \(port) (\(lastError?.localizedDescription ?? "no answer"))")
    }

    public func shutdown() {
        grpc.beginGracefulShutdown()
        runTask.cancel()
    }

    deinit { shutdown() }
}
