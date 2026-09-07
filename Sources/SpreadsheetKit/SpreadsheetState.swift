import Foundation

public struct Tab: Equatable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct Column: Equatable {
    public var id: UUID
    public var name: String
    public var rowCount: Int
    public init(id: UUID = UUID(), name: String, rowCount: Int) {
        self.id = id; self.name = name; self.rowCount = rowCount
    }
}

public enum Mode: Equatable, CaseIterable {
    case browse
    case tabNav
    case move
    case moveTabNav
    case rename
}

public enum PanelTarget: Equatable {
    case row(column: Int, row: Int)
    case columnHeader(column: Int)
    case tab(index: Int)
    case tabStrip
}

public struct SpreadsheetState: Equatable {
    public var tabs: [Tab]
    public var activeTab: Int
    public var columns: [Column]
    public var selectedColumn: Int
    public var selectedRow: Int
    public var mode: Mode
    public var moveOriginColumn: Int
    public var moveOriginRow: Int
    public var moveTargetColumn: Int
    public var movingColumn: Bool
    public var phantomColumnIndex: Int?
    public var renameTarget: PanelTarget?
    public var quickSession: Bool

    public init(
        tabs: [Tab] = [],
        activeTab: Int = 0,
        columns: [Column] = [],
        selectedColumn: Int = 0,
        selectedRow: Int = 0,
        mode: Mode = .browse,
        moveOriginColumn: Int = 0,
        moveOriginRow: Int = 0,
        moveTargetColumn: Int = 0,
        movingColumn: Bool = false,
        phantomColumnIndex: Int? = nil,
        renameTarget: PanelTarget? = nil,
        quickSession: Bool = false
    ) {
        self.tabs = tabs
        self.activeTab = activeTab
        self.columns = columns
        self.selectedColumn = selectedColumn
        self.selectedRow = selectedRow
        self.mode = mode
        self.moveOriginColumn = moveOriginColumn
        self.moveOriginRow = moveOriginRow
        self.moveTargetColumn = moveTargetColumn
        self.movingColumn = movingColumn
        self.phantomColumnIndex = phantomColumnIndex
        self.renameTarget = renameTarget
        self.quickSession = quickSession
    }
}
