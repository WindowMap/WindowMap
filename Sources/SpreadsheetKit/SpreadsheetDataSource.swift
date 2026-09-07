import AppKit

public protocol SpreadsheetDataSource: AnyObject {
    var columnCount: Int { get }
    func columnName(_ column: Int) -> String
    func rowCount(in column: Int) -> Int
    func rowLabel(column: Int, row: Int) -> String
    func rowHasCustomLabel(column: Int, row: Int) -> Bool
    func rowIcon(column: Int, row: Int) -> NSImage?
}

public extension SpreadsheetDataSource {
    func rowHasCustomLabel(column: Int, row: Int) -> Bool { false }
}
