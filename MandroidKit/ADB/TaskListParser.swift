import Foundation

/// Parses `am stack list` for root tasks per display.
///
/// ```
/// RootTask id=28 bounds=[0,0][1080,2400] displayId=0 userId=0
///   taskId=28: com.android.settings/... visible=true ...
/// ```
public enum TaskListParser {
    public static func displaysWithTasks(_ text: String) -> Set<Int> {
        var out = Set<Int>()
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("RootTask"), let r = s.range(of: "displayId=") else { continue }
            let digits = s[r.upperBound...].prefix { $0.isNumber }
            if let id = Int(digits) { out.insert(id) }
        }
        return out
    }

    /// Package names that own a root task on `displayID`.
    public static func packages(onDisplay displayID: Int, in text: String) -> [String] {
        var result: [String] = []
        var current: Int?
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("RootTask") {
                current = s.range(of: "displayId=").flatMap { Int(s[$0.upperBound...].prefix { $0.isNumber }) }
            } else if current == displayID, s.hasPrefix("taskId="), let colon = s.firstIndex(of: ":") {
                let rest = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if let comp = rest.split(separator: " ").first, let slash = comp.firstIndex(of: "/") {
                    result.append(String(comp[..<slash]))
                }
            }
        }
        return result
    }
}
