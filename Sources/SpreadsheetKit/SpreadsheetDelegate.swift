public protocol SpreadsheetDelegate: AnyObject {
    func spreadsheetDidConfirm(column: Int, row: Int)
    func spreadsheetDidCancel()
    func spreadsheetDidRequestAddRow()
    func spreadsheetDidRequestAddColumn()
    func spreadsheetDidRequestDeleteColumn(column: Int)
    func spreadsheetDidRequestCloseRow(column: Int, row: Int)
    func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int)
    func spreadsheetDidRequestMoveColumn(column: Int)
    func spreadsheetDidRequestAddTab()
    func spreadsheetDidRequestDeleteTab(index: Int)
    func spreadsheetDidSwitchTab(index: Int)
    func spreadsheetDidSwitchMoveTab(index: Int)
    func spreadsheetDidDescendFromMoveTabNav()
    func spreadsheetDidCancelMoveTabNav()
    func spreadsheetDidConfirmMoveTab(index: Int)
    func spreadsheetDidRequestRename(target: PanelTarget, value: String)
    func spreadsheetDidRightClick(target: PanelTarget)
}

public extension SpreadsheetDelegate {
    func spreadsheetDidRequestAddRow() {}
    func spreadsheetDidRequestMoveColumn(column: Int) {}
    func spreadsheetDidSwitchMoveTab(index: Int) {}
    func spreadsheetDidDescendFromMoveTabNav() {}
    func spreadsheetDidCancelMoveTabNav() {}
    func spreadsheetDidConfirmMoveTab(index: Int) {}
    func spreadsheetDidRightClick(target: PanelTarget) {}
}
