import AppKit
import Carbon
import Logging
import WindowMapCore

private let log = Log(module: "LauncherPanel")

private class LauncherWindow: NSPanel {
    override var canBecomeKey:  Bool { true  }
    override var canBecomeMain: Bool { false }
}

class LauncherPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate {

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    private let panel: LauncherWindow
    private let effect: NSVisualEffectView
    private let searchField: NSTextField
    private let separatorView: NSBox
    private let tableView: NSTableView
    private let scrollView: NSScrollView
    private let mru: AppMRU

    private var allApps: [AppInfo] = []
    private var filteredApps: [AppInfo] = []
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    private let fieldH:  CGFloat = 44
    private let rowH:    CGFloat = 36
    private let maxRows: Int     = 8
    private let panelW:  CGFloat = 500

    init(mru: AppMRU) {
        self.mru = mru

        panel = LauncherWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
                               styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .transient]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        container.wantsLayer = true
        container.layer!.cornerRadius = 12
        container.layer!.cornerCurve = .continuous
        container.layer!.masksToBounds = true
        panel.contentView = container

        effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        searchField = NSTextField(frame: .zero)
        searchField.placeholderString = "New window…"
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: (rowH * 0.44).rounded())

        separatorView = NSBox(frame: .zero)
        separatorView.boxType = .separator

        tableView = NSTableView(frame: .zero)
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = rowH
        let col = NSTableColumn(identifier: .init("app"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true

        effect.addSubview(searchField)
        effect.addSubview(separatorView)
        effect.addSubview(scrollView)

        super.init()

        panel.delegate = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(tableRowClicked)
        searchField.delegate = self
    }

    // MARK: – Show / Hide

    func show(paths: [String], opacity: Double) {
        log.info("show")
        panel.alphaValue = opacity
        allApps = listApps(paths: paths)
        searchField.stringValue = ""
        refilter()
        applyLayout()
        reloadTable()
        installMonitors()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        removeMonitors()
        panel.orderOut(nil)
    }

    // MARK: – NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible else { return }
        hide()
        onConfirm?()
    }

    // MARK: – Layout

    private func applyLayout() {
        let visibleRows = min(filteredApps.count, maxRows)
        let listH  = rowH * CGFloat(max(visibleRows, 4))
        let totalH = fieldH + 1 + listH

        if panel.frame.height != totalH {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
            let sf = screen.visibleFrame
            let x = sf.minX + (sf.width - panelW) / 2
            let y = sf.minY + sf.height - totalH - sf.height * 0.22
            panel.setFrame(NSRect(x: x, y: y, width: panelW, height: totalH), display: false)
            let cv = panel.contentView!
            cv.frame = NSRect(origin: .zero, size: NSSize(width: panelW, height: totalH))
            searchField.frame   = NSRect(x: 14, y: totalH - fieldH + 4, width: panelW - 28, height: fieldH - 8)
            separatorView.frame = NSRect(x: 0, y: totalH - fieldH, width: panelW, height: 1)
            scrollView.frame = NSRect(x: 0, y: 0, width: panelW, height: listH)
            tableView.frame  = NSRect(x: 0, y: 0, width: panelW, height: listH)
        }
    }

    private func reloadTable() {
        tableView.reloadData()
        if filteredApps.isEmpty {
            tableView.deselectAll(nil)
        } else {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    // MARK: – Filtering

    private func refilter() {
        let query  = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let mruIDs = mru.mruBundleIDs()

        if query.isEmpty {
            var mruApps: [AppInfo] = []
            for id in mruIDs {
                if let app = allApps.first(where: { $0.bundleID == id }) {
                    mruApps.append(app)
                    if mruApps.count == maxRows { break }
                }
            }
            filteredApps = mruApps
        } else {
            let rank = Dictionary(uniqueKeysWithValues: mruIDs.enumerated().map { ($1, $0) })
            let matches = allApps.filter { $0.nameLowercased.contains(query) }
            filteredApps = matches.sorted { a, b in
                let ai = rank[a.bundleID] ?? Int.max
                let bi = rank[b.bundleID] ?? Int.max
                if ai != bi { return ai < bi }
                return a.nameLowercased < b.nameLowercased
            }
        }
    }

    // MARK: – NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        refilter()
        applyLayout()
        reloadTable()
    }

    // MARK: – NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { filteredApps.count }

    // MARK: – NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("appCell")
        let cell: AppCell
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? AppCell {
            cell = reused
        } else {
            cell = AppCell(frame: .zero)
            cell.identifier = id
        }
        cell.configure(with: filteredApps[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { LauncherRowView() }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rowH }

    // MARK: – Key handling

    private func installMonitors() {
        guard keyMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            let point = self.tableView.convert(event.locationInWindow, from: nil)
            let row = self.tableView.row(at: point)
            if row >= 0, row < self.filteredApps.count {
                self.tableView.selectRowIndexes([row], byExtendingSelection: false)
            }
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let fe = self.searchField.currentEditor() as? NSTextView,
               fe.handleEditingShortcut(event) { return nil }
            let k = event.keyCode
            if k == UInt16(kVK_Return) || k == UInt16(kVK_Space) { self.confirm(); return nil }
            if k == UInt16(kVK_Escape)                           { self.hide(); self.onCancel?(); return nil }
            if k == UInt16(kVK_UpArrow)                          { self.moveSelection(by: -1); return nil }
            if k == UInt16(kVK_DownArrow)                        { self.moveSelection(by:  1); return nil }
            return event
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    private func moveSelection(by delta: Int) {
        let count = filteredApps.count
        guard count > 0 else { return }
        let cur  = tableView.selectedRow
        let next: Int
        if delta > 0 { next = cur < count - 1 ? cur + 1 : 0 }
        else         { next = cur > 0 ? cur - 1 : count - 1 }
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func tableRowClicked() { confirm() }

    private func confirm() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredApps.count else { return }
        let app = filteredApps[row]
        log.info("launch: \(app.name)")
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == app.bundleID }) {
            running.activate()
            if let menuItem = findNewWindowMenuItem(pid: running.processIdentifier) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
                }
            }
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [app.path]
            try? task.run()
        }
        mru.record(app.bundleID)
        hide()
        onConfirm?()
    }
}

private func findNewWindowMenuItem(pid: pid_t) -> AXUIElement? {
    func children(of el: AXUIElement) -> [AXUIElement] {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success else { return [] }
        return ref as? [AXUIElement] ?? []
    }
    func title(of el: AXUIElement) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
    var menuBarRef: AnyObject?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXMenuBarAttribute as CFString, &menuBarRef) == .success else { return nil }
    for menu in children(of: menuBarRef as! AXUIElement) {
        guard let submenu = children(of: menu).first else { continue }
        for item in children(of: submenu) {
            if title(of: item)?.caseInsensitiveCompare("New Window") == .orderedSame {
                return item
            }
        }
    }
    return nil
}

private class AppCell: NSTableCellView {
    private let iconView: NSImageView
    private let nameLabel: NSTextField

    override init(frame: NSRect) {
        iconView = NSImageView(frame: .zero)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = .systemFont(ofSize: 14)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: frame)

        addSubview(iconView)
        addSubview(nameLabel)
        textField = nameLabel

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private var currentPath: String?

    func configure(with app: AppInfo) {
        guard app.path != currentPath else { return }
        currentPath = app.path
        nameLabel.stringValue = app.name
        iconView.image = NSWorkspace.shared.icon(forFile: app.path)
    }
}

private class LauncherRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        bounds.fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }
}

private extension NSTextView {
    func handleEditingShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers {
        case "a": selectAll(nil); return true
        case "c": copy(nil); return true
        case "v": paste(nil); return true
        case "x": cut(nil); return true
        case "z": undoManager?.undo(); return true
        default: return false
        }
    }
}
