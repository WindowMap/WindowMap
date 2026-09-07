import AppKit
import Logging
import SpreadsheetKit
import WindowMapCore

public struct Unchecked<T>: @unchecked Sendable { public let value: T; public init(value: T) { self.value = value } }

private let log = Log(module: "PanelController")

public class PanelController: SpreadsheetDelegate {
    public let panel: SpreadsheetPanel
    public let dataSource: WindowMapDataSource
    public let store: Store
    public let listWindows: () -> [Window]
    public var config: Config
    public var onConfirm: ((Window) -> Void)?
    public var onCloseWindow: ((Window) -> Void)?
    /// Returns true if the window still exists (e.g. app showed a save dialog).
    public var onVerifyWindowClosed: ((Window) -> Bool)?
    public var onBeforeShow: (() -> Void)?
    public var onCapturePreview: ((_ windowId: CGWindowID) async -> Void)?
    public var onSelectionChanged: ((Window?) -> Void)?
    public var onShowPreview: ((_ focusedId: CGWindowID?, _ priorityOrder: [CGWindowID]) -> Void)?
    public var onStartLauncher: (() -> Void)?
    public var onQuickShown: (() -> Void)?
    public var onShown: (() -> Void)?

    public init(store: Store, config: Config, listWindows: @escaping () -> [Window]) {
        self.store = store
        self.config = config
        self.listWindows = listWindows
        self.dataSource = WindowMapDataSource()
        self.panel = SpreadsheetPanel(state: SpreadsheetState(
            columns: [], selectedColumn: 0, selectedRow: 0, mode: .browse
        ))
        self.dataSource.titleLookup = { [weak store] wid in store?.title(for: wid) }
        self.panel.dataSource = dataSource
        self.panel.spreadsheetDelegate = self
        self.panel.onStateChanged = { [weak self] in self?.handleStateChanged() }
        NotificationCenter.default.addObserver(self, selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification, object: panel)
    }

    private var isTabFocused: Bool {
        switch panel.state.mode {
        case .tabNav, .moveTabNav: return true
        case .rename: if case .tab = panel.state.renameTarget { return true }; return false
        default: return false
        }
    }

    private func handleStateChanged() {
        let col = panel.state.selectedColumn
        let row = panel.state.selectedRow
        let mode = panel.state.mode
        log.debug("stateChanged: col=\(col) row=\(row) mode=\(mode) movingId=\(movingWindowId.map(String.init) ?? "nil") tabFocused=\(isTabFocused)")
        if col < dataSource.columns.count {
            store.setActiveWorkspace(id: dataSource.columns[col].0.id)
        }
        if mode == .move && movingWindowId == nil {
            movingWindowId = dataSource.window(column: panel.state.moveOriginColumn, row: panel.state.moveOriginRow)?.id
            moveOriginContextId = store.activeContextId()
        }
        if mode == .moveTabNav, let ctxId = store.activeContextId() {
            moveTargetColumnPerContext[ctxId] = panel.state.moveTargetColumn
        }
        if movingWindowId != nil {
            log.debug("stateChanged: preview locked to moving window")
        } else if isTabFocused {
            log.debug("stateChanged: tab focused → hide preview")
            onSelectionChanged?(nil)
        } else if mode == .browse {
            let win = dataSource.window(column: col, row: row)
            log.debug("stateChanged: browse → selection window=\(win.map { String($0.id) } ?? "nil")")
            onSelectionChanged?(win)
        } else {
            log.debug("stateChanged: no preview branch matched (mode=\(mode))")
        }
    }

    public private(set) var launcherActive = false

    public func suspendForLauncher() {
        launcherActive = true
        panel.stopMouseMonitor()
    }

    public func resumeFromLauncher() {
        launcherActive = false
        panel.makeKeyAndOrderFront(nil)
        panel.installMouseMonitor()
    }

    public func dismissFromLauncher() {
        launcherActive = false
        panel.dismiss()
    }

    @objc private func panelDidResignKey() {
        guard panel.isVisible else { return }
        guard !launcherActive else { return }
        guard CFAbsoluteTimeGetCurrent() >= suppressResignUntil else { return }
        guard !panel.isDragging else { return }
        if config.clickOutside == "confirm" {
            let col = panel.state.selectedColumn
            let row = panel.state.selectedRow
            if let win = dataSource.window(column: col, row: row) {
                log.info("focus loss → confirm: \(win.appName ?? "?") — \(win.title)")
                onConfirm?(win)
            } else {
                log.info("focus loss → cancel (no window selected)")
            }
        } else {
            log.info("focus loss → cancel")
        }
        panel.dismiss()
    }

    public func toggle(on screen: NSScreen) {
        if panel.isVisible {
            panel.dismiss()
        } else {
            show(on: screen)
        }
    }

    public func showQuick(on screen: NSScreen) {
        if panel.isVisible && panel.state.quickSession {
            panel.cycleQuickMode()
            return
        }
        onBeforeShow?()
        cachedWindows = listWindows()
        let focusedId = focusedWindow?.id
        let s = Unchecked(value: screen)
        Task { @MainActor in
            if let fid = focusedId {
                await onCapturePreview?(fid)
            }
            showPanel(on: s.value, quickSession: true)
            if config.mruOrder { panel.cycleQuickMode() }
            onQuickShown?()
        }
    }

    public func toggleAsync(on screen: NSScreen) {
        if panel.isVisible {
            panel.dismiss()
            return
        }
        onBeforeShow?()
        cachedWindows = listWindows()
        let focusedId = focusedWindow?.id
        let s = Unchecked(value: screen)
        Task { @MainActor in
            if let fid = focusedId {
                await onCapturePreview?(fid)
            }
            self.showPanel(on: s.value)
            self.onShown?()
        }
    }

    private var cachedWindows: [Window] = []
    private var focusedWindow: Window? { cachedWindows.first }
    private var mruContextIds: [UUID] = []
    private var selectedColumnPerContext: [UUID: Int] = [:]

    public func show(on screen: NSScreen) {
        onBeforeShow?()
        cachedWindows = listWindows()
        showPanel(on: screen)
    }

    private func showPanel(on screen: NSScreen, quickSession: Bool = false) {
        log.info("show\(quickSession ? " (quick)" : "") with \(cachedWindows.count) windows")

        // Set active context to the one containing the frontmost window
        if let frontWindow = focusedWindow,
           let ctxId = store.contextId(containingWindowId: frontWindow.id) {
            store.setActiveContext(id: ctxId)
        }

        reloadForActiveContext()
        let ctxs = store.contexts()
        if config.mruOrder {
            let mruOrder = mruContextOrder(contexts: ctxs, windows: cachedWindows)
            mruContextIds = mruOrder.map(\.id)
        } else {
            mruContextIds = ctxs.map(\.id)
        }
        selectedColumnPerContext = [:]

        let columns = (0..<dataSource.columnCount).map {
            Column(name: dataSource.columnName($0), rowCount: dataSource.rowCount(in: $0))
        }
        let pos = focusedWindow.flatMap { dataSource.position(of: $0.id) }
        let selCol = pos?.column ?? 0
        let selRow = pos?.row ?? 0
        panel.state = SpreadsheetState(
            columns: columns,
            selectedColumn: selCol, selectedRow: selRow,
            quickSession: quickSession
        )
        syncTabState()
        panel.alphaValue = CGFloat(config.panelOpacity)

        var layout = LayoutConfig.forScreen(screen)
        layout.minVisibleRows = config.minHeightRows
        layout.maxVisibleRows = config.maxHeightRows
        layout.centered = config.centered
        layout.panelX = CGFloat(config.panelX)
        layout.panelY = CGFloat(config.panelY)
        layout.columnWidth = (layout.rowHeight * CGFloat(config.columnWidth)).rounded()

        let maxColumns = store.contexts().map(\.workspaces.count).max() ?? 1
        panel.show(on: screen, layout: layout, maxColumns: maxColumns)

        let focusedId = focusedWindow?.id
        onShowPreview?(focusedId, previewPriorityOrder(focusedId: focusedId))

        // Show preview for initial selection (after picker is visible)
        if let win = dataSource.window(column: panel.state.selectedColumn, row: panel.state.selectedRow) {
            onSelectionChanged?(win)
        }
    }

    private func previewPriorityOrder(focusedId: CGWindowID?) -> [CGWindowID] {
        var result: [CGWindowID] = []
        var seen = Set<CGWindowID>()
        if let fid = focusedId { seen.insert(fid) }

        // Active context: all workspaces in column order (MRU)
        for (_, windows) in dataSource.columns {
            for w in windows where seen.insert(w.id).inserted { result.append(w.id) }
        }

        // Other contexts
        let activeCtxId = store.activeContextId()
        for ctx in store.contexts() where ctx.id != activeCtxId {
            for ws in ctx.workspaces {
                for wid in ws.windowIds where seen.insert(wid).inserted { result.append(wid) }
            }
        }

        return result
    }

    /// Order tabs by MRU: iterate cached windows front-to-back, the first context
    /// that owns each window is ordered first. Contexts with no live windows go last.
    private func mruContextOrder(contexts: [Context], windows: [Window]) -> [(id: UUID, tab: Tab)] {
        var windowToContext: [UInt32: UUID] = [:]
        for ctx in contexts {
            for ws in ctx.workspaces {
                for wid in ws.windowIds { windowToContext[wid] = ctx.id }
            }
        }
        var ordered: [(id: UUID, tab: Tab)] = []
        var seen = Set<UUID>()
        for w in windows {
            if let ctxId = windowToContext[w.id], seen.insert(ctxId).inserted,
               let ctx = contexts.first(where: { $0.id == ctxId }) {
                ordered.append((ctx.id, Tab(name: ctx.name)))
            }
        }
        for ctx in contexts where !seen.contains(ctx.id) {
            ordered.append((ctx.id, Tab(name: ctx.name)))
        }
        return ordered
    }

    private func setColumns(_ cols: [(Workspace, [Window])]) {
        dataSource.columns = cols
        panel.relayout()
    }

    private func reloadForActiveContext() {
        setColumns(store.updateAndGroup(for: cachedWindows, mruOrder: config.mruOrder))
    }

    public func spreadsheetDidConfirm(column: Int, row: Int) {
        if let win = dataSource.window(column: column, row: row) {
            log.info("confirm: \(win.appName ?? "?") — \(win.title)")
            onConfirm?(win)
        }
        panel.dismiss()
    }

    public func spreadsheetDidCancel() {
        log.info("cancel")
        panel.dismiss()
    }

    /// Timestamp until which panel resign events should be suppressed.
    /// Set after closing a window to prevent macOS focus shift from dismissing the panel.
    public private(set) var suppressResignUntil: CFAbsoluteTime = 0

    public func spreadsheetDidRequestCloseRow(column: Int, row: Int) {
        guard column < dataSource.columns.count,
              row < dataSource.columns[column].1.count else { return }

        // 1. Remove from data source and store
        let win = dataSource.columns[column].1.remove(at: row)
        store.removeWindow(win.id)
        cachedWindows.removeAll { $0.id == win.id }
        let newRowCount = dataSource.columns[column].1.count
        panel.state.selectedRow = newRowCount > 0 ? min(row, newRowCount - 1) : 0
        panel.refresh()

        // 2. Close the real window via callback
        onCloseWindow?(win)

        // 3. Suppress panel resign for 0.3s
        suppressResignUntil = CFAbsoluteTimeGetCurrent() + 0.3

        // 4. Post-close verification after 0.25s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            if let verify = self.onVerifyWindowClosed, verify(win) {
                self.panel.dismiss()
            } else {
                // Window is gone — bring the panel back to front.
                self.panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    public func spreadsheetDidRequestAddRow() {
        onStartLauncher?()
    }

    private var movingWorkspaceData: (Workspace, [Window])?

    public func spreadsheetDidRequestMoveColumn(column: Int) {
        guard column < dataSource.columns.count else { return }
        movingWorkspaceData = dataSource.columns[column]
        moveOriginContextId = store.activeContextId()

        dataSource.columns.remove(at: column)
        insertPhantomColumn()
        panel.state.movingColumn = true
        panel.state.mode = .moveTabNav
        panel.refresh()
        panel.relayout()
    }

    private func insertPhantomColumn() {
        guard let data = movingWorkspaceData else { return }
        dataSource.columns.removeAll { $0.0.id == data.0.id }
        dataSource.columns.insert(data, at: 0)
        panel.state.phantomColumnIndex = 0
    }

    public func spreadsheetDidConfirmMoveTab(index: Int) {
        guard let wsData = movingWorkspaceData,
              index < mruContextIds.count else { return }
        let targetCtxId = mruContextIds[index]
        store.moveWorkspace(id: wsData.0.id, toContext: targetCtxId)
        store.setActiveContext(id: targetCtxId)
        clearMoveState()
        var cols = store.groupCurrentWorkspaces(windows: cachedWindows, mruOrder: config.mruOrder)
        cols.removeAll { $0.0.id == wsData.0.id }
        cols.insert(wsData, at: 0)
        setColumns(cols)
        syncTabState()
        panel.state.selectedColumn = 0
        panel.state.selectedRow = 0
        panel.refresh()
    }

    public func spreadsheetDidRequestAddColumn() {
        let wss = store.workspaces()
        var wsIdx = wss.count
        while wss.contains(where: { $0.name == "Workspace\(wsIdx)" }) { wsIdx += 1 }
        let id = store.addWorkspace(name: "Workspace\(wsIdx)")
        let ws = store.workspaces().first(where: { $0.id == id })!
        dataSource.columns.insert((ws, []), at: 0)
        panel.state.selectedColumn = 0
        panel.state.selectedRow = 0
        panel.refresh()
        panel.relayout()
    }

    public func spreadsheetDidRequestDeleteColumn(column: Int) {
        guard column < dataSource.columns.count else { return }
        guard dataSource.columns.count > 1 else { return }
        let ws = dataSource.columns[column].0
        dataSource.columns.remove(at: column)
        store.removeWorkspace(id: ws.id)
        panel.refresh()
        panel.relayout()
    }

    private var moveOriginContextId: UUID?
    private var moveTargetColumnPerContext: [UUID: Int] = [:]

    public func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {
        guard column < dataSource.columns.count,
              row < dataSource.columns[column].1.count,
              toColumn < dataSource.columns.count else { return }
        let win = dataSource.columns[column].1.remove(at: row)
        dataSource.columns[toColumn].1.insert(win, at: 0)

        store.moveWindow(win.id, toWorkspace: dataSource.columns[toColumn].0.id)

        clearMoveState()
        panel.state.mode = .browse
        panel.state.selectedColumn = toColumn
        panel.state.selectedRow = 0
        panel.refresh()
        panel.relayout()
    }

    public func spreadsheetDidSwitchMoveTab(index: Int) {
        guard index < mruContextIds.count else { return }
        let ctxId = mruContextIds[index]
        store.setActiveContext(id: ctxId)
        setColumns(store.groupCurrentWorkspaces(windows: cachedWindows, mruOrder: config.mruOrder))
        if movingWorkspaceData != nil { insertPhantomColumn() }
        panel.refresh()
        panel.relayout()
    }

    public func spreadsheetDidDescendFromMoveTabNav() {
        guard panel.state.activeTab < mruContextIds.count else { return }
        let ctxId = mruContextIds[panel.state.activeTab]
        // Remove the moving window from any column in this context
        if let wid = movingWindowId {
            for i in dataSource.columns.indices {
                dataSource.columns[i].1.removeAll { $0.id == wid }
            }
        }

        let targetCol: Int
        if let saved = moveTargetColumnPerContext[ctxId] {
            targetCol = min(saved, max(dataSource.columns.count - 1, 0))
        } else {
            targetCol = selectedColumnPerContext[ctxId] ?? 0
        }

        if let wid = movingWindowId,
           let win = cachedWindows.first(where: { $0.id == wid }),
           targetCol < dataSource.columns.count {
            dataSource.columns[targetCol].1.insert(win, at: 0)
        }

        panel.state.moveOriginColumn = targetCol
        panel.state.moveOriginRow = 0
        panel.state.moveTargetColumn = targetCol
        panel.state.selectedColumn = targetCol
        panel.refresh()
        panel.relayout()
    }

    public func spreadsheetDidCancelMoveTabNav() {
        // Restore to origin context
        if let originCtxId = moveOriginContextId {
            store.setActiveContext(id: originCtxId)
            setColumns(store.groupCurrentWorkspaces(windows: cachedWindows, mruOrder: config.mruOrder))
        }
        clearMoveState()
        panel.refresh()
    }

    private var movingWindowId: CGWindowID?

    private func clearMoveState() {
        moveOriginContextId = nil
        moveTargetColumnPerContext = [:]
        movingWindowId = nil
        movingWorkspaceData = nil
        panel.state.phantomColumnIndex = nil
    }

    public func spreadsheetDidRequestAddTab() {
        let ctxs = store.contexts()
        var idx = ctxs.count
        while ctxs.contains(where: { $0.name == "Context\(idx)" }) { idx += 1 }
        store.addContext(name: "Context\(idx)")
        panel.state.mode = .tabNav
        syncTabsFromStore()
    }

    public func spreadsheetDidRequestDeleteTab(index: Int) {
        guard index < mruContextIds.count else { return }
        let ctxId = mruContextIds[index]
        guard store.isContextDeletable(id: ctxId) else { return }
        store.deleteContext(id: ctxId)
        mruContextIds.removeAll { $0 == ctxId }
        let nextIndex = min(index, max(mruContextIds.count - 1, 0))
        if nextIndex < mruContextIds.count {
            store.setActiveContext(id: mruContextIds[nextIndex])
        }
        refreshAll()
    }

    private func syncTabsFromStore() {
        let ctxs = store.contexts()
        let ctxIds = Set(ctxs.map(\.id))
        mruContextIds = mruContextIds.filter { ctxIds.contains($0) }
        for ctx in ctxs where !mruContextIds.contains(ctx.id) {
            mruContextIds.insert(ctx.id, at: 0)
        }
        refreshAll()
    }

    public func spreadsheetDidSwitchTab(index: Int) {
        guard index < mruContextIds.count else { return }

        if let oldId = store.activeContextId() {
            selectedColumnPerContext[oldId] = panel.state.selectedColumn
        }

        store.setActiveContext(id: mruContextIds[index])
        setColumns(store.groupCurrentWorkspaces(windows: cachedWindows, mruOrder: config.mruOrder))

        panel.state.selectedColumn = selectedColumnPerContext[mruContextIds[index]] ?? 0
        panel.state.selectedRow = 0
        panel.refresh()
        panel.relayout()
    }

    public func spreadsheetDidRequestRename(target: PanelTarget, value: String) {
        switch target {
        case .row(let column, let row):
            guard let win = dataSource.window(column: column, row: row) else { return }
            store.setTitle(value.isEmpty ? nil : value, for: win.id)
        case .columnHeader(let column):
            guard column < dataSource.columns.count else { return }
            guard !value.isEmpty else { return }
            store.renameWorkspace(id: dataSource.columns[column].0.id, name: value)
            dataSource.columns[column].0.name = value
        case .tab(let index):
            guard index < mruContextIds.count else { return }
            guard !value.isEmpty else { return }
            store.renameContext(id: mruContextIds[index], name: value)
        case .tabStrip: return
        }
        syncTabState()
        panel.refresh()
    }

    private var rightClickTarget: PanelTarget?

    public func spreadsheetDidRightClick(target: PanelTarget) {
        rightClickTarget = target
        let menu = buildContextMenu(for: target)
        guard !menu.items.isEmpty else { return }
        let location = panel.mouseLocationOutsideOfEventStream
        let viewPoint = panel.spreadsheetView.convert(location, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: panel.spreadsheetView)
    }

    public func buildContextMenu(for target: PanelTarget) -> NSMenu {
        let menu = NSMenu()
        switch target {
        case .row:
            menu.addItem(menuItem("Close Window", action: #selector(contextMenuClose)))
            menu.addItem(menuItem("Rename Window", action: #selector(contextMenuRename)))
            menu.addItem(menuItem("New Window", action: #selector(contextMenuNewRow)))
        case .columnHeader(let col):
            let isEmpty = col < dataSource.columns.count && dataSource.columns[col].1.isEmpty
            if isEmpty {
                menu.addItem(menuItem("Close Workspace", action: #selector(contextMenuClose)))
            }
            menu.addItem(menuItem("Rename Workspace", action: #selector(contextMenuRename)))
            menu.addItem(menuItem("New Workspace", action: #selector(contextMenuNewColumn)))
            menu.addItem(menuItem("New Window", action: #selector(contextMenuNewRow)))
        case .tab(let index):
            if index < mruContextIds.count && store.isContextDeletable(id: mruContextIds[index]) {
                menu.addItem(menuItem("Close Context", action: #selector(contextMenuClose)))
            }
            menu.addItem(menuItem("Rename Context", action: #selector(contextMenuRename)))
            menu.addItem(menuItem("New Context", action: #selector(contextMenuNewTab)))
        case .tabStrip:
            menu.addItem(menuItem("New Context", action: #selector(contextMenuNewTab)))
        }
        return menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func contextMenuClose() {
        guard let target = rightClickTarget else { return }
        switch target {
        case .row(let col, let row): spreadsheetDidRequestCloseRow(column: col, row: row)
        case .columnHeader(let col): spreadsheetDidRequestDeleteColumn(column: col)
        case .tab(let index): spreadsheetDidRequestDeleteTab(index: index)
        case .tabStrip: break
        }
    }

    @objc private func contextMenuRename() {
        guard let target = rightClickTarget else { return }
        panel.startRename(for: target)
    }

    @objc private func contextMenuNewRow() {
        spreadsheetDidRequestAddRow()
    }

    @objc private func contextMenuNewColumn() {
        spreadsheetDidRequestAddColumn()
    }

    @objc private func contextMenuNewTab() {
        spreadsheetDidRequestAddTab()
    }

    private func refreshAll() {
        reloadForActiveContext()
        syncTabState()
        panel.refresh()
        panel.relayout()
    }

    private func syncTabState() {
        let ctxs = store.contexts()
        panel.state.tabs = mruContextIds.compactMap { id in
            ctxs.first(where: { $0.id == id }).map { Tab(name: $0.name) }
        }
        if let activeId = store.activeContextId() {
            panel.state.activeTab = mruContextIds.firstIndex(of: activeId) ?? 0
        }
    }
}
