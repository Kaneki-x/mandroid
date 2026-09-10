import Foundation

/// User-adjustable settings, persisted in `UserDefaults`.
public struct RunnerSettings: Sendable, Equatable {
    public var ramMB: Int = 4096
    public var cores: Int = 4
    public var defaultWindowHeight: Int = 900
    public var launcherStubs: Bool = true
    /// New app windows open in landscape ("horizontal") unless changed.
    public var landscapeByDefault: Bool = true

    public static let ramChoices = [2048, 3072, 4096, 6144, 8192]
    public static let coreChoices = [2, 4, 6, 8]

    public init() {}

    public static func load(from defaults: UserDefaults = .standard) -> RunnerSettings {
        var s = RunnerSettings()
        if let v = defaults.object(forKey: "ramMB") as? Int, ramChoices.contains(v) { s.ramMB = v }
        if let v = defaults.object(forKey: "cores") as? Int, coreChoices.contains(v) { s.cores = v }
        if let v = defaults.object(forKey: "defaultWindowHeight") as? Int, (500...1600).contains(v) { s.defaultWindowHeight = v }
        if let v = defaults.object(forKey: "launcherStubs") as? Bool { s.launcherStubs = v }
        if let v = defaults.object(forKey: "landscapeByDefault") as? Bool { s.landscapeByDefault = v }
        return s
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(ramMB, forKey: "ramMB")
        defaults.set(cores, forKey: "cores")
        defaults.set(defaultWindowHeight, forKey: "defaultWindowHeight")
        defaults.set(launcherStubs, forKey: "launcherStubs")
        defaults.set(landscapeByDefault, forKey: "landscapeByDefault")
    }

    /// Default logical size of a new app window given the usable screen size.
    /// Landscape: 16:10 with the height derived from `defaultWindowHeight`;
    /// portrait: a 420:900 phone rectangle.
    public func defaultWindowSize(screenWidth: Double, screenHeight: Double) -> (width: Double, height: Double) {
        let maxH = max(400, screenHeight - 40), maxW = max(400, screenWidth - 40)
        if landscapeByDefault {
            var h = min(Double(defaultWindowHeight) * 0.72, maxH)
            var w = (h * 1.6).rounded()
            if w > maxW { w = maxW; h = (w / 1.6).rounded() }
            return (w, h)
        } else {
            let h = min(Double(defaultWindowHeight), maxH)
            return ((h * 420 / 900).rounded(), h)
        }
    }

    /// Applies the hardware settings to an AVD config.
    public func apply(to config: inout AVDConfig) {
        config.ramMB = ramMB
        config.cores = cores
    }
}
