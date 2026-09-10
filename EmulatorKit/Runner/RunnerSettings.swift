import Foundation

/// User-adjustable settings, persisted in `UserDefaults`.
public struct RunnerSettings: Sendable, Equatable {
    public var ramMB: Int = 4096
    public var cores: Int = 4
    public var defaultWindowHeight: Int = 900
    public var launcherStubs: Bool = true

    public static let ramChoices = [2048, 3072, 4096, 6144, 8192]
    public static let coreChoices = [2, 4, 6, 8]

    public init() {}

    public static func load(from defaults: UserDefaults = .standard) -> RunnerSettings {
        var s = RunnerSettings()
        if let v = defaults.object(forKey: "ramMB") as? Int, ramChoices.contains(v) { s.ramMB = v }
        if let v = defaults.object(forKey: "cores") as? Int, coreChoices.contains(v) { s.cores = v }
        if let v = defaults.object(forKey: "defaultWindowHeight") as? Int, (500...1600).contains(v) { s.defaultWindowHeight = v }
        if let v = defaults.object(forKey: "launcherStubs") as? Bool { s.launcherStubs = v }
        return s
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(ramMB, forKey: "ramMB")
        defaults.set(cores, forKey: "cores")
        defaults.set(defaultWindowHeight, forKey: "defaultWindowHeight")
        defaults.set(launcherStubs, forKey: "launcherStubs")
    }

    /// Applies the hardware settings to an AVD config.
    public func apply(to config: inout AVDConfig) {
        config.ramMB = ramMB
        config.cores = cores
    }
}
