import Foundation

/// A secondary emulator display that is currently allocated to a window.
public struct DisplaySlot: Sendable, Hashable, Identifiable {
    public var id: Int { emulatorIndex }
    public let emulatorIndex: Int      // 1…3, what gRPC calls `display`
    public var androidDisplayID: Int   // what `am start --display` wants
    public var width: Int              // pixels
    public var height: Int
    public var dpi: Int

    public init(emulatorIndex: Int, androidDisplayID: Int, width: Int, height: Int, dpi: Int) {
        self.emulatorIndex = emulatorIndex
        self.androidDisplayID = androidDisplayID
        self.width = width; self.height = height; self.dpi = dpi
    }
}

/// A running app bound to a slot.
public struct AppSession: Sendable, Hashable, Identifiable {
    public var id: String { package }
    public let package: String
    public let launcherComponent: String
    public var slot: DisplaySlot

    public init(package: String, launcherComponent: String, slot: DisplaySlot) {
        self.package = package; self.launcherComponent = launcherComponent; self.slot = slot
    }
}
