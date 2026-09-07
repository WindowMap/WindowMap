import AppKit
import Logging

public struct KeyCombo: Equatable {
    public let keyCode: UInt16
    public let modifiers: NSEvent.ModifierFlags

    private static let ignoredModifiers: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function]

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers.subtracting(KeyCombo.ignoredModifiers)
    }

    public func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        self.keyCode == keyCode
            && modifiers.subtracting(KeyCombo.ignoredModifiers).intersection([.shift, .control, .option, .command])
                == self.modifiers.intersection([.shift, .control, .option, .command])
    }
}

public struct KeyBindings {
    public var up: [KeyCombo]
    public var down: [KeyCombo]
    public var left: [KeyCombo]
    public var right: [KeyCombo]
    public var confirm: [KeyCombo]
    public var cancel: [KeyCombo]
    public var addColumn: [KeyCombo]
    public var close: [KeyCombo]
    public var moveRow: [KeyCombo]
    public var rename: [KeyCombo]

    public init(
        up: [KeyCombo] = [KeyCombo(keyCode: 126)],
        down: [KeyCombo] = [KeyCombo(keyCode: 125)],
        left: [KeyCombo] = [KeyCombo(keyCode: 123)],
        right: [KeyCombo] = [KeyCombo(keyCode: 124)],
        confirm: [KeyCombo] = [KeyCombo(keyCode: 36)],
        cancel: [KeyCombo] = [KeyCombo(keyCode: 53)],
        addColumn: [KeyCombo] = [],
        close: [KeyCombo] = [],
        moveRow: [KeyCombo] = [],
        rename: [KeyCombo] = []
    ) {
        self.up = up; self.down = down; self.left = left; self.right = right
        self.confirm = confirm; self.cancel = cancel
        self.addColumn = addColumn; self.close = close
        self.moveRow = moveRow; self.rename = rename
    }

    private static let actionMap: [(WritableKeyPath<KeyBindings, [KeyCombo]>, SpreadsheetAction)] = [
        (\.up, .keyDown(.up)), (\.down, .keyDown(.down)),
        (\.left, .keyDown(.left)), (\.right, .keyDown(.right)),
        (\.confirm, .keyDown(.confirm)), (\.cancel, .keyDown(.cancel)),
        (\.addColumn, .dataAction(.addColumn)),
        (\.close, .dataAction(.close)),
        (\.moveRow, .dataAction(.moveRow)),
        (\.rename, .dataAction(.rename)),
    ]

    public func action(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> SpreadsheetAction? {
        for (path, action) in KeyBindings.actionMap {
            if self[keyPath: path].contains(where: { $0.matches(keyCode: keyCode, modifiers: modifiers) }) {
                return action
            }
        }
        return nil
    }
}

public class SpreadsheetPanel: NSPanel {
    public var state: SpreadsheetState
    public weak var dataSource: SpreadsheetDataSource?
    public weak var spreadsheetDelegate: SpreadsheetDelegate?
    public var keys = KeyBindings()
    public var onStateChanged: (() -> Void)?
    public var onDismiss: (() -> Void)?
    public var tabSwitchOnHover = false
    public var tabHoverDelay: Double = 0.2

    public let spreadsheetView: SpreadsheetView
    public var layout: LayoutConfig { spreadsheetView.layout }
    private let log = Log(module: "SpreadsheetPanel")
    private weak var showScreen: NSScreen?
    private let effect: NSVisualEffectView
    private var mouseMoveMonitor: Any?
    private var editKeyMonitor: Any?
    private let nameEditor: NSTextField
    private let infoLabel: NSTextField
    private static let infoBarHeight: CGFloat = 22

    public var infoText: String? {
        didSet {
            infoLabel.stringValue = infoText ?? ""
            infoLabel.isHidden = infoText == nil
        }
    }

    private var infoBarHeight: CGFloat {
        infoText != nil ? Self.infoBarHeight : 0
    }

    public init(state: SpreadsheetState, layout: LayoutConfig = LayoutConfig()) {
        self.state = state
        self.spreadsheetView = SpreadsheetView(frame: .zero, layout: layout)
        self.nameEditor = NSTextField()
        self.infoLabel = NSTextField(labelWithString: "")

        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        self.effect = NSVisualEffectView(frame: rect)

        super.init(contentRect: rect,
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        level = .popUpMenu
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .transient]

        let container = NSView(frame: rect)
        container.wantsLayer = true
        container.layer!.cornerRadius = 12
        container.layer!.cornerCurve = .continuous
        container.layer!.masksToBounds = true
        contentView = container

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        effect.addSubview(spreadsheetView)

        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byTruncatingMiddle
        infoLabel.isHidden = true
        effect.addSubview(infoLabel)

        nameEditor.isBezeled = false
        nameEditor.isBordered = false
        nameEditor.isEditable = true
        nameEditor.drawsBackground = true
        nameEditor.backgroundColor = .textBackgroundColor
        nameEditor.focusRingType = .none
        nameEditor.isHidden = true
        nameEditor.wantsLayer = true
        nameEditor.layer?.cornerRadius = 5
        nameEditor.layer?.borderWidth = 2
        nameEditor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        effect.addSubview(nameEditor)
    }

    public func show(on screen: NSScreen, layout: LayoutConfig? = nil, maxColumns: Int? = nil) {
        let l = layout ?? LayoutConfig.forScreen(screen)
        spreadsheetView.layout = l
        showScreen = screen

        let sf = screen.visibleFrame
        let topY = sf.origin.y + sf.height * (1 - l.panelY)

        // Vertical clamp: max rows that fit between panel_y and screen bottom
        let availableHeight = topY - screen.frame.origin.y
        let nonRowHeight = tabStripTotalHeight + spreadsheetView.headerHeight + spreadsheetView.hairlineH + infoBarHeight
        let screenMaxRows = max(Int((availableHeight - nonRowHeight) / spreadsheetView.rowHeight), 1)

        let marginPx = sf.width * l.panelX
        let availableWidth = sf.width - marginPx * 2

        layoutForState(screenMaxRows: screenMaxRows, maxWidth: availableWidth)

        let x: CGFloat
        if l.centered {
            let centeringWidth: CGFloat
            if let maxCols = maxColumns {
                let maxW = spreadsheetView.columnWidth * CGFloat(maxCols)
                centeringWidth = min(maxW, availableWidth)
            } else {
                centeringWidth = frame.width
            }
            x = sf.origin.x + marginPx + (availableWidth - centeringWidth) / 2
        } else {
            x = sf.origin.x + marginPx
        }
        let y = topY - frame.height
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        log.debug("show: isVisible=\(isVisible)")
        installMouseMonitor()
    }

    private var tabStripTotalHeight: CGFloat {
        state.tabs.isEmpty ? 0 : spreadsheetView.tabStripHeight + spreadsheetView.hairlineH
    }

    public func layoutForState(screenMaxRows: Int? = nil, maxWidth: CGFloat? = nil) {
        guard let ds = dataSource else { return }
        let colCount = max(ds.columnCount, 1)
        var actualRows = (0..<ds.columnCount).map { ds.rowCount(in: $0) }.max() ?? 0
        if state.mode == .move {
            let targetRows = state.moveTargetColumn < ds.columnCount ? ds.rowCount(in: state.moveTargetColumn) + 1 : 0
            actualRows = max(actualRows, targetRows)
        }
        var clampedRows = max(min(actualRows, layout.maxVisibleRows), layout.minVisibleRows)
        if let cap = screenMaxRows { clampedRows = min(clampedRows, cap) }
        let contentW = spreadsheetView.columnWidth * CGFloat(colCount)
        let tabMinW = spreadsheetView.tabStripNaturalWidth(for: state.tabs)
        let rawW = max(contentW, tabMinW)
        let w = maxWidth.map { min(rawW, $0) } ?? rawW
        let contentH = tabStripTotalHeight + spreadsheetView.headerHeight + spreadsheetView.hairlineH + spreadsheetView.rowHeight * CGFloat(clampedRows)
        let h = contentH + infoBarHeight
        let panelFrame = NSRect(x: 0, y: 0, width: w, height: h)
        setFrame(panelFrame, display: false)
        spreadsheetView.frame = NSRect(x: 0, y: 0, width: w, height: contentH)
        infoLabel.frame = NSRect(x: 8, y: contentH + 2, width: w - 16, height: Self.infoBarHeight - 4)
        renderState()
    }

    public func cycleQuickMode() {
        guard state.quickSession else { return }
        apply(.keyDown(.down))
    }

    public func confirmIfVisible() {
        guard isVisible, state.quickSession else { return }
        apply(.keyDown(.confirm))
    }

    public func dismiss() {
        if state.mode == .rename { cancelRename() }
        stopMouseMonitor()
        cursorInTabArea = false
        tabEntryGateOpen = false
        tabEntryGateTimer?.cancel()
        tabHoverTimer?.cancel()
        tabHoverIndex = nil
        infoText = nil
        orderOut(nil)
        onDismiss?()
    }

    public override var canBecomeKey: Bool { true }

    // MARK: – State management

    private var lastModifiers: NSEvent.ModifierFlags = []

    public func apply(_ action: SpreadsheetAction, modifiers: NSEvent.ModifierFlags = []) {
        lastModifiers = modifiers
        let previousMode = state.mode
        let previousActiveTab = state.activeTab
        let previousColumn = state.selectedColumn
        let previousRow = state.selectedRow
        let previousMoveTarget = state.moveTargetColumn

        switch action {
        case .dataAction where state.quickSession:
            return
        case .dataAction(let dataAction) where state.mode != .move && state.mode != .moveTabNav:
            handleDataAction(dataAction)
            return
        default:
            break
        }

        reduce(state: &state, action: action)

        if case .mouseMove = action,
           state.selectedColumn == previousColumn && state.selectedRow == previousRow && state.mode == previousMode {
            return
        }

        switch action {
        case .keyDown(.confirm):
            if previousMode == .moveTabNav && state.movingColumn {
                spreadsheetDelegate?.spreadsheetDidConfirmMoveTab(index: state.activeTab)
                state.mode = .browse
                state.movingColumn = false
            } else if previousMode == .move || previousMode == .moveTabNav {
                spreadsheetDelegate?.spreadsheetDidRequestMoveRow(
                    column: state.moveOriginColumn, row: state.moveOriginRow,
                    toColumn: state.moveTargetColumn)
                state.mode = .browse
            } else if state.mode == .browse {
                spreadsheetDelegate?.spreadsheetDidConfirm(column: state.selectedColumn, row: state.selectedRow)
            }
        case .keyDown(.cancel):
            if previousMode == .moveTabNav {
                state.movingColumn = false
                spreadsheetDelegate?.spreadsheetDidCancelMoveTabNav()
            } else if previousMode != .move {
                spreadsheetDelegate?.spreadsheetDidCancel()
            }
        default:
            break
        }

        if state.mode == .moveTabNav && previousMode == .moveTabNav && state.activeTab != previousActiveTab {
            spreadsheetDelegate?.spreadsheetDidSwitchMoveTab(index: state.activeTab)
        } else if state.mode == .move && previousMode == .moveTabNav {
            spreadsheetDelegate?.spreadsheetDidDescendFromMoveTabNav()
        } else if state.activeTab != previousActiveTab && state.mode != .moveTabNav {
            spreadsheetDelegate?.spreadsheetDidSwitchTab(index: state.activeTab)
        }

        renderState()

        if state.mode == .move && state.moveTargetColumn != previousMoveTarget {
            relayout()
        }
    }

    private func resolveTarget() -> PanelTarget? {
        let mods = lastModifiers

        // cmd → context level
        if mods.contains(.command) {
            return .tab(index: state.activeTab)
        }
        // shift → workspace level
        if mods.contains(.shift) {
            guard state.selectedColumn < state.columns.count else { return nil }
            return .columnHeader(column: state.selectedColumn)
        }
        // no modifier → based on mode/state (convenience rule)
        switch state.mode {
        case .tabNav:
            return .tab(index: state.activeTab)
        case .browse:
            guard state.selectedColumn < state.columns.count else { return nil }
            if state.columns[state.selectedColumn].rowCount > 0 {
                return .row(column: state.selectedColumn, row: state.selectedRow)
            }
            return .columnHeader(column: state.selectedColumn)
        default:
            return nil
        }
    }

    private func handleDataAction(_ action: DataAction) {
        switch action {
        case .addColumn:
            if lastModifiers.contains(.command) || state.mode == .tabNav {
                spreadsheetDelegate?.spreadsheetDidRequestAddTab()
            } else if lastModifiers.contains(.shift) {
                spreadsheetDelegate?.spreadsheetDidRequestAddColumn()
            } else {
                spreadsheetDelegate?.spreadsheetDidRequestAddRow()
            }
        case .close:
            switch resolveTarget() {
            case .row(let col, let row):
                spreadsheetDelegate?.spreadsheetDidRequestCloseRow(column: col, row: row)
            case .columnHeader(let col):
                guard col < state.columns.count, state.columns[col].rowCount == 0 else { break }
                spreadsheetDelegate?.spreadsheetDidRequestDeleteColumn(column: col)
            case .tab(let idx):
                spreadsheetDelegate?.spreadsheetDidRequestDeleteTab(index: idx)
            case .tabStrip, nil: break
            }
        case .moveRow:
            if lastModifiers.contains(.shift) || state.columns[state.selectedColumn].rowCount == 0 || state.columns.count <= 1 {
                guard state.tabs.count > 1 else { break }
                spreadsheetDelegate?.spreadsheetDidRequestMoveColumn(column: state.selectedColumn)
            } else {
                reduce(state: &state, action: .dataAction(.moveRow))
                renderState()
            }
        case .moveColumn: break
        case .rename:
            guard let target = resolveTarget() else { return }
            state.renameTarget = target
            state.mode = .rename
            renderState()
            showNameEditor(for: target)
        }
    }

    public func relayout() {
        guard let screen = showScreen else { return }
        let sf = screen.visibleFrame

        let oldX = frame.origin.x
        let oldTop = frame.origin.y + frame.height

        let marginPx = sf.width * layout.panelX
        let rightBoundary = sf.origin.x + sf.width - marginPx
        let maxW = rightBoundary - oldX

        let availableHeight = oldTop - screen.frame.origin.y
        let nonRowHeight = tabStripTotalHeight + spreadsheetView.headerHeight + spreadsheetView.hairlineH + infoBarHeight
        let screenMaxRows = max(Int((availableHeight - nonRowHeight) / spreadsheetView.rowHeight), 1)

        layoutForState(screenMaxRows: screenMaxRows, maxWidth: maxW)
        setFrameOrigin(NSPoint(x: oldX, y: oldTop - frame.height))
    }

    public func refresh() {
        guard let ds = dataSource else { return }
        let columns = (0..<ds.columnCount).map {
            Column(name: ds.columnName($0), rowCount: ds.rowCount(in: $0))
        }
        let clampedCol = min(state.selectedColumn, max(columns.count - 1, 0))
        let maxRow = columns.isEmpty ? 0 : max(columns[clampedCol].rowCount - 1, 0)
        let clampedRow = min(state.selectedRow, maxRow)
        state = SpreadsheetState(
            tabs: state.tabs, activeTab: state.activeTab,
            columns: columns,
            selectedColumn: clampedCol, selectedRow: clampedRow,
            mode: state.mode,
            moveOriginColumn: state.moveOriginColumn,
            moveOriginRow: state.moveOriginRow,
            moveTargetColumn: state.moveTargetColumn,
            movingColumn: state.movingColumn,
            phantomColumnIndex: state.phantomColumnIndex,
            quickSession: state.quickSession
        )
        renderState()
    }

    private func renderState() {
        guard let ds = dataSource else { return }
        spreadsheetView.render(state: state, dataSource: ds)
        spreadsheetView.layoutSubtreeIfNeeded()
        if isVisible {
            onStateChanged?()
        } else {
            log.debug("renderState: not visible, skipping onStateChanged")
        }
    }

    // MARK: – Rename editor

    private func showNameEditor(for target: PanelTarget) {
        let viewId: String
        let currentValue: String
        let font: NSFont
        switch target {
        case .row(let col, let row):
            viewId = "label-\(col)-\(row)"
            currentValue = dataSource?.rowLabel(column: col, row: row) ?? ""
            font = .systemFont(ofSize: (layout.rowHeight * 0.31).rounded())
        case .columnHeader(let col):
            viewId = "header-\(col)"
            currentValue = dataSource?.columnName(col) ?? ""
            font = .systemFont(ofSize: (layout.rowHeight * 0.28).rounded(), weight: .medium)
        case .tab(let index):
            viewId = "tab-label-\(index)"
            currentValue = state.tabs.indices.contains(index) ? state.tabs[index].name : ""
            font = .systemFont(ofSize: (layout.rowHeight * 0.28).rounded(), weight: .medium)
        case .tabStrip: return
        }

        guard let targetView = spreadsheetView.findView(id: viewId) else { return }
        var frame = targetView.convert(targetView.bounds, to: effect)
        switch target {
        case .row:
            frame = frame.insetBy(dx: -4, dy: -2)
            frame.origin.y -= 1
        case .columnHeader, .tab:
            frame = frame.insetBy(dx: 4, dy: -1)
        case .tabStrip: return
        }
        nameEditor.frame = frame
        nameEditor.font = font
        nameEditor.stringValue = currentValue
        nameEditor.isHidden = false
        nameEditor.delegate = self
        makeFirstResponder(nameEditor)
        installEditKeyMonitor()
    }

    private func installEditKeyMonitor() {
        editKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let editor = self.nameEditor.currentEditor() as? NSTextView,
                  event.modifierFlags.contains(.command) else { return event }
            let shift = event.modifierFlags.contains(.shift)
            switch event.charactersIgnoringModifiers {
            case "a": editor.selectAll(nil)
            case "c": editor.copy(nil)
            case "v": editor.paste(nil)
            case "x": editor.cut(nil)
            case "z": shift ? editor.undoManager?.redo() : editor.undoManager?.undo()
            default: return event
            }
            return nil
        }
    }

    private func hideNameEditor() {
        nameEditor.isHidden = true
        nameEditor.delegate = nil
        if let m = editKeyMonitor { NSEvent.removeMonitor(m); editKeyMonitor = nil }
    }

    private func exitRename() {
        hideNameEditor()
        if case .tab = state.renameTarget { state.mode = .tabNav } else { state.mode = .browse }
        state.renameTarget = nil
    }

    private func commitRename() {
        guard let target = state.renameTarget else { return }
        let value = nameEditor.stringValue.trimmingCharacters(in: .whitespaces)
        exitRename()
        spreadsheetDelegate?.spreadsheetDidRequestRename(target: target, value: value)
    }

    private func cancelRename() {
        exitRename()
        renderState()
    }

    // MARK: – Keyboard

    public override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { super.sendEvent(event); return }
        if state.mode == .rename { super.sendEvent(event); return }
        let mods = state.quickSession ? [] : event.modifierFlags
        if let action = keys.action(forKeyCode: event.keyCode, modifiers: mods) {
            apply(action, modifiers: event.modifierFlags)
            if mouseDragging && state.mode == .browse {
                mouseDragging = false
                mouseDownColumn = nil
                mouseDownRow = nil
                mouseDownActive = false
                NSCursor.arrow.set()
            }
        }
    }

    // MARK: – Mouse

    private var mouseDownColumn: Int?
    private var mouseDownRow: Int?
    private var mouseDownActive = false
    private var mouseDragging = false
    public var isDragging: Bool { mouseDragging }

    public func installMouseMonitor() {
        stopMouseMonitor()
        mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            let point = self.pointInSpreadsheetView(from: event)
            switch event.type {
            case .leftMouseDown:   return self.handleMouseDown(point: point)
            case .leftMouseDragged: return self.handleMouseDragged(point: point)
            case .leftMouseUp:     return self.handleMouseUp(point: point, event: event)
            case .mouseMoved:      return self.handleMouseHover(point: point, event: event)
            case .rightMouseDown:  self.handleRightClick(point: point); return nil
            default:               return event
            }
        }
    }

    private func pointInSpreadsheetView(from event: NSEvent) -> NSPoint {
        let screenPoint: NSPoint
        if let eventWindow = event.window {
            screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
        } else {
            screenPoint = event.locationInWindow
        }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        return spreadsheetView.convert(windowPoint, from: nil)
    }

    private func handleMouseDown(point: NSPoint) -> NSEvent? {
        let hit = hitTest(point: point)
        mouseDownColumn = hit.column
        mouseDownRow = hit.row
        mouseDownActive = true
        log.debug("mouseDown: col=\(hit.column.map(String.init) ?? "nil") row=\(hit.row.map(String.init) ?? "nil") tab=\(hit.tab.map(String.init) ?? "nil")")
        return nil
    }

    private func handleMouseDragged(point: NSPoint) -> NSEvent? {
        guard let col = mouseDownColumn else { return nil }
        if !mouseDragging && state.mode == .browse {
            if let row = mouseDownRow {
                guard col < state.columns.count,
                      state.columns[col].rowCount > 0 else { return nil }
                if state.columns.count <= 1 {
                    guard state.tabs.count > 1 else { return nil }
                    apply(.mouseMove(column: col, row: row))
                    spreadsheetDelegate?.spreadsheetDidRequestMoveColumn(column: col)
                } else {
                    apply(.mouseMove(column: col, row: row))
                    apply(.dataAction(.moveRow))
                }
            } else {
                guard state.tabs.count > 1 else { return nil }
                spreadsheetDelegate?.spreadsheetDidRequestMoveColumn(column: col)
            }
            mouseDragging = true
            NSCursor.closedHand.set()
        }
        if mouseDragging {
            let hit = hitTest(point: point)
            if let tab = hit.tab, tab != state.activeTab, (state.mode == .move || state.mode == .moveTabNav) {
                state.activeTab = tab
                spreadsheetDelegate?.spreadsheetDidSwitchMoveTab(index: tab)
                if state.mode == .move {
                    spreadsheetDelegate?.spreadsheetDidDescendFromMoveTabNav()
                }
            } else if let targetCol = hit.column, state.mode == .move, targetCol != state.moveTargetColumn {
                state.moveTargetColumn = targetCol
                relayout()
            }
        }
        return nil
    }

    private func handleMouseUp(point: NSPoint, event: NSEvent) -> NSEvent {
        if mouseDragging {
            let hit = hitTest(point: point)
            if let targetCol = hit.column {
                state.moveTargetColumn = targetCol
            }
            apply(.keyDown(.confirm))
            mouseDragging = false
            mouseDownColumn = nil
            mouseDownRow = nil
            mouseDownActive = false
            NSCursor.arrow.set()
            return event
        }
        guard mouseDownActive else {
            log.debug("mouseUp: ignored (mouseDownActive=false)")
            return event
        }
        let hit = hitTest(point: point)
        log.debug("mouseUp: col=\(hit.column.map(String.init) ?? "nil") row=\(hit.row.map(String.init) ?? "nil") tab=\(hit.tab.map(String.init) ?? "nil")")
        if let tab = hit.tab {
            apply(.mouseClickTab(index: tab))
        } else if let col = hit.column {
            apply(.mouseMove(column: col, row: hit.row ?? 0))
            if hit.row != nil {
                log.debug("mouseUp: confirming col=\(col) row=\(hit.row!)")
                apply(.keyDown(.confirm))
            }
        }
        mouseDownColumn = nil
        mouseDownRow = nil
        mouseDownActive = false
        return event
    }

    private var tabHoverTimer: DispatchWorkItem?
    private var tabHoverIndex: Int?
    private var cursorInTabArea = false
    private var tabEntryGateOpen = false
    private var tabEntryGateTimer: DispatchWorkItem?

    private func handleMouseHover(point: NSPoint, event: NSEvent) -> NSEvent {
        if !mouseDragging {
            let hit = hitTest(point: point)
            if let col = hit.column {
                let row = hit.row ?? 0
                if col != state.selectedColumn || row != state.selectedRow || state.mode != .browse {
                    apply(.mouseMove(column: col, row: row))
                }
            }
            if tabSwitchOnHover && (state.mode == .browse || state.mode == .tabNav) {
                let nowInTabArea = hit.tab != nil || hit.tabStrip
                if nowInTabArea && !cursorInTabArea {
                    cursorInTabArea = true
                    tabEntryGateOpen = false
                    tabEntryGateTimer?.cancel()
                    tabHoverTimer?.cancel()
                    tabHoverIndex = nil
                    let item = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.tabEntryGateOpen = true
                        if let pending = self.tabHoverIndex, pending != self.state.activeTab {
                            self.apply(.mouseClickTab(index: pending))
                            self.tabHoverIndex = nil
                        }
                    }
                    tabEntryGateTimer = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + tabHoverDelay, execute: item)
                }
                if !nowInTabArea && cursorInTabArea {
                    cursorInTabArea = false
                    tabEntryGateOpen = false
                    tabEntryGateTimer?.cancel()
                    tabHoverTimer?.cancel()
                    tabHoverIndex = nil
                }

                if let tab = hit.tab {
                    if state.mode == .browse {
                        state.mode = .tabNav
                        renderState()
                    }
                    if tabEntryGateOpen {
                        if tab != state.activeTab && tab != tabHoverIndex {
                            tabHoverTimer?.cancel()
                            tabHoverIndex = tab
                            let item = DispatchWorkItem { [weak self] in
                                guard let self, self.tabHoverIndex == tab else { return }
                                self.apply(.mouseClickTab(index: tab))
                            }
                            tabHoverTimer = item
                            DispatchQueue.main.asyncAfter(deadline: .now() + tabHoverDelay, execute: item)
                        } else if tab == state.activeTab {
                            tabHoverTimer?.cancel()
                            tabHoverIndex = nil
                        }
                    } else {
                        tabHoverIndex = tab
                    }
                } else {
                    tabHoverTimer?.cancel()
                    tabHoverIndex = nil
                }
            }
        }
        return event
    }

    public func simulateMouseDown(at point: NSPoint) {
        _ = handleMouseDown(point: point)
    }

    public func simulateMouseDragged(to point: NSPoint) {
        _ = handleMouseDragged(point: point)
    }

    public func simulateMouseUp(at point: NSPoint) {
        _ = handleMouseUp(point: point, event: NSEvent())
    }

    public func simulateMouseHover(at point: NSPoint) {
        _ = handleMouseHover(point: point, event: NSEvent())
    }

    public func handleRightClick(point: NSPoint) {
        guard !state.quickSession, state.mode != .rename else { return }
        let hit = hitTest(point: point)
        let target: PanelTarget
        if let tab = hit.tab { target = .tab(index: tab) }
        else if hit.tabStrip { target = .tabStrip }
        else if let col = hit.column, let row = hit.row { target = .row(column: col, row: row) }
        else if let col = hit.column { target = .columnHeader(column: col) }
        else { return }

        switch target {
        case .row(let col, let row): apply(.mouseMove(column: col, row: row))
        case .columnHeader(let col): apply(.mouseMove(column: col, row: 0))
        case .tab(let index): apply(.mouseClickTab(index: index))
        case .tabStrip: break
        }
        spreadsheetDelegate?.spreadsheetDidRightClick(target: target)
    }

    public func startRename(for target: PanelTarget) {
        state.renameTarget = target
        state.mode = .rename
        renderState()
        showNameEditor(for: target)
    }

    public func stopMouseMonitor() {
        if let m = mouseMoveMonitor { NSEvent.removeMonitor(m); mouseMoveMonitor = nil }
    }

    private struct HitResult {
        var column: Int?
        var row: Int?
        var tab: Int?
        var tabStrip = false
    }

    private func hitTest(point: NSPoint) -> HitResult {
        guard spreadsheetView.bounds.contains(point) else { return HitResult() }
        let h = spreadsheetView.bounds.height
        let tabStripOffset: CGFloat = state.tabs.isEmpty ? 0 : spreadsheetView.tabStripHeight + spreadsheetView.hairlineH

        // Tab strip area
        if !state.tabs.isEmpty && point.y > h - spreadsheetView.tabStripHeight {
            for i in 0..<state.tabs.count {
                if let tabView = spreadsheetView.findView(id: "tab-\(i)") {
                    let tabFrame = tabView.convert(tabView.bounds, to: spreadsheetView)
                    if tabFrame.contains(point) {
                        return HitResult(tab: i)
                    }
                }
            }
            return HitResult(tabStrip: true)
        }

        let colIndex = Int(point.x / spreadsheetView.columnWidth)
        guard colIndex >= 0, colIndex < state.columns.count else { return HitResult() }
        let contentTop = h - tabStripOffset - spreadsheetView.headerHeight - spreadsheetView.hairlineH
        guard point.y < contentTop else { return HitResult(column: colIndex) }
        let scrollOffset = spreadsheetView.columnScrollOffset(for: colIndex)
        let rowIndex = Int((contentTop - point.y + scrollOffset) / spreadsheetView.rowHeight)
        guard rowIndex >= 0, rowIndex < state.columns[colIndex].rowCount else { return HitResult(column: colIndex) }
        return HitResult(column: colIndex, row: rowIndex)
    }
}

extension SpreadsheetPanel: NSTextFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { commitRename(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancelRename(); return true }
        return false
    }
}
