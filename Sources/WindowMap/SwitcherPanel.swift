import AppKit
import Logging
import SpreadsheetKit
import WindowMapCore

private let log = Log(module: "SwitcherPanel")

private class SwitcherWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

class SwitcherPanel: NSObject, NSWindowDelegate {

    var onConfirm: ((Window) -> Void)?
    var onDismiss: (() -> Void)?
    var onSelectionChanged: ((Window) -> Void)?
    var keys = KeyBindings()

    private let panel: NSPanel
    private let effect: NSVisualEffectView
    private let scrollView: NSScrollView
    private let stackView: NSView

    private var windows: [Window] = []
    private var selectedRow: Int = 0
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var titleLookup: ((UInt32) -> String?)? = nil

    private var rowH: CGFloat = 36
    private var iconSize: CGFloat = 20
    private var panelW: CGFloat = 500

    init(titleLookup: ((UInt32) -> String?)?) {
        self.titleLookup = titleLookup

        panel = SwitcherWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
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

        stackView = NSView()
        stackView.wantsLayer = true

        scrollView = NSScrollView()
        scrollView.documentView = stackView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .legacy
        scrollView.verticalScroller?.controlSize = .mini
        effect.addSubview(scrollView)

        super.init()
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }

    func show(windows: [Window], visibleRows: Int, width: Double, opacity: Double) {
        guard !windows.isEmpty else { return }
        log.info("show with \(windows.count) windows")
        self.windows = windows
        panel.alphaValue = opacity

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        let sf = screen.visibleFrame

        rowH = min(max(sf.height * 0.044, 38), 56).rounded()
        iconSize = (rowH * 0.56).rounded()
        panelW = max(sf.width * CGFloat(width), 200).rounded()

        let rows = min(windows.count, visibleRows)
        let totalH = rowH * CGFloat(rows)
        let x = sf.origin.x + (sf.width - panelW) / 2
        let y = sf.origin.y + sf.height * 0.67 - totalH
        panel.setFrame(NSRect(x: x, y: y, width: panelW, height: totalH), display: false)
        panel.contentView!.frame = NSRect(origin: .zero, size: NSSize(width: panelW, height: totalH))
        scrollView.frame = NSRect(x: 0, y: 0, width: panelW, height: totalH)

        selectedRow = 0
        rebuildRows()
        let topY = max(stackView.frame.height - scrollView.frame.height, 0)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: topY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        installMonitors()
        panel.makeKeyAndOrderFront(nil)
    }

    func cycleQuickMode() {
        guard !windows.isEmpty else { return }
        selectedRow = (selectedRow + 1) % windows.count
        rebuildRows()
        scrollToSelected()
        notifySelectionChanged()
    }

    func confirmIfVisible() {
        guard panel.isVisible else { return }
        confirm()
    }

    func dismiss() {
        stopMonitors()
        panel.orderOut(nil)
        windows = []
        onDismiss?()
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    // MARK: – Rendering

    private func rebuildRows() {
        stackView.subviews.forEach { $0.removeFromSuperview() }
        let docH = rowH * CGFloat(windows.count)
        stackView.frame = NSRect(x: 0, y: 0, width: panelW, height: max(docH, scrollView.frame.height))

        for (i, win) in windows.enumerated() {
            let y = stackView.frame.height - rowH * CGFloat(i + 1)
            let row = NSView(frame: NSRect(x: 0, y: y, width: panelW, height: rowH))
            row.wantsLayer = true

            if i == selectedRow {
                let highlight = NSView(frame: row.bounds.insetBy(dx: 4, dy: 2))
                highlight.wantsLayer = true
                highlight.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
                highlight.layer?.cornerRadius = 6
                row.addSubview(highlight)
            }

            let imgView = NSImageView(frame: NSRect(x: 10, y: (rowH - iconSize) / 2, width: iconSize, height: iconSize))
            imgView.image = win.app.icon
            imgView.imageScaling = .scaleProportionallyDown
            row.addSubview(imgView)

            let label: String
            let isCustom: Bool
            if let custom = titleLookup?(win.id) {
                label = custom
                isCustom = true
            } else {
                label = win.title.isEmpty ? (win.appName ?? "") : win.title
                isCustom = false
            }

            let lbl = NSTextField(labelWithString: label)
            let fontSize = (rowH * 0.38).rounded()
            lbl.font = isCustom ? .boldSystemFont(ofSize: fontSize) : .systemFont(ofSize: fontSize)
            lbl.textColor = i == selectedRow ? .white : .labelColor
            lbl.lineBreakMode = .byTruncatingTail
            let lblH = fontSize + 4
            lbl.frame = NSRect(x: 10 + iconSize + 8, y: (rowH - lblH) / 2, width: panelW - iconSize - 36, height: lblH)
            row.addSubview(lbl)

            stackView.addSubview(row)
        }
    }

    private func notifySelectionChanged() {
        guard selectedRow >= 0, selectedRow < windows.count else { return }
        onSelectionChanged?(windows[selectedRow])
    }

    private func scrollToSelected() {
        let y = stackView.frame.height - rowH * CGFloat(selectedRow + 1)
        stackView.scrollToVisible(NSRect(x: 0, y: y, width: panelW, height: rowH))
    }

    // MARK: – Input

    private func installMonitors() {
        stopMonitors()
        let navUp = Set(keys.up.map(\.keyCode))
        let navDown = Set(keys.down.map(\.keyCode))
        let confirmKeys = Set(keys.confirm.map(\.keyCode))
        let cancelKeys = Set(keys.cancel.map(\.keyCode))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, panel.isVisible else { return event }
            let k = event.keyCode
            if navDown.contains(k)    { moveSelection(by: 1); return nil }
            if navUp.contains(k)      { moveSelection(by: -1); return nil }
            if confirmKeys.contains(k) { confirm(); return nil }
            if cancelKeys.contains(k)  { dismiss(); return nil }
            return event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp]) { [weak self] event in
            guard let self, panel.isVisible else { return event }
            let point = stackView.convert(event.locationInWindow, from: nil)
            let row = Int((stackView.frame.height - point.y) / rowH)
            guard row >= 0, row < windows.count else { return event }
            if event.type == .leftMouseUp {
                selectedRow = row
                confirm()
            } else {
                selectedRow = row
                rebuildRows()
                notifySelectionChanged()
            }
            return event
        }
    }

    private func stopMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    private func moveSelection(by delta: Int) {
        guard !windows.isEmpty else { return }
        selectedRow = ((selectedRow + delta) % windows.count + windows.count) % windows.count
        rebuildRows()
        scrollToSelected()
        notifySelectionChanged()
    }

    private func confirm() {
        guard selectedRow >= 0, selectedRow < windows.count else { return }
        let win = windows[selectedRow]
        log.info("confirm: \(win.appName ?? "?") — \(win.title)")
        onConfirm?(win)
        dismiss()
    }
}
