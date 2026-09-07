import AppKit
import Logging
import SpreadsheetKit
import WindowMapCore

private let log = Log(module: "KeybindingTranslator")

/// Translates a domain Config into SpreadsheetKit KeyBindings.
///
/// Applies the automatic modifier pattern:
///   - letter alone      -> window action (close, moveRow)
///   - shift + letter    -> workspace action (addColumn)
///   - cmd + letter      -> context action (reserved for addTab/deleteTab)
///
/// Dotted overrides (e.g. config.actionCloseWorkspace) replace the
/// automatic shift+letter binding with the specified key combo.
public func translateKeybindings(from config: Config) -> KeyBindings {
    var keys = KeyBindings(
        up: parseKeyCombos(config.navUp),
        down: parseKeyCombos(config.navDown),
        left: parseKeyCombos(config.navLeft),
        right: parseKeyCombos(config.navRight),
        confirm: parseKeyCombos(config.actionConfirm),
        cancel: parseKeyCombos(config.actionCancel)
    )

    // All action keys get plain + shift + cmd variants.
    // The panel routes to the correct entity level based on modifier.
    keys.close = allModifierVariants(base: config.actionClose)
    keys.addColumn = allModifierVariants(base: config.actionNew)
    keys.moveRow = allModifierVariants(base: config.actionMove)
    keys.rename = allModifierVariants(base: config.actionRename)

    return keys
}

// MARK: - Helpers

/// Parses a comma-separated key combo string (e.g. "return,space") into
/// an array of KeyCombo values, dropping any that fail to parse.
private func parseKeyCombos(_ comboString: String) -> [KeyCombo] {
    comboString
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .compactMap { combo in
            guard let kc = parseKeyCombo(combo) else {
                log.warning("unrecognized key combo: \"\(combo)\"")
                return nil
            }
            return kc
        }
}

/// Resolves a key binding using either a dotted override or the automatic
/// modifier pattern applied to each base key.
///
/// If `override` is non-nil and non-empty, it is parsed as-is (it already
/// contains whatever modifiers the user wants). Otherwise, the base keys
/// are each combined with `modifiers` to form the automatic pattern.
private func allModifierVariants(base: String) -> [KeyCombo] {
    base.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .compactMap { key -> [KeyCombo]? in
            guard let keyCode = keyCodeFor(key) else {
                log.warning("unrecognized key: \"\(key)\"")
                return nil
            }
            return [
                KeyCombo(keyCode: keyCode, modifiers: []),
                KeyCombo(keyCode: keyCode, modifiers: .shift),
                KeyCombo(keyCode: keyCode, modifiers: .command),
            ]
        }
        .flatMap { $0 }
}

private func resolvedCombos(
    base: String,
    override: String?,
    modifiers: NSEvent.ModifierFlags
) -> [KeyCombo] {
    if let override, !override.isEmpty {
        return parseKeyCombos(override)
    }
    return base
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .compactMap { key in
            guard let keyCode = keyCodeFor(key) else {
                log.warning("unrecognized key: \"\(key)\"")
                return nil
            }
            return KeyCombo(keyCode: keyCode, modifiers: modifiers)
        }
}
