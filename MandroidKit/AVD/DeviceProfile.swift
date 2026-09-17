import Foundation

/// Display profiles for testing Android layouts on the built-in device screen.
public enum DeviceProfile: String, CaseIterable, Sendable {
    case tablet, phone, compactPhone, custom

    public var label: String {
        switch self {
        case .tablet: "Tablet"
        case .phone: "Phone"
        case .compactPhone: "Compact phone"
        case .custom: "Custom"
        }
    }

    public func display(widthDP: Int = 400, heightDP: Int = 900, density: Int = 320) -> DeviceDisplay {
        switch self {
        case .tablet: DeviceDisplay(widthDP: 1280, heightDP: 800, density: 320)
        case .phone: DeviceDisplay(widthDP: 400, heightDP: 900, density: 320)
        case .compactPhone: DeviceDisplay(widthDP: 360, heightDP: 640, density: 320)
        case .custom: DeviceDisplay(widthDP: widthDP, heightDP: heightDP, density: density)
        }
    }
}

public struct DeviceDisplay: Sendable, Equatable {
    public static let dimensionRange = 320...1600
    public static let densityRange = 120...480
    public let widthDP: Int
    public let heightDP: Int
    public let density: Int

    public init(widthDP: Int, heightDP: Int, density: Int) {
        self.widthDP = min(max(widthDP, Self.dimensionRange.lowerBound), Self.dimensionRange.upperBound)
        self.heightDP = min(max(heightDP, Self.dimensionRange.lowerBound), Self.dimensionRange.upperBound)
        self.density = min(max(density, Self.densityRange.lowerBound), Self.densityRange.upperBound)
    }

    public var widthPixels: Int { Int((Double(widthDP) * Double(density) / 160).rounded()) }
    public var heightPixels: Int { Int((Double(heightDP) * Double(density) / 160).rounded()) }
    public var summary: String { "\(widthDP) × \(heightDP) dp · \(widthPixels) × \(heightPixels) px · \(density) dpi" }
}
