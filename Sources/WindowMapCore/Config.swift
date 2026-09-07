import Foundation
import Logging

public struct Config {
    // Global
    public var logLevel: LogLevel?
    public var panelOpacity: Double

    // Picker
    public var trigger: String
    public var quickTrigger: String
    public var gesture: String
    public var dismissGesture: String
    public var showPlusButtons: Bool
    public var centered: Bool
    public var panelX: Double
    public var panelY: Double
    public var columnWidth: Double
    public var minHeightRows: Int
    public var maxHeightRows: Int
    public var mruOrder: Bool
    public var clickOutside: String
    public var tabSwitch: String
    public var tabHoverDelay: Int

    // Actions (base keys)
    public var actionRename: String
    public var actionMove: String
    public var actionNew: String
    public var actionClose: String
    public var actionConfirm: String
    public var actionCancel: String

    // Action overrides (dotted keys, e.g. close.workspace = "x")
    public var actionCloseWindow: String?
    public var actionCloseWorkspace: String?
    public var actionCloseContext: String?
    public var actionRenameWindow: String?
    public var actionRenameWorkspace: String?
    public var actionRenameContext: String?
    public var actionMoveWindow: String?
    public var actionMoveWorkspace: String?
    public var actionMoveContext: String?
    public var actionNewWindow: String?
    public var actionNewWorkspace: String?
    public var actionNewContext: String?

    // Navigation
    public var navUp: String
    public var navDown: String
    public var navLeft: String
    public var navRight: String

    // Switcher
    public var switcherTrigger: String
    public var switcherVisibleRows: Int
    public var switcherWidth: Double

    // Launcher
    public var launcherPaths: [String]

    // Preview
    public var previewCacheLimit: Int
    public var previewBorder: Double
    public var previewBorderRadius: Double
    public var previewBorderCurve: String

    // MARK: - Loading

    private static let log = Log(module: "Config")

    /// Loads config from the given URL. Exits the process with a clear error
    /// message if the file is missing or any required value is absent/invalid.
    public static func load(from url: URL) -> Config {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            log.error("config not found: \(url.path)")
            exit(1)
        }
        let (config, warnings) = parse(content)
        for w in warnings { log.warning(w) }
        guard let config else { exit(1) }
        return config
    }

    /// Attempts to reload config from the given URL.
    /// Returns nil + warnings on failure (caller keeps previous config).
    /// Returns config + warnings on success.
    public static func reload(from url: URL) -> (Config?, [String]) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, ["config not found: \(url.path)"])
        }
        return parse(content)
    }

    /// Parses a TOML config string into a Config value.
    /// Returns nil + warnings listing all problems if any required value is
    /// missing or invalid. Returns config + warnings on success (warnings
    /// may still be present for non-fatal issues like duplicate triggers).
    public static func parse(_ content: String) -> (Config?, [String]) {
        // Optionals for all required fields — nil means "not yet seen"
        var logLevel: LogLevel? = nil
        var panelOpacity: Double? = nil

        var trigger: String? = nil
        var quickTrigger: String? = nil
        var centered: Bool? = nil
        var panelX: Double? = nil
        var panelY: Double? = nil
        var gesture: String = ""
        var dismissGesture: String = ""
        var showPlusButtons: Bool? = nil
        var minHeightRows: Int? = nil
        var maxHeightRows: Int? = nil
        var mruOrder: Bool? = nil
        var clickOutside: String? = nil
        var tabSwitch: String? = nil
        var tabHoverDelay: Int? = nil

        var actionRename: String? = nil
        var actionMove: String? = nil
        var actionNew: String? = nil
        var actionClose: String? = nil
        var actionConfirm: String? = nil
        var actionCancel: String? = nil

        var actionCloseWindow: String? = nil
        var actionCloseWorkspace: String? = nil
        var actionCloseContext: String? = nil
        var actionRenameWindow: String? = nil
        var actionRenameWorkspace: String? = nil
        var actionRenameContext: String? = nil
        var actionMoveWindow: String? = nil
        var actionMoveWorkspace: String? = nil
        var actionMoveContext: String? = nil
        var actionNewWindow: String? = nil
        var actionNewWorkspace: String? = nil
        var actionNewContext: String? = nil

        var navUp: String? = nil
        var navDown: String? = nil
        var navLeft: String? = nil
        var navRight: String? = nil

        var columnWidth: Double? = nil

        var switcherTrigger: String? = nil
        var switcherVisibleRows: Int? = nil
        var switcherWidth: Double? = nil

        var launcherPaths: [String]? = nil
        var previewCacheLimit: Int? = nil
        var previewBorder: Double? = nil
        var previewBorderRadius: Double? = nil
        var previewBorderCurve: String? = nil

        var warnings: [String] = []
        var section = ""

        var seenSections = Set<String>()

        for line in content.components(separatedBy: .newlines) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }

            // Section header
            if s.hasPrefix("[") && s.hasSuffix("]") {
                section = String(s.dropFirst().dropLast())
                if !seenSections.insert(section).inserted {
                    warnings.append("duplicate section [\(section)]")
                }
                continue
            }

            // Key = value
            guard let eq = s.firstIndex(of: "=") else { continue }
            let key = s[..<eq].trimmingCharacters(in: .whitespaces)
            var val = s[s.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            // Strip quoted string value
            if val.hasPrefix("\"") {
                let inner = val.dropFirst()
                if let close = inner.firstIndex(of: "\"") {
                    val = String(inner[..<close])
                }
            } else if let c = val.firstIndex(of: "#") {
                // Strip inline comment from unquoted values
                val = val[..<c].trimmingCharacters(in: .whitespaces)
            }

            switch (section, key) {
            // Global
            case ("", "log_level"):
                if let v = parseLogLevel(val) { logLevel = v }
                else { warnings.append("invalid log_level \"\(val)\"") }
            case ("", "panel_opacity"):
                if let v = Double(val) { panelOpacity = v }
                else { warnings.append("invalid panel_opacity \"\(val)\"") }

            // Picker
            case ("picker", "trigger"):        trigger = val
            case ("picker", "quick_trigger"):   quickTrigger = val
            case ("picker", "gesture"):         gesture = val
            case ("picker", "dismiss_gesture"): dismissGesture = val
            case ("picker", "show_plus_buttons"):
                if let v = parseBool(val) { showPlusButtons = v }
                else { warnings.append("invalid [picker] show_plus_buttons \"\(val)\"") }
            case ("picker", "centered"):
                if let v = parseBool(val) { centered = v }
                else { warnings.append("invalid [picker] centered \"\(val)\"") }
            case ("picker", "panel_x"):
                if let v = Double(val) { panelX = v }
                else { warnings.append("invalid [picker] panel_x \"\(val)\"") }
            case ("picker", "panel_y"):
                if let v = Double(val) { panelY = v }
                else { warnings.append("invalid [picker] panel_y \"\(val)\"") }
            case ("picker", "column_width"):
                if let v = Double(val), v > 0 { columnWidth = v }
                else { warnings.append("invalid [picker] column_width \"\(val)\"") }
            case ("picker", "min_height_rows"):
                if let v = Int(val), v > 0 { minHeightRows = v }
                else { warnings.append("invalid [picker] min_height_rows \"\(val)\"") }
            case ("picker", "max_height_rows"):
                if let v = Int(val), v > 0 { maxHeightRows = v }
                else { warnings.append("invalid [picker] max_height_rows \"\(val)\"") }
            case ("picker", "mru_order"):
                if let v = parseBool(val) { mruOrder = v }
                else { warnings.append("invalid [picker] mru_order \"\(val)\"") }
            case ("picker", "click_outside"):
                if ["confirm", "cancel"].contains(val) { clickOutside = val }
                else { warnings.append("invalid [picker] click_outside \"\(val)\" — use confirm or cancel") }
            case ("picker", "tab_switch"):
                if ["click", "hover"].contains(val) { tabSwitch = val }
                else { warnings.append("invalid [picker] tab_switch \"\(val)\" — use click or hover") }
            case ("picker", "tab_hover_delay"):
                if let v = Int(val), v >= 0 { tabHoverDelay = v }
                else { warnings.append("invalid [picker] tab_hover_delay \"\(val)\"") }

            // Actions (base keys)
            case ("actions", "rename"):  actionRename = val
            case ("actions", "move"):    actionMove = val
            case ("actions", "new"):     actionNew = val
            case ("actions", "close"):   actionClose = val
            case ("actions", "confirm"): actionConfirm = val
            case ("actions", "cancel"):  actionCancel = val

            // Action overrides (dotted keys)
            case ("actions", "close.window"):    actionCloseWindow = val
            case ("actions", "close.workspace"): actionCloseWorkspace = val
            case ("actions", "close.context"):   actionCloseContext = val
            case ("actions", "rename.window"):    actionRenameWindow = val
            case ("actions", "rename.workspace"): actionRenameWorkspace = val
            case ("actions", "rename.context"):   actionRenameContext = val
            case ("actions", "move.window"):    actionMoveWindow = val
            case ("actions", "move.workspace"): actionMoveWorkspace = val
            case ("actions", "move.context"):   actionMoveContext = val
            case ("actions", "new.window"):    actionNewWindow = val
            case ("actions", "new.workspace"): actionNewWorkspace = val
            case ("actions", "new.context"):   actionNewContext = val

            // Navigation
            case ("navigation", "up"):    navUp = val
            case ("navigation", "down"):  navDown = val
            case ("navigation", "left"):  navLeft = val
            case ("navigation", "right"): navRight = val

            // Switcher
            case ("switcher", "trigger"): switcherTrigger = val
            case ("switcher", "visible_rows"):
                if let v = Int(val), v > 0 { switcherVisibleRows = v }
                else { warnings.append("invalid [switcher] visible_rows \"\(val)\"") }
            case ("switcher", "width"):
                if let v = Double(val), v > 0 { switcherWidth = v }
                else { warnings.append("invalid [switcher] width \"\(val)\"") }

            // Launcher
            case ("launcher", "paths"):
                let parts = val.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if !parts.isEmpty { launcherPaths = parts }

            case ("preview", "cache_limit"):
                if let v = Int(val), v >= 1 { previewCacheLimit = v }
                else { warnings.append("invalid [preview] cache_limit \"\(val)\"") }
            case ("preview", "border"):
                if let v = Double(val), v >= 0 { previewBorder = v }
                else { warnings.append("invalid [preview] border \"\(val)\"") }
            case ("preview", "border_radius"):
                if let v = Double(val), v >= 0 { previewBorderRadius = v }
                else { warnings.append("invalid [preview] border_radius \"\(val)\"") }
            case ("preview", "border_curve"):
                if ["circular", "continuous"].contains(val) { previewBorderCurve = val }
                else { warnings.append("invalid [preview] border_curve \"\(val)\"") }

            default: break
            }
        }

        // Check all mandatory fields
        var missing: [String] = []
        if logLevel       == nil { missing.append("log_level") }
        if panelOpacity   == nil { missing.append("panel_opacity") }
        if trigger        == nil { missing.append("[picker] trigger") }
        if quickTrigger   == nil { missing.append("[picker] quick_trigger") }
        if showPlusButtons == nil { missing.append("[picker] show_plus_buttons") }
        if centered == nil { missing.append("[picker] centered") }
        if panelX == nil { missing.append("[picker] panel_x") }
        if panelY == nil { missing.append("[picker] panel_y") }
        if columnWidth == nil { missing.append("[picker] column_width") }
        if minHeightRows  == nil { missing.append("[picker] min_height_rows") }
        if maxHeightRows  == nil { missing.append("[picker] max_height_rows") }
        if mruOrder       == nil { missing.append("[picker] mru_order") }
        if clickOutside   == nil { missing.append("[picker] click_outside") }
        if tabSwitch      == nil { missing.append("[picker] tab_switch") }
        if tabHoverDelay  == nil { missing.append("[picker] tab_hover_delay") }
        if actionRename   == nil { missing.append("[actions] rename") }
        if actionMove     == nil { missing.append("[actions] move") }
        if actionNew      == nil { missing.append("[actions] new") }
        if actionClose    == nil { missing.append("[actions] close") }
        if actionConfirm  == nil { missing.append("[actions] confirm") }
        if actionCancel   == nil { missing.append("[actions] cancel") }
        if navUp          == nil { missing.append("[navigation] up") }
        if navDown        == nil { missing.append("[navigation] down") }
        if navLeft        == nil { missing.append("[navigation] left") }
        if navRight       == nil { missing.append("[navigation] right") }
        if switcherTrigger     == nil { missing.append("[switcher] trigger") }
        if switcherVisibleRows == nil { missing.append("[switcher] visible_rows") }
        if switcherWidth == nil { missing.append("[switcher] width") }
        if launcherPaths       == nil { missing.append("[launcher] paths") }
        if previewCacheLimit   == nil { missing.append("[preview] cache_limit") }
        if previewBorder       == nil { missing.append("[preview] border") }
        if previewBorderRadius == nil { missing.append("[preview] border_radius") }
        if previewBorderCurve  == nil { missing.append("[preview] border_curve") }

        for m in missing { warnings.append("missing required value \(m)") }
        guard missing.isEmpty else { return (nil, warnings) }

        var config = Config(
            logLevel: logLevel,
            panelOpacity: panelOpacity!,
            trigger: trigger!,
            quickTrigger: quickTrigger!,
            gesture: gesture,
            dismissGesture: dismissGesture,
            showPlusButtons: showPlusButtons!,
            centered: centered!,
            panelX: panelX!,
            panelY: panelY!,
            columnWidth: columnWidth!,
            minHeightRows: minHeightRows!,
            maxHeightRows: maxHeightRows!,
            mruOrder: mruOrder!,
            clickOutside: clickOutside!,
            tabSwitch: tabSwitch!,
            tabHoverDelay: tabHoverDelay!,
            actionRename: actionRename!,
            actionMove: actionMove!,
            actionNew: actionNew!,
            actionClose: actionClose!,
            actionConfirm: actionConfirm!,
            actionCancel: actionCancel!,
            actionCloseWindow: actionCloseWindow,
            actionCloseWorkspace: actionCloseWorkspace,
            actionCloseContext: actionCloseContext,
            actionRenameWindow: actionRenameWindow,
            actionRenameWorkspace: actionRenameWorkspace,
            actionRenameContext: actionRenameContext,
            actionMoveWindow: actionMoveWindow,
            actionMoveWorkspace: actionMoveWorkspace,
            actionMoveContext: actionMoveContext,
            actionNewWindow: actionNewWindow,
            actionNewWorkspace: actionNewWorkspace,
            actionNewContext: actionNewContext,
            navUp: navUp!,
            navDown: navDown!,
            navLeft: navLeft!,
            navRight: navRight!,
            switcherTrigger: switcherTrigger!,
            switcherVisibleRows: switcherVisibleRows!,
            switcherWidth: switcherWidth!,
            launcherPaths: launcherPaths!,
            previewCacheLimit: previewCacheLimit!,
            previewBorder: previewBorder!,
            previewBorderRadius: previewBorderRadius!,
            previewBorderCurve: previewBorderCurve!
        )

        // Validate trigger uniqueness
        if !config.quickTrigger.isEmpty && config.quickTrigger == config.trigger {
            warnings.append("quick_trigger \"\(config.quickTrigger)\" matches trigger — quick mode disabled")
            config.quickTrigger = ""
        }
        if !config.switcherTrigger.isEmpty &&
            (config.switcherTrigger == config.trigger || config.switcherTrigger == config.quickTrigger) {
            warnings.append("switcher trigger \"\(config.switcherTrigger)\" matches another trigger — switcher disabled")
            config.switcherTrigger = ""
        }

        // Validate action key uniqueness
        let actionKeys: [(String, String)] = [
            ("rename", config.actionRename), ("move", config.actionMove),
            ("new", config.actionNew), ("close", config.actionClose),
        ]
        for i in actionKeys.indices {
            for j in (i+1)..<actionKeys.count {
                let (nameA, keysA) = actionKeys[i]
                let (nameB, keysB) = actionKeys[j]
                let setA = Set(keysA.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                let setB = Set(keysB.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                let overlap = setA.intersection(setB).filter { !$0.isEmpty }
                for key in overlap {
                    warnings.append("[actions] \(nameA) and \(nameB) share key \"\(key)\"")
                }
            }
        }

        return (config, warnings)
    }

    // MARK: - Helpers

    private static func parseBool(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "true":  return true
        case "false": return false
        default:      return nil
        }
    }

    private static func parseLogLevel(_ s: String) -> LogLevel? {
        switch s.lowercased() {
        case "debug":           return .debug
        case "info":            return .info
        case "warn", "warning": return .warning
        case "error":           return .error
        default:                return nil
        }
    }
}
