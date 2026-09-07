import Carbon
import Foundation

public let singleCharKeyCodes: [Character: UInt16] = [
    "a": UInt16(kVK_ANSI_A), "b": UInt16(kVK_ANSI_B), "c": UInt16(kVK_ANSI_C), "d": UInt16(kVK_ANSI_D),
    "e": UInt16(kVK_ANSI_E), "f": UInt16(kVK_ANSI_F), "g": UInt16(kVK_ANSI_G), "h": UInt16(kVK_ANSI_H),
    "i": UInt16(kVK_ANSI_I), "j": UInt16(kVK_ANSI_J), "k": UInt16(kVK_ANSI_K), "l": UInt16(kVK_ANSI_L),
    "m": UInt16(kVK_ANSI_M), "n": UInt16(kVK_ANSI_N), "o": UInt16(kVK_ANSI_O), "p": UInt16(kVK_ANSI_P),
    "q": UInt16(kVK_ANSI_Q), "r": UInt16(kVK_ANSI_R), "s": UInt16(kVK_ANSI_S), "t": UInt16(kVK_ANSI_T),
    "u": UInt16(kVK_ANSI_U), "v": UInt16(kVK_ANSI_V), "w": UInt16(kVK_ANSI_W), "x": UInt16(kVK_ANSI_X),
    "y": UInt16(kVK_ANSI_Y), "z": UInt16(kVK_ANSI_Z),
    "0": UInt16(kVK_ANSI_0), "1": UInt16(kVK_ANSI_1), "2": UInt16(kVK_ANSI_2), "3": UInt16(kVK_ANSI_3),
    "4": UInt16(kVK_ANSI_4), "5": UInt16(kVK_ANSI_5), "6": UInt16(kVK_ANSI_6), "7": UInt16(kVK_ANSI_7),
    "8": UInt16(kVK_ANSI_8), "9": UInt16(kVK_ANSI_9),
    "/": UInt16(kVK_ANSI_Slash), "\\": UInt16(kVK_ANSI_Backslash),
    "-": UInt16(kVK_ANSI_Minus), "=": UInt16(kVK_ANSI_Equal),
    "[": UInt16(kVK_ANSI_LeftBracket), "]": UInt16(kVK_ANSI_RightBracket),
    ";": UInt16(kVK_ANSI_Semicolon), "'": UInt16(kVK_ANSI_Quote),
    ",": UInt16(kVK_ANSI_Comma), ".": UInt16(kVK_ANSI_Period),
    "`": UInt16(kVK_ANSI_Grave),
]

/// Maps a key name to its Carbon virtual key code.
/// Accepts single characters (a-z, 0-9) and named keys
/// (space, return/enter, tab, escape/esc, up, down, left, right).
public func keyCodeFor(_ name: String) -> UInt16? {
    if name.count == 1, let c = name.first { return singleCharKeyCodes[c] }
    switch name {
    case "space":           return UInt16(kVK_Space)
    case "return", "enter": return UInt16(kVK_Return)
    case "tab":             return UInt16(kVK_Tab)
    case "escape", "esc":   return UInt16(kVK_Escape)
    case "up":              return UInt16(kVK_UpArrow)
    case "down":            return UInt16(kVK_DownArrow)
    case "left":            return UInt16(kVK_LeftArrow)
    case "right":           return UInt16(kVK_RightArrow)
    case "delete":          return UInt16(kVK_Delete)
    case "slash":           return UInt16(kVK_ANSI_Slash)
    case "backslash":       return UInt16(kVK_ANSI_Backslash)
    case "minus":           return UInt16(kVK_ANSI_Minus)
    case "equal", "equals": return UInt16(kVK_ANSI_Equal)
    case "comma":           return UInt16(kVK_ANSI_Comma)
    case "period", "dot":   return UInt16(kVK_ANSI_Period)
    case "grave", "backtick": return UInt16(kVK_ANSI_Grave)
    default:                return nil
    }
}

/// Maps a modifier name to its CGEventFlags value.
/// Accepts: opt/option/alt, cmd/command, ctrl/control, shift.
public func modifierFor(_ name: String) -> CGEventFlags? {
    switch name {
    case "opt", "option", "alt": return .maskAlternate
    case "cmd", "command":       return .maskCommand
    case "ctrl", "control":      return .maskControl
    case "shift":                return .maskShift
    default:                     return nil
    }
}

/// Parses a hotkey string like "opt+o" or "cmd+shift+k" into a key code
/// Parses comma-separated hotkey combos (e.g. "opt+tab,opt+k").
/// Returns nil if any combo is invalid.
public func parseHotkeys(_ trigger: String) -> [(keyCode: Int64, modifierMask: CGEventFlags)]? {
    let combos = trigger.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard !combos.isEmpty else { return nil }
    var result: [(Int64, CGEventFlags)] = []
    for combo in combos {
        guard let parsed = parseHotkey(combo) else { return nil }
        result.append(parsed)
    }
    return result
}

/// and modifier mask suitable for CGEvent tap registration.
/// Returns nil if any component is unrecognized.
public func parseHotkey(_ trigger: String) -> (keyCode: Int64, modifierMask: CGEventFlags)? {
    let parts = trigger.lowercased().split(separator: "+").map(String.init)
    guard !parts.isEmpty else { return nil }
    var modifiers: CGEventFlags = []
    for part in parts.dropLast() {
        guard let mod = modifierFor(part) else { return nil }
        modifiers.insert(mod)
    }
    guard let keyCode = keyCodeFor(parts.last!) else { return nil }
    return (Int64(keyCode), modifiers)
}
