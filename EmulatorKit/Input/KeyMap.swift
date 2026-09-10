import Foundation

/// A keyboard event described without AppKit types so it can be unit tested.
public struct KeyInput: Sendable, Hashable {
    public var keyCode: UInt16              // macOS virtual key code
    public var characters: String           // NSEvent.characters
    public var charactersIgnoringModifiers: String
    public var command: Bool
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var isRepeat: Bool

    public init(keyCode: UInt16, characters: String, charactersIgnoringModifiers: String,
                command: Bool = false, control: Bool = false, option: Bool = false, shift: Bool = false,
                isRepeat: Bool = false) {
        self.keyCode = keyCode; self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.command = command; self.control = control; self.option = option; self.shift = shift
        self.isRepeat = isRepeat
    }
}

/// What to send to the emulator for a key press.
public enum KeyAction: Sendable, Hashable {
    /// Unicode text through `KeyboardEvent.text`.
    case text(String)
    /// A single DOM key name (`Enter`, `ArrowLeft`, `GoBack`…) as down + up.
    case key(String)
    /// A modifier chord, e.g. `["Control", "c"]`: downs in order, ups reversed.
    case chord([String])
    /// Handled by macOS (menu shortcut) or nothing to send.
    case ignore
}

public enum KeyMap {
    // macOS virtual key codes (Carbon HIToolbox Events.h)
    static let special: [UInt16: String] = [
        36: "Enter", 76: "Enter", 51: "Backspace", 117: "Delete", 48: "Tab",
        123: "ArrowLeft", 124: "ArrowRight", 125: "ArrowDown", 126: "ArrowUp",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
    ]

    public static func action(for k: KeyInput) -> KeyAction {
        // ⌘ shortcuts we translate to Android navigation; everything else
        // with ⌘ belongs to the macOS menu bar.
        if k.command {
            switch k.charactersIgnoringModifiers {
            case "[": return .key("GoBack")
            case "h" where k.shift: return .key("GoHome")
            case "c" where !k.shift && !k.option: return .chord(["Control", "c"])
            case "v" where !k.shift && !k.option: return .chord(["Control", "v"])
            case "x" where !k.shift && !k.option: return .chord(["Control", "x"])
            case "a" where !k.shift && !k.option: return .chord(["Control", "a"])
            case "z" where !k.option: return .chord(k.shift ? ["Control", "Shift", "z"] : ["Control", "z"])
            default: return .ignore
            }
        }
        if k.keyCode == 53 { return .key("GoBack") }          // Escape
        if let name = special[k.keyCode] {
            if k.shift, name.hasPrefix("Arrow") { return .chord(["Shift", name]) }
            return .key(name)
        }
        if k.control, let c = k.charactersIgnoringModifiers.first, c.isLetter {
            return .chord(["Control", String(c).lowercased()])
        }
        // Printable text (includes space and option-composed characters).
        let text = k.characters
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f && !($0.value >= 0xF700 && $0.value <= 0xF8FF) }) else {
            return .ignore
        }
        return .text(text)
    }
}
