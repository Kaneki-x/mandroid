import Foundation

/// Parses `pm list packages` output (`package:com.example`).
public enum PackageListParser {
    public static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("package:") }
            .map { String($0.dropFirst("package:".count)) }
            .sorted()
    }
}
