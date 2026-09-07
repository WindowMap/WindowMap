import AppKit
import Logging

private let log = Log(module: "SpreadsheetView")

private func vid(_ s: String) -> NSUserInterfaceItemIdentifier { .init(s) }

// MARK: – Highlight constants (spec: focus/path system)

private let focusColor = NSColor.controlAccentColor
private let pathAlpha: CGFloat = 0.35
private let phantomFillAlpha: CGFloat = 0.15
private let phantomBorderAlpha: CGFloat = 0.8
private let hairlineAlpha: CGFloat = 0.15
private let cornerRadius: CGFloat = 6

public class SpreadsheetView: NSView {
    private var smallFont: NSFont { .systemFont(ofSize: (layout.rowHeight * 0.28).rounded(), weight: .medium) }
    private var rowFont: NSFont { .systemFont(ofSize: (layout.rowHeight * 0.31).rounded()) }

    private func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }
    private let tabMinWidth: CGFloat = 52
    private let tabHPad: CGFloat = 10
    private let tabSpacing: CGFloat = 4
    private let tabPadding: CGFloat = 8

    private var columnScrollOffsets: [Int: CGFloat] = [:]

    public var layout: LayoutConfig

    public var rowHeight: CGFloat { layout.rowHeight }
    public var headerHeight: CGFloat { layout.headerHeight }

    public func tabStripNaturalWidth(for tabs: [Tab]) -> CGFloat {
        guard !tabs.isEmpty else { return 0 }
        let widths = tabs.map { tab in
            let textW = (tab.name as NSString).size(withAttributes: [.font: smallFont]).width
            return max(textW + tabHPad * 2, tabMinWidth).rounded()
        }
        let spacing = tabPadding * 2 + tabSpacing * CGFloat(max(tabs.count - 1, 0))
        return widths.reduce(0, +) + spacing
    }

    public var columnWidth: CGFloat { layout.columnWidth }
    public var iconSize: CGFloat { layout.iconSize }
    public var hairlineH: CGFloat { layout.hairlineH }
    public var tabStripHeight: CGFloat { layout.tabStripHeight }

    public init(frame: NSRect, layout: LayoutConfig = LayoutConfig()) {
        self.layout = layout
        super.init(frame: frame)
        wantsLayer = true
        identifier = vid("spreadsheet")
    }

    required init?(coder: NSCoder) { fatalError() }

    public func render(state: SpreadsheetState, dataSource: SpreadsheetDataSource) {
        saveColumnScrollOffsets()
        subviews.forEach { $0.removeFromSuperview() }
        log.debug("render: \(state.columns.count) cols, mode=\(state.mode), tab=\(state.activeTab)")

        let renderMode = resolveRenderMode(state)
        let tabStripOffset: CGFloat = state.tabs.isEmpty ? 0 : tabStripHeight + hairlineH

        if !state.tabs.isEmpty {
            renderTabStrip(state: state, renderMode: renderMode)
        }
        renderColumns(state: state, dataSource: dataSource, renderMode: renderMode, tabStripOffset: tabStripOffset)
    }

    private func resolveRenderMode(_ state: SpreadsheetState) -> Mode {
        switch state.mode {
        case .rename:
            switch state.renameTarget {
            case .tab: return .tabNav
            default:   return .browse
            }
        default:
            return state.mode
        }
    }

    private func renderTabStrip(state: SpreadsheetState, renderMode: Mode) {
        let naturalWidths: [CGFloat] = state.tabs.map { tab in
            let textW = (tab.name as NSString).size(withAttributes: [.font: smallFont]).width
            return max(textW + tabHPad * 2, tabMinWidth).rounded()
        }
        let totalSpacing = tabPadding * 2 + tabSpacing * CGFloat(max(state.tabs.count - 1, 0))
        let naturalTotal = naturalWidths.reduce(0, +) + totalSpacing
        let tabWidths = naturalTotal > bounds.width
            ? shrinkToFit(naturalWidths, budget: bounds.width - totalSpacing)
            : naturalWidths

        let tabDocView = NSView(frame: .zero)
        tabDocView.wantsLayer = true
        var tabX = tabPadding
        for i in 0..<state.tabs.count {
            let isActive = i == state.activeTab
            let isFocused = isActive && renderMode == .tabNav
            let isMoveTabFocused = isActive && renderMode == .moveTabNav
            let tabW = tabWidths[i]

            let tabTextH = lineHeight(smallFont)
            let tabH = (tabTextH + 6).rounded()
            let tabY = (tabStripHeight - tabH) / 2

            let tabView = NSView(frame: NSRect(x: tabX, y: tabY, width: tabW, height: tabH))
            tabView.wantsLayer = true
            tabView.identifier = vid("tab-\(i)")

            if isFocused {
                tabView.layer?.backgroundColor = focusColor.cgColor
                tabView.layer?.cornerRadius = cornerRadius
            } else if isMoveTabFocused {
                tabView.layer?.backgroundColor = focusColor.withAlphaComponent(phantomFillAlpha).cgColor
                tabView.layer?.cornerRadius = cornerRadius
                tabView.layer?.borderWidth = 1
                tabView.layer?.borderColor = focusColor.withAlphaComponent(0.4).cgColor
            } else if isActive && [.browse, .move].contains(renderMode) {
                tabView.layer?.backgroundColor = focusColor.withAlphaComponent(pathAlpha).cgColor
                tabView.layer?.cornerRadius = cornerRadius
            }

            let label = NSTextField(labelWithString: state.tabs[i].name)
            label.font = smallFont
            label.textColor = isActive ? .white : .secondaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 0, y: (tabH - tabTextH) / 2, width: tabW, height: tabTextH)
            label.identifier = vid("tab-label-\(i)")
            tabView.addSubview(label)

            tabDocView.addSubview(tabView)
            tabX += tabW + tabSpacing
        }
        tabX += tabPadding - tabSpacing
        tabDocView.frame = NSRect(x: 0, y: 0, width: tabX, height: tabStripHeight)

        let chevronW: CGFloat = 22
        let tabsOverflow = tabDocView.frame.width > bounds.width
        let chevronReserve: CGFloat = tabsOverflow ? chevronW : 0

        let tabScroll = NSScrollView(frame: NSRect(
            x: chevronReserve,
            y: bounds.height - tabStripHeight,
            width: bounds.width - chevronReserve * 2,
            height: tabStripHeight
        ))
        tabScroll.documentView = tabDocView
        tabScroll.hasHorizontalScroller = false
        tabScroll.hasVerticalScroller = false
        tabScroll.drawsBackground = false
        addSubview(tabScroll)

        if state.activeTab < state.tabs.count {
            var activeLeft = tabPadding
            for j in 0..<state.activeTab { activeLeft += tabWidths[j] + tabSpacing }
            scrollIntoView(left: activeLeft, width: tabWidths[state.activeTab], padding: tabPadding, in: tabScroll)
        }

        if tabsOverflow {
            let chevronY = bounds.height - tabStripHeight
            let scrollOffset = tabScroll.contentView.bounds.origin.x
            let docWidth = tabDocView.frame.width
            let tabVisibleWidth = tabScroll.frame.width

            addChevron("\u{2039}", x: 0, y: chevronY, width: chevronW, height: tabStripHeight,
                       id: "tab-chevron-left", hidden: scrollOffset <= 1)
            addChevron("\u{203A}", x: bounds.width - chevronW, y: chevronY, width: chevronW, height: tabStripHeight,
                       id: "tab-chevron-right", hidden: docWidth <= tabVisibleWidth + scrollOffset + 1)
        }

        let sep = NSView(frame: NSRect(x: 0, y: bounds.height - tabStripHeight - hairlineH, width: bounds.width, height: hairlineH))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(hairlineAlpha).cgColor
        sep.identifier = vid("tab-strip-hairline")
        addSubview(sep)
    }

    private func renderColumns(state: SpreadsheetState, dataSource: SpreadsheetDataSource, renderMode: Mode, tabStripOffset: CGFloat) {
        let columnAreaHeight = bounds.height - tabStripOffset
        let totalColumnsWidth = columnWidth * CGFloat(state.columns.count)

        let columnDocView = NSView(frame: NSRect(x: 0, y: 0, width: max(totalColumnsWidth, bounds.width), height: columnAreaHeight))
        columnDocView.wantsLayer = true

        let columnScroll = OverlaidScrollView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: columnAreaHeight))
        columnScroll.documentView = columnDocView
        columnScroll.hasHorizontalScroller = true
        columnScroll.hasVerticalScroller = false
        columnScroll.autohidesScrollers = true
        columnScroll.drawsBackground = false
        columnScroll.scrollerStyle = .legacy
        columnScroll.horizontalScroller?.controlSize = .small
        addSubview(columnScroll)

        let isMoving = renderMode == .move
        let isCarryingRow = isMoving || (renderMode == .moveTabNav && !state.movingColumn)

        for col in 0..<state.columns.count {
            let colView = renderColumn(
                col: col, state: state, dataSource: dataSource,
                renderMode: renderMode, isMoving: isMoving, isCarryingRow: isCarryingRow,
                columnAreaHeight: columnAreaHeight, columnScroll: columnScroll
            )
            columnDocView.addSubview(colView)
        }

        let selectedCol = isMoving ? state.moveTargetColumn : state.selectedColumn
        scrollIntoView(left: columnWidth * CGFloat(selectedCol), width: columnWidth, in: columnScroll)
    }

    private func renderColumn(
        col: Int, state: SpreadsheetState, dataSource: SpreadsheetDataSource,
        renderMode: Mode, isMoving: Bool, isCarryingRow: Bool,
        columnAreaHeight: CGFloat, columnScroll: NSScrollView
    ) -> NSView {
        let isSelectedInBrowse = col == state.selectedColumn && renderMode == .browse
        let isTargetInMove = col == state.moveTargetColumn && isMoving
        let isPathHighlighted = isSelectedInBrowse || isTargetInMove
        let columnIsEmpty = state.columns[col].rowCount == 0
        let headerHasFocus = isSelectedInBrowse && columnIsEmpty
        let isSelectedColumn = isSelectedInBrowse && !columnIsEmpty
        let isPhantomColumn = col == state.phantomColumnIndex
        let x = columnWidth * CGFloat(col)
        let colView = ColumnView(frame: NSRect(x: x, y: 0, width: columnWidth, height: columnAreaHeight))
        colView.wantsLayer = true
        colView.identifier = vid("column-\(col)")

        if isPhantomColumn {
            let bg = NSView(frame: colView.bounds.insetBy(dx: 2, dy: 2))
            bg.wantsLayer = true
            bg.layer?.backgroundColor = focusColor.withAlphaComponent(phantomFillAlpha).cgColor
            bg.layer?.cornerRadius = cornerRadius
            bg.layer?.borderWidth = 1
            bg.layer?.borderColor = focusColor.withAlphaComponent(0.4).cgColor
            colView.addSubview(bg)
        }

        let headerBg = NSView(frame: NSRect(x: 0, y: columnAreaHeight - headerHeight, width: columnWidth, height: headerHeight))
        headerBg.wantsLayer = true
        headerBg.identifier = vid("header-bg-\(col)")
        if isPhantomColumn {
        } else if headerHasFocus {
            headerBg.layer?.backgroundColor = focusColor.cgColor
        } else if isPathHighlighted {
            headerBg.layer?.backgroundColor = focusColor.withAlphaComponent(pathAlpha).cgColor
        }
        colView.addSubview(headerBg)

        let hdr = NSTextField(labelWithString: dataSource.columnName(col))
        hdr.font = smallFont
        hdr.alignment = .center
        hdr.textColor = isPathHighlighted ? .white : .secondaryLabelColor
        let hdrTextH = lineHeight(smallFont)
        let hdrY = columnAreaHeight - headerHeight + (headerHeight - hdrTextH) / 2
        hdr.frame = NSRect(x: 0, y: hdrY, width: columnWidth, height: hdrTextH)
        hdr.identifier = vid("header-\(col)")
        colView.addSubview(hdr)

        colView.addSubview(hairline(frame: NSRect(x: 0, y: columnAreaHeight - headerHeight - hairlineH, width: columnWidth, height: hairlineH)))
        colView.addSubview(hairline(frame: NSRect(x: columnWidth - 1, y: 0, width: 1, height: columnAreaHeight)))

        let hasPhantom = isMoving && col == state.moveTargetColumn
        let phantomOffset: CGFloat = hasPhantom ? 1 : 0
        let rowCount = dataSource.rowCount(in: col)
        let hidesOrigin = isCarryingRow && col == state.moveOriginColumn
        let visibleRowCount = CGFloat(rowCount - (hidesOrigin ? 1 : 0))
        let totalContentRows = visibleRowCount + phantomOffset
        let docHeight = rowHeight * totalContentRows

        let scrollViewHeight = columnAreaHeight - headerHeight - hairlineH
        let scrollView = ForwardingScrollView(frame: NSRect(x: 0, y: 0, width: columnWidth, height: scrollViewHeight))
        scrollView.horizontalTarget = columnScroll
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .legacy
        scrollView.verticalScroller?.controlSize = .mini
        let docView = FlippedDocView(frame: NSRect(x: 0, y: 0, width: columnWidth, height: max(docHeight, scrollViewHeight)))
        docView.wantsLayer = true
        scrollView.documentView = docView

        var visualRow: CGFloat = 0

        if hasPhantom {
            let originLabel = dataSource.rowLabel(column: state.moveOriginColumn, row: state.moveOriginRow)
            let originIcon = dataSource.rowIcon(column: state.moveOriginColumn, row: state.moveOriginRow)
            let phantom = makePhantomRow(
                label: originLabel, icon: originIcon,
                frame: NSRect(x: 0, y: 0, width: columnWidth, height: rowHeight)
            )
            docView.addSubview(phantom)
        }

        for row in 0..<rowCount {
            if isCarryingRow && col == state.moveOriginColumn && row == state.moveOriginRow { continue }
            let y = rowHeight * (visualRow + phantomOffset)
            let isRowSelected = isSelectedColumn && row == state.selectedRow
            let rowView = makeRow(
                column: col, row: row,
                label: dataSource.rowLabel(column: col, row: row),
                icon: dataSource.rowIcon(column: col, row: row),
                selected: isRowSelected,
                boldLabel: dataSource.rowHasCustomLabel(column: col, row: row),
                frame: NSRect(x: 0, y: y, width: columnWidth, height: rowHeight)
            )
            docView.addSubview(rowView)
            visualRow += 1
        }

        if hasPhantom {
            scrollView.contentView.scroll(to: .zero)
        } else if let savedOffset = columnScrollOffsets[col] {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(savedOffset, max(docHeight - scrollViewHeight, 0))))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            if isSelectedColumn && renderMode == .browse {
                let selectedY = rowHeight * CGFloat(state.selectedRow)
                let visibleRect = NSRect(x: 0, y: selectedY, width: columnWidth, height: rowHeight)
                docView.scrollToVisible(visibleRect)
            }
        }

        colView.addSubview(scrollView)
        return colView
    }

    public func columnScrollOffset(for col: Int) -> CGFloat {
        guard let columnScroll = subviews.first(where: { $0 is OverlaidScrollView }) as? NSScrollView,
              let docView = columnScroll.documentView,
              col < docView.subviews.count,
              let sv = docView.subviews[col].subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
        else { return 0 }
        return sv.contentView.bounds.origin.y
    }

    private func saveColumnScrollOffsets() {
        columnScrollOffsets.removeAll()
        guard let columnScroll = subviews.first(where: { $0 is OverlaidScrollView }) as? NSScrollView,
              let docView = columnScroll.documentView else { return }
        for (i, colView) in docView.subviews.enumerated() {
            if let sv = colView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
                columnScrollOffsets[i] = sv.contentView.bounds.origin.y
            }
        }
    }

    private func scrollIntoView(left: CGFloat, width: CGFloat, padding: CGFloat = 0, in scrollView: NSScrollView) {
        let right = left + width
        let visible = scrollView.frame.width
        let offset = scrollView.contentView.bounds.origin.x
        if left < offset {
            scrollView.contentView.scroll(to: NSPoint(x: max(0, left - padding), y: 0))
        } else if right > offset + visible {
            scrollView.contentView.scroll(to: NSPoint(x: right - visible + padding, y: 0))
        }
    }

    private func shrinkToFit(_ widths: [CGFloat], budget: CGFloat) -> [CGFloat] {
        var result = widths
        var total = result.reduce(0, +)
        while total > budget {
            let maxW = result.max()!
            if maxW <= tabMinWidth { break }
            let secondMax = result.filter { $0 < maxW }.max() ?? tabMinWidth
            let target = max(secondMax, tabMinWidth)
            let excess = total - budget
            let countAtMax = CGFloat(result.filter { $0 == maxW }.count)
            let reduction = min(maxW - target, excess / countAtMax).rounded()
            if reduction < 1 { break }
            result = result.map { $0 == maxW ? $0 - reduction : $0 }
            total = result.reduce(0, +)
        }
        return result.map { max($0, tabMinWidth).rounded() }
    }

    private func addChevron(_ char: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, id: String, hidden: Bool) {
        let label = NSTextField(labelWithString: char)
        let font = NSFont.systemFont(ofSize: (layout.rowHeight * 0.38).rounded(), weight: .medium)
        label.font = font
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        let textH = lineHeight(font)
        let yOffset = y + (height - textH) / 2
        label.frame = NSRect(x: x, y: yOffset, width: width, height: textH)
        label.identifier = vid(id)
        label.isHidden = hidden
        addSubview(label)
    }

    private func hairline(frame: NSRect) -> NSView {
        let v = NSView(frame: frame)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(hairlineAlpha).cgColor
        return v
    }

    private func addRowContent(to v: NSView, label: String, icon: NSImage?, textColor: NSColor, iconAlpha: CGFloat = 1, boldLabel: Bool = false, iconId: String? = nil, labelId: String? = nil) {
        let margin = (layout.rowHeight * 0.22).rounded()
        if let icon {
            let imgView = NSImageView(frame: NSRect(x: margin, y: (v.frame.height - iconSize) / 2, width: iconSize, height: iconSize))
            imgView.image = icon
            imgView.imageScaling = .scaleProportionallyDown
            imgView.alphaValue = iconAlpha
            if let iconId { imgView.identifier = vid(iconId) }
            v.addSubview(imgView)
        }

        let lbl = NSTextField(labelWithString: label)
        let font = boldLabel ? NSFont.boldSystemFont(ofSize: rowFont.pointSize) : rowFont
        lbl.font = font
        lbl.textColor = textColor
        lbl.lineBreakMode = .byTruncatingTail
        let textH = lineHeight(font)
        lbl.frame = NSRect(x: margin + iconSize + margin * 0.6, y: (v.frame.height - textH) / 2, width: v.frame.width - iconSize - margin * 2.6, height: textH)
        if let labelId { lbl.identifier = vid(labelId) }
        v.addSubview(lbl)
    }

    private func makeRow(column: Int, row: Int, label: String, icon: NSImage?, selected: Bool, boldLabel: Bool = false, frame: NSRect) -> NSView {
        let v = NSView(frame: frame)
        v.wantsLayer = true
        v.identifier = vid("row-\(column)-\(row)")

        if selected {
            let highlight = NSView(frame: v.bounds.insetBy(dx: 4, dy: 2))
            highlight.wantsLayer = true
            highlight.layer?.backgroundColor = focusColor.cgColor
            highlight.layer?.cornerRadius = cornerRadius
            highlight.identifier = vid("selection")
            v.addSubview(highlight)
        }

        addRowContent(to: v, label: label, icon: icon,
                      textColor: selected ? .white : .labelColor,
                      boldLabel: boldLabel,
                      iconId: "icon-\(column)-\(row)", labelId: "label-\(column)-\(row)")
        return v
    }

    private func makePhantomRow(label: String, icon: NSImage?, frame: NSRect) -> NSView {
        let v = NSView(frame: frame)
        v.wantsLayer = true
        v.identifier = vid("phantom")

        let bg = NSView(frame: v.bounds.insetBy(dx: 4, dy: 2))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = focusColor.withAlphaComponent(phantomFillAlpha).cgColor
        bg.layer?.cornerRadius = cornerRadius
        bg.layer?.borderWidth = 1.5
        bg.layer?.borderColor = focusColor.withAlphaComponent(phantomBorderAlpha).cgColor
        v.addSubview(bg)

        addRowContent(to: v, label: label, icon: icon, textColor: .secondaryLabelColor, iconAlpha: 0.6)
        return v
    }
}

private class ColumnView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private class FlippedDocView: NSView {
    override var isFlipped: Bool { true }
}

private class OverlaidScrollView: NSScrollView {
    override func tile() {
        super.tile()
        contentView.frame = bounds
    }
}

private class ForwardingScrollView: NSScrollView {
    weak var horizontalTarget: NSScrollView?
    override func tile() {
        super.tile()
        contentView.frame = bounds
    }
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
           let target = horizontalTarget {
            target.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: – View query helpers (for tests)

public extension NSView {
    func findView(id: String) -> NSView? {
        if identifier?.rawValue == id { return self }
        for sub in subviews {
            if let found = sub.findView(id: id) { return found }
        }
        return nil
    }

    func findAllViews(id: String) -> [NSView] {
        var result: [NSView] = []
        if identifier?.rawValue == id { result.append(self) }
        for sub in subviews { result.append(contentsOf: sub.findAllViews(id: id)) }
        return result
    }

    func findLabel(id: String) -> NSTextField? {
        findView(id: id) as? NSTextField
    }
}
