import AppKit

/// All dimensions needed to lay out a SpreadsheetView and SpreadsheetPanel.
/// Computed from the screen's visible frame at show time via `forScreen(_:)`.
public struct LayoutConfig: Equatable {
    // Primary dimensions (screen-proportional with clamp)
    public var columnWidth: CGFloat
    public var rowHeight: CGFloat
    public var tabStripHeight: CGFloat

    // Derived dimensions
    public var headerHeight: CGFloat
    public var iconSize: CGFloat

    // Fixed constants
    public var hairlineH: CGFloat
    public var tabCornerRadius: CGFloat

    // Spacing
    public var listInset: CGFloat

    // Panel sizing
    public var minVisibleRows: Int
    public var maxVisibleRows: Int

    // Panel position
    public var centered: Bool
    public var panelX: CGFloat
    public var panelY: CGFloat

    public init(
        columnWidth: CGFloat = 240,
        rowHeight: CGFloat = 44,
        tabStripHeight: CGFloat = 28,
        headerHeight: CGFloat = 28,
        iconSize: CGFloat = 24,
        hairlineH: CGFloat = 1,
        tabCornerRadius: CGFloat = 5,
        listInset: CGFloat = 6,
        minVisibleRows: Int = 1,
        maxVisibleRows: Int = 10,
        centered: Bool = true,
        panelX: CGFloat = 0.1,
        panelY: CGFloat = 0.33
    ) {
        self.columnWidth = columnWidth
        self.rowHeight = rowHeight
        self.tabStripHeight = tabStripHeight
        self.headerHeight = headerHeight
        self.iconSize = iconSize
        self.hairlineH = hairlineH
        self.tabCornerRadius = tabCornerRadius
        self.listInset = listInset
        self.minVisibleRows = minVisibleRows
        self.maxVisibleRows = maxVisibleRows
        self.centered = centered
        self.panelX = panelX
        self.panelY = panelY
    }

    /// Compute layout dimensions proportionally from a screen's visible frame,
    /// using the same ratios as the v1 sizing model.
    public static func forScreen(_ screen: NSScreen) -> LayoutConfig {
        forScreen(screen.visibleFrame.height)
    }

    public static func forScreen(_ visibleHeight: CGFloat) -> LayoutConfig {
        // Primary dimensions: clamp(screenDimension * fraction, min, max).rounded()
        let rowH = clamp(visibleHeight * 0.044, 38, 56).rounded()
        let tabH = clamp(visibleHeight * 0.034, 26, 40).rounded()
        let colW = (rowH * 5).rounded()

        // Derived dimensions
        let hdrH = clamp(rowH * 0.65, 25, 36).rounded()
        let icon = (rowH * 0.56).rounded()

        // Spacing
        let inset = (rowH * 0.15).rounded()

        return LayoutConfig(
            columnWidth: colW,
            rowHeight: rowH,
            tabStripHeight: tabH,
            headerHeight: hdrH,
            iconSize: icon,
            hairlineH: 1,
            tabCornerRadius: 5,
            listInset: inset
        )
    }
}

private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(v, lo), hi)
}
