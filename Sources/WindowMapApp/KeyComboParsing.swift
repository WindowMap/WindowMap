import AppKit
import SpreadsheetKit
import WindowMapCore

/// Maps a modifier name to its NSEvent.ModifierFlags value.
private func nsModifierFor(_ name: String) -> NSEvent.ModifierFlags? {
    switch name {
    case "opt", "option", "alt": return .option
    case "cmd", "command":       return .command
    case "ctrl", "control":      return .control
    case "shift":                return .shift
    default:                     return nil
    }
}

/// Parses a key combo string like "shift+n", "r", or "return" into a
/// SpreadsheetKit KeyCombo (UInt16 keyCode + NSEvent.ModifierFlags).
/// Returns nil if any component is unrecognized.
public func parseKeyCombo(_ s: String) -> KeyCombo? {
    let parts = s.lowercased().split(separator: "+").map(String.init)
    guard !parts.isEmpty else { return nil }
    var modifiers: NSEvent.ModifierFlags = []
    for part in parts.dropLast() {
        guard let mod = nsModifierFor(part) else { return nil }
        modifiers.insert(mod)
    }
    guard let keyCode = keyCodeFor(parts.last!) else { return nil }
    return KeyCombo(keyCode: keyCode, modifiers: modifiers)
}
