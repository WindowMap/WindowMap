import AppKit
import SpreadsheetKit
import WindowMapCore

public class WindowMapDataSource: SpreadsheetDataSource {
    public var columns: [(Workspace, [Window])] = []
    public var titleLookup: ((UInt32) -> String?)? = nil

    public init() {}

    public var columnCount: Int { columns.count }

    public func columnName(_ column: Int) -> String {
        guard column < columns.count else { return "" }
        return columns[column].0.name
    }

    public func rowCount(in column: Int) -> Int {
        guard column < columns.count else { return 0 }
        return columns[column].1.count
    }

    public func rowLabel(column: Int, row: Int) -> String {
        guard column < columns.count, row < columns[column].1.count else { return "" }
        let win = columns[column].1[row]
        if let custom = titleLookup?(win.id) { return custom }
        return win.title.isEmpty ? (win.appName ?? "") : win.title
    }

    public func rowHasCustomLabel(column: Int, row: Int) -> Bool {
        guard column < columns.count, row < columns[column].1.count else { return false }
        return titleLookup?(columns[column].1[row].id) != nil
    }

    public func rowIcon(column: Int, row: Int) -> NSImage? {
        guard column < columns.count, row < columns[column].1.count else { return nil }
        return columns[column].1[row].app.icon
    }

    public func window(column: Int, row: Int) -> Window? {
        guard column < columns.count, row < columns[column].1.count else { return nil }
        return columns[column].1[row]
    }

    public func position(of windowId: UInt32) -> (column: Int, row: Int)? {
        for c in columns.indices {
            if let r = columns[c].1.firstIndex(where: { $0.id == windowId }) {
                return (c, r)
            }
        }
        return nil
    }
}
