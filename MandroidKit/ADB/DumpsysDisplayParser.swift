import Foundation

/// One logical display as reported by `dumpsys display`.
public struct AndroidDisplay: Sendable, Hashable {
    public var displayID: Int
    public var uniqueID: String
    public var name: String
    public var width: Int
    public var height: Int
    public var densityDpi: Int?

    /// Emulator secondary display index (1…3) derived from the uniqueId
    /// `virtual:com.android.emulator.multidisplay:123456<N+1>`; nil for the
    /// built-in display.
    public var emulatorIndex: Int? {
        let prefix = "virtual:com.android.emulator.multidisplay:"
        guard uniqueID.hasPrefix(prefix), let n = Int(uniqueID.dropFirst(prefix.count)) else { return nil }
        let idx = n - 1234561
        return (1...3).contains(idx) ? idx : nil
    }
}

/// Extracts logical displays from `dumpsys display` text. Only the
/// `mBaseDisplayInfo=DisplayInfo{…}` lines are used; they carry the logical
/// id, uniqueId and real size in a stable format across API 31–36.
public enum DumpsysDisplayParser {
    public static func parse(_ text: String) -> [AndroidDisplay] {
        var result: [AndroidDisplay] = []
        var seen = Set<Int>()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("mBaseDisplayInfo=DisplayInfo{") else { continue }
            guard let id = int(after: "displayId ", in: line),
                  let unique = quoted(after: "uniqueId \"", in: line),
                  let (w, h) = size(after: "real ", in: line) else { continue }
            let name = quoted(after: "DisplayInfo{\"", in: line) ?? ""
            let density = int(after: "density ", in: line)
            if seen.insert(id).inserted {
                result.append(AndroidDisplay(displayID: id, uniqueID: unique, name: name, width: w, height: h, densityDpi: density))
            }
        }
        return result.sorted { $0.displayID < $1.displayID }
    }

    private static func int(after marker: String, in s: String) -> Int? {
        guard let r = s.range(of: marker) else { return nil }
        let digits = s[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    private static func quoted(after marker: String, in s: String) -> String? {
        guard let r = s.range(of: marker) else { return nil }
        let rest = s[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func size(after marker: String, in s: String) -> (Int, Int)? {
        guard let r = s.range(of: marker) else { return nil }
        let rest = s[r.upperBound...]
        guard let rawSize = rest.split(separator: ",", maxSplits: 1).first else { return nil }
        let comps = rawSize.split(separator: " ")
        guard comps.count >= 3, comps[1] == "x", let w = Int(comps[0]), let h = Int(comps[2]) else { return nil }
        return (w, h)
    }
}
