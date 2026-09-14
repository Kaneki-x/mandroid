import Foundation

private final class FixtureAnchor {}

enum Fixtures {
    static func url(_ name: String) -> URL {
        let bundle = Bundle(for: FixtureAnchor.self)
        if let u = bundle.url(forResource: name, withExtension: nil) { return u }
        // Fallback when run outside Xcode resource copying.
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    }
    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }
    static func text(_ name: String) throws -> String { try String(contentsOf: url(name), encoding: .utf8) }
}
