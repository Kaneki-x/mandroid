import Foundation

/// The only place that creates, resizes and removes secondary displays.
/// Three slots (emulator indices 1…3). Every change pushes the complete
/// secondary set, then re-reads `dumpsys display` to learn the Android id.
public actor DisplaySlotPool {
    public static let capacity = 3

    private let client: EmulatorClient
    private let adb: ADBClient
    private var slots: [Int: DisplaySlot] = [:]    // by emulatorIndex

    public init(client: EmulatorClient, adb: ADBClient) {
        self.client = client
        self.adb = adb
    }

    public var activeSlots: [DisplaySlot] { slots.values.sorted { $0.emulatorIndex < $1.emulatorIndex } }
    public var freeCount: Int { Self.capacity - slots.count }

    /// Removes every secondary display. Called once after connecting because
    /// the emulator recreates displays persisted in the AVD `config.ini`.
    public func reset() async throws {
        slots = [:]
        try await client.setSecondaryDisplays([])
    }

    /// Creates a display of the given pixel size. Throws `.display` when all
    /// three slots are taken.
    public func acquire(width: Int, height: Int, dpi: Int) async throws -> DisplaySlot {
        guard let index = (1...Self.capacity).first(where: { slots[$0] == nil }) else {
            throw MadroidKitError.display("all \(Self.capacity) app windows are in use")
        }
        let (w, h, d) = Self.sanitize(width: width, height: height, dpi: dpi)
        var pending = slots
        pending[index] = DisplaySlot(emulatorIndex: index, androidDisplayID: -1, width: w, height: h, dpi: d)
        try await push(pending)
        let androidID = try await waitForAndroidDisplay(index: index, width: w, height: h)
        let slot = DisplaySlot(emulatorIndex: index, androidDisplayID: androidID, width: w, height: h, dpi: d)
        slots[index] = slot
        Log.display.info("acquired slot \(index) → android display \(androidID) \(w)x\(h)@\(d)")
        return slot
    }

    /// Resizes an existing display in place (the activity survives).
    public func resize(_ index: Int, width: Int, height: Int, dpi: Int) async throws -> DisplaySlot {
        guard var slot = slots[index] else { throw MadroidKitError.display("slot \(index) is not allocated") }
        let (w, h, d) = Self.sanitize(width: width, height: height, dpi: dpi)
        if slot.width == w, slot.height == h, slot.dpi == d { return slot }
        slot.width = w; slot.height = h; slot.dpi = d
        var pending = slots
        pending[index] = slot
        try await push(pending)
        slot.androidDisplayID = try await waitForAndroidDisplay(index: index, width: w, height: h)
        slots[index] = slot
        return slot
    }

    public func release(_ index: Int) async throws {
        guard slots[index] != nil else { return }
        slots[index] = nil
        try await push(slots)
        Log.display.info("released slot \(index)")
    }

    // MARK: Internals

    private func push(_ set: [Int: DisplaySlot]) async throws {
        let specs = set.values.sorted { $0.emulatorIndex < $1.emulatorIndex }
            .map { DisplaySpec(index: $0.emulatorIndex, width: $0.width, height: $0.height, dpi: $0.dpi) }
        try await client.setSecondaryDisplays(specs)
    }

    /// Polls `dumpsys display` until the display with the emulator's uniqueId
    /// (and, for resizes, the new size) shows up.
    private func waitForAndroidDisplay(index: Int, width: Int, height: Int) async throws -> Int {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            let displays = DumpsysDisplayParser.parse(try await adb.dumpsysDisplay())
            if let d = displays.first(where: { $0.emulatorIndex == index }),
               d.width == width, d.height == height {
                return d.displayID
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw MadroidKitError.timeout("Android did not report display \(index)")
    }

    /// Emulator limits: dpi 120…640, each side ≥ 320 dp, ≤ 7680 px.
    static func sanitize(width: Int, height: Int, dpi: Int) -> (Int, Int, Int) {
        let d = min(max(dpi, 120), 640)
        let minPx = Int((320.0 * Double(d) / 160.0).rounded(.up))
        var w = min(max(width, minPx), 7680)
        var h = min(max(height, minPx), 7680)
        // Even sizes keep video encoders and the emulator's scaler happy.
        w &= ~1; h &= ~1
        return (w, h, d)
    }
}
