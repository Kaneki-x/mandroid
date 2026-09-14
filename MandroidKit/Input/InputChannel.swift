import Foundation
import GRPCCore

/// Owns the single `streamInputEvent` bidirectional stream of an emulator and
/// serialises touches and keys onto it in order. If the stream dies it is
/// reopened on the next event.
public actor InputChannel {
    private let client: EmulatorClient
    private var continuation: AsyncStream<PBInputEvent>.Continuation?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    public init(client: EmulatorClient) { self.client = client }

    private func ensureOpen() {
        if continuation != nil, task?.isCancelled == false { return }
        let (stream, cont) = AsyncStream<PBInputEvent>.makeStream(bufferingPolicy: .unbounded)
        continuation = cont
        let generation = UUID()
        self.generation = generation
        let controller = client.controller
        task = Task { [weak self] in
            do {
                try await controller.streamInputEvent { writer in
                    for await event in stream { try await writer.write(event) }
                } onResponse: { _ in }
            } catch {
                Log.input.error("input stream closed: \(error.localizedDescription)")
            }
            await self?.streamEnded(generation: generation)
        }
    }

    private func streamEnded(generation: UUID) {
        guard self.generation == generation else { return }
        continuation?.finish()
        continuation = nil
        task = nil
    }

    private func send(_ event: PBInputEvent) {
        ensureOpen()
        continuation?.yield(event)
    }

    public func close() {
        continuation?.finish()
        continuation = nil
        task?.cancel()
        task = nil
    }

    // MARK: Touch

    /// `pressure` 0 = up, anything else = down/move.
    public func touch(display: Int, x: Int, y: Int, identifier: Int = 0, pressure: Int) {
        var t = PBTouch()
        t.x = Int32(x); t.y = Int32(y); t.identifier = Int32(identifier); t.pressure = Int32(pressure)
        var te = PBTouchEvent()
        te.touches = [t]
        te.display = Int32(display)
        var e = PBInputEvent()
        e.touchEvent = te
        send(e)
    }

    /// Multiple simultaneous touches (e.g. pinch).
    public func touches(display: Int, points: [(x: Int, y: Int, identifier: Int, pressure: Int)]) {
        var te = PBTouchEvent()
        te.touches = points.map { p in
            var t = PBTouch()
            t.x = Int32(p.x); t.y = Int32(p.y); t.identifier = Int32(p.identifier); t.pressure = Int32(p.pressure)
            return t
        }
        te.display = Int32(display)
        var e = PBInputEvent()
        e.touchEvent = te
        send(e)
    }

    // MARK: Keys

    public func perform(_ action: KeyAction) {
        switch action {
        case .ignore: return
        case .text(let s):
            var k = PBKeyboardEvent(); k.eventType = .keypress; k.text = s
            sendKey(k)
        case .key(let name):
            var k = PBKeyboardEvent(); k.key = name
            k.eventType = .keydown; sendKey(k)
            k.eventType = .keyup; sendKey(k)
        case .chord(let names):
            for n in names { var k = PBKeyboardEvent(); k.key = n; k.eventType = .keydown; sendKey(k) }
            for n in names.reversed() { var k = PBKeyboardEvent(); k.key = n; k.eventType = .keyup; sendKey(k) }
        }
    }

    private func sendKey(_ k: PBKeyboardEvent) {
        var e = PBInputEvent()
        e.keyEvent = k
        send(e)
    }
}
