import Foundation

/// Android's native STREAM_MUSIC range varies with the system image.
public struct MediaVolume: Sendable, Equatable {
    public let level: Int
    public let minimum: Int
    public let maximum: Int
    public var percent: Int {
        Int((100 * Double(level - minimum) / Double(maximum - minimum)).rounded())
    }
    public func level(forPercent percent: Int) -> Int {
        minimum + Int((Double(maximum - minimum) * Double(min(max(percent, 0), 100)) / 100).rounded())
    }
    public static func parse(_ output: String) -> MediaVolume? {
        let pattern = #"volume is (\d+) in range \[(\d+)\.\.(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) else { return nil }
        let values = (1...3).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: output) else { return nil }
            return Int(output[range])
        }
        guard values.count == 3, values[2] > values[1], (values[1]...values[2]).contains(values[0]) else { return nil }
        return MediaVolume(level: values[0], minimum: values[1], maximum: values[2])
    }
}
