import Foundation
import SwiftProtobuf

/// Host side of the clipboard, abstracted so MandroidKit stays AppKit-free.
public protocol HostClipboard: Sendable {
    /// Monotonic counter that changes whenever the host clipboard changes.
    func changeCount() -> Int
    func readString() -> String?
    func writeString(_ s: String)
}

/// Echo suppression for a two-way clipboard: whatever was last written in
/// one direction is ignored when it comes back from the other side.
public struct ClipboardEchoGuard: Sendable, Equatable {
    public private(set) var lastSentToGuest: String?
    public private(set) var lastReceivedFromGuest: String?
    public init() {}

    public func shouldAcceptFromGuest(_ text: String) -> Bool {
        !text.isEmpty && text != lastSentToGuest && text != lastReceivedFromGuest
    }
    public func shouldSendToGuest(_ text: String) -> Bool {
        !text.isEmpty && text != lastReceivedFromGuest && text != lastSentToGuest
    }
    public mutating func noteReceivedFromGuest(_ text: String) {
        lastReceivedFromGuest = text
        lastSentToGuest = nil
    }
    public mutating func noteSentToGuest(_ text: String) {
        lastSentToGuest = text
        lastReceivedFromGuest = nil
    }
}

/// Two-way text clipboard sync built on `ClipboardEchoGuard`.
public actor ClipboardSync {
    private let client: EmulatorClient
    private let host: any HostClipboard
    private var guardState = ClipboardEchoGuard()
    private var lastChangeCount: Int
    private var tasks: [Task<Void, Never>] = []

    public init(client: EmulatorClient, host: any HostClipboard) {
        self.client = client
        self.host = host
        self.lastChangeCount = host.changeCount()
    }

    public func start() {
        guard tasks.isEmpty else { return }
        tasks.append(Task { [weak self] in await self?.pumpGuestToHost() })
        tasks.append(Task { [weak self] in await self?.pumpHostToGuest() })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// Pushes the host clipboard now (e.g. when an app window becomes key).
    public func pushHostClipboard() async {
        guard let s = host.readString(), !s.isEmpty else { return }
        await send(s)
    }

    func shouldAcceptFromGuest(_ text: String) -> Bool { guardState.shouldAcceptFromGuest(text) }
    func shouldSendToGuest(_ text: String) -> Bool { guardState.shouldSendToGuest(text) }
    func noteReceivedFromGuest(_ text: String) { guardState.noteReceivedFromGuest(text) }
    func noteSentToGuest(_ text: String) { guardState.noteSentToGuest(text) }

    // MARK: Pumps

    private func send(_ text: String) async {
        guard shouldSendToGuest(text) else { return }
        do {
            try await client.setClipboard(text)
            noteSentToGuest(text)
        } catch {
            Log.runner.warning("clipboard → guest failed: \(error.localizedDescription)")
        }
    }

    private func pumpHostToGuest() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let count = host.changeCount()
            guard count != lastChangeCount else { continue }
            lastChangeCount = count
            if let s = host.readString() { await send(s) }
        }
    }

    private func pumpGuestToHost() async {
        let controller = client.controller
        while !Task.isCancelled {
            do {
                try await controller.streamClipboard(Google_Protobuf_Empty()) { response in
                    for try await clip in response.messages {
                        let text = clip.text
                        if await self.shouldAcceptFromGuest(text) {
                            await self.noteReceivedFromGuest(text)
                            self.host.writeString(text)
                            await self.bumpChangeCount()
                        }
                    }
                }
            } catch {
                if Task.isCancelled { return }
                Log.runner.warning("clipboard stream ended: \(error.localizedDescription); retrying")
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// After we write to the host clipboard its change count moves; swallow
    /// that so the host→guest pump does not echo it back.
    private func bumpChangeCount() { lastChangeCount = host.changeCount() }
}
