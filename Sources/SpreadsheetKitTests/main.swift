import AppKit
import Foundation
import ObjectiveC
@testable import SpreadsheetKit

// MARK: – Test harness

private var testCount = 0
private var failCount = 0

func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        testCount += 1
        print("✓  \(name)")
    } catch {
        testCount += 1; failCount += 1
        print("✗  \(name)")
        print("   \(error)")
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { description = msg }
}

func expect<T: Equatable>(_ a: T, equals b: T, file: String = #file, line: Int = #line) throws {
    guard a == b else { throw TestFailure("expected \(b), got \(a) (\(file):\(line))") }
}

func expectTrue(_ v: Bool, file: String = #file, line: Int = #line) throws {
    guard v else { throw TestFailure("expected true (\(file):\(line))") }
}

// MARK: – Helpers

func makeState(
    tabs: Int = 2,
    columns: [(String, Int)] = [("Col0", 3), ("Col1", 2)],
    selectedColumn: Int = 0,
    selectedRow: Int = 0,
    mode: Mode = .browse
) -> SpreadsheetState {
    SpreadsheetState(
        tabs: (0..<tabs).map { Tab(name: "Tab\($0)") },
        activeTab: 0,
        columns: columns.map { Column(name: $0.0, rowCount: $0.1) },
        selectedColumn: selectedColumn,
        selectedRow: selectedRow,
        mode: mode
    )
}

func apply(_ state: inout SpreadsheetState, _ action: SpreadsheetAction) {
    reduce(state: &state, action: action)
}

// MARK: – Browse: down

test("down moves to next row") {
    var s = makeState(selectedRow: 0)
    apply(&s, .keyDown(.down))
    try expect(s.selectedRow, equals: 1)
    try expect(s.mode, equals: .browse)
}

test("down from last row enters tabNav") {
    var s = makeState(selectedRow: 2)
    apply(&s, .keyDown(.down))
    try expect(s.mode, equals: .tabNav)
}

test("down in empty column enters tabNav") {
    var s = makeState(columns: [("Empty", 0)])
    apply(&s, .keyDown(.down))
    try expect(s.mode, equals: .tabNav)
}

// MARK: – Browse: up

test("up moves to previous row") {
    var s = makeState(selectedRow: 2)
    apply(&s, .keyDown(.up))
    try expect(s.selectedRow, equals: 1)
}

test("up from first row enters tabNav") {
    var s = makeState(selectedRow: 0)
    apply(&s, .keyDown(.up))
    try expect(s.mode, equals: .tabNav)
}

// MARK: – Browse: left/right

test("right moves to next column") {
    var s = makeState(selectedColumn: 0)
    apply(&s, .keyDown(.right))
    try expect(s.selectedColumn, equals: 1)
}

test("right from last column wraps") {
    var s = makeState(selectedColumn: 1)
    apply(&s, .keyDown(.right))
    try expect(s.selectedColumn, equals: 0)
}

test("left from first column wraps") {
    var s = makeState(selectedColumn: 0)
    apply(&s, .keyDown(.left))
    try expect(s.selectedColumn, equals: 1)
}

test("column switch resets row to 0") {
    var s = makeState(selectedColumn: 0, selectedRow: 2)
    apply(&s, .keyDown(.right))
    try expect(s.selectedColumn, equals: 1)
    try expect(s.selectedRow, equals: 0)
}

// MARK: – TabNav

test("tabNav left/right navigates tabs") {
    var s = makeState(mode: .tabNav)
    apply(&s, .keyDown(.right))
    try expect(s.activeTab, equals: 1)
    apply(&s, .keyDown(.left))
    try expect(s.activeTab, equals: 0)
}

test("tabNav down returns to browse at row 0") {
    var s = makeState(mode: .tabNav)
    apply(&s, .keyDown(.down))
    try expect(s.mode, equals: .browse)
    try expect(s.selectedRow, equals: 0)
}

test("tabNav up returns to browse at last row") {
    var s = makeState(mode: .tabNav)
    apply(&s, .keyDown(.up))
    try expect(s.mode, equals: .browse)
    try expect(s.selectedRow, equals: 2)
}

test("tabNav confirm returns to browse") {
    var s = makeState(mode: .tabNav)
    apply(&s, .keyDown(.confirm))
    try expect(s.mode, equals: .browse)
}

test("tabNav wraps") {
    var s = makeState(mode: .tabNav)
    s.activeTab = 1
    apply(&s, .keyDown(.right))
    try expect(s.activeTab, equals: 0)
}

// MARK: – Mouse

test("mouse move selects row") {
    var s = makeState()
    apply(&s, .mouseMove(column: 1, row: 1))
    try expect(s.selectedColumn, equals: 1)
    try expect(s.selectedRow, equals: 1)
}

test("mouse move exits tabNav") {
    var s = makeState(mode: .tabNav)
    apply(&s, .mouseMove(column: 0, row: 0))
    try expect(s.mode, equals: .browse)
}

test("mouse click tab switches tab in browse mode") {
    var s = makeState()
    apply(&s, .mouseClickTab(index: 1))
    try expect(s.mode, equals: .browse)
    try expect(s.activeTab, equals: 1)
    try expect(s.selectedRow, equals: 0)
}

test("mouse move out of bounds ignored") {
    var s = makeState(selectedColumn: 0, selectedRow: 1)
    apply(&s, .mouseMove(column: 5, row: 0))
    try expect(s.selectedColumn, equals: 0)
    try expect(s.selectedRow, equals: 1)
}

// MARK: – KeyCombo matching

test("KeyCombo matches keyCode and modifiers") {
    let combo = KeyCombo(keyCode: 45, modifiers: .shift)
    try expectTrue(combo.matches(keyCode: 45, modifiers: .shift))
    try expect(combo.matches(keyCode: 45, modifiers: []), equals: false)
    try expect(combo.matches(keyCode: 99, modifiers: .shift), equals: false)
}

test("KeyCombo with no modifier matches plain key") {
    let combo = KeyCombo(keyCode: 36, modifiers: [])
    try expectTrue(combo.matches(keyCode: 36, modifiers: []))
    try expectTrue(combo.matches(keyCode: 36, modifiers: .capsLock))
    try expect(combo.matches(keyCode: 36, modifiers: .shift), equals: false)
}

test("KeyCombo ignores capsLock in modifier comparison") {
    let combo = KeyCombo(keyCode: 45, modifiers: .shift)
    try expectTrue(combo.matches(keyCode: 45, modifiers: [.shift, .capsLock]))
}

test("KeyBindings action(for:) returns correct action") {
    var keys = KeyBindings()
    keys.addColumn = [KeyCombo(keyCode: 45, modifiers: .shift)]
    keys.moveRow = [KeyCombo(keyCode: 46, modifiers: [])]

    try expect(keys.action(forKeyCode: 45, modifiers: .shift) == .dataAction(.addColumn), equals: true)
    try expect(keys.action(forKeyCode: 46, modifiers: []) == .dataAction(.moveRow), equals: true)
    try expect(keys.action(forKeyCode: 45, modifiers: []) == nil, equals: true)
}

// MARK: – Move mode: enter

test("moveRow enters move mode") {
    var s = makeState()
    apply(&s, .dataAction(.moveRow))
    try expect(s.mode, equals: .move)
    try expect(s.moveOriginColumn, equals: 0)
    try expect(s.moveOriginRow, equals: 0)
    try expect(s.moveTargetColumn, equals: 0)
}

test("moveRow with single column stays in browse") {
    var s = makeState(columns: [("A", 2)])
    apply(&s, .dataAction(.moveRow))
    try expect(s.mode, equals: .browse)
}

test("moveRow with empty column stays in browse") {
    var s = makeState(columns: [("A", 0), ("B", 1)])
    apply(&s, .dataAction(.moveRow))
    try expect(s.mode, equals: .browse)
}

// MARK: – Move mode: navigate

test("move right moves phantom to next column") {
    var s = makeState()
    apply(&s, .dataAction(.moveRow))
    apply(&s, .keyDown(.right))
    try expect(s.moveTargetColumn, equals: 1)
}

test("move right wraps around") {
    var s = makeState(selectedColumn: 1)
    apply(&s, .dataAction(.moveRow))
    try expect(s.moveTargetColumn, equals: 1)
    apply(&s, .keyDown(.right))
    try expect(s.moveTargetColumn, equals: 0)
}

test("move left moves phantom to previous column") {
    var s = makeState(selectedColumn: 1)
    apply(&s, .dataAction(.moveRow))
    apply(&s, .keyDown(.left))
    try expect(s.moveTargetColumn, equals: 0)
}

test("move left wraps around") {
    var s = makeState()
    apply(&s, .dataAction(.moveRow))
    apply(&s, .keyDown(.left))
    try expect(s.moveTargetColumn, equals: 1)
}

// MARK: – Move mode: cancel

test("move cancel returns to browse at origin") {
    var s = makeState(selectedColumn: 0, selectedRow: 1)
    apply(&s, .dataAction(.moveRow))
    apply(&s, .keyDown(.right))
    try expect(s.moveTargetColumn, equals: 1)

    apply(&s, .keyDown(.cancel))
    try expect(s.mode, equals: .browse)
    try expect(s.selectedColumn, equals: 0)
    try expect(s.selectedRow, equals: 1)
}

// MARK: – Quick mode

test("quick session up/down navigates like browse") {
    var s = SpreadsheetState(
        tabs: [Tab(name: "T0")],
        columns: [Column(name: "A", rowCount: 3)],
        selectedColumn: 0, selectedRow: 2, quickSession: true
    )
    apply(&s, .keyDown(.down))
    try expect(s.mode, equals: .tabNav)
    apply(&s, .keyDown(.down))
    try expect(s.mode, equals: .browse)
    try expect(s.selectedRow, equals: 0)
}

test("quick session left/right wraps columns") {
    var s = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1), Column(name: "B", rowCount: 1)],
        selectedColumn: 1, selectedRow: 0, quickSession: true
    )
    apply(&s, .keyDown(.right))
    try expect(s.selectedColumn, equals: 0)
    apply(&s, .keyDown(.left))
    try expect(s.selectedColumn, equals: 1)
}

test("quick session cancel stays in browse") {
    var s = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, quickSession: true
    )
    apply(&s, .keyDown(.cancel))
    try expect(s.mode, equals: .browse)
}

test("quick session enters tabNav and returns to browse") {
    var s = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")],
        columns: [Column(name: "A", rowCount: 2)],
        selectedColumn: 0, selectedRow: 1, quickSession: true
    )
    apply(&s, .keyDown(.down))
    try expect(s.mode, equals: .tabNav)
    apply(&s, .keyDown(.right))
    try expect(s.activeTab, equals: 1)
    apply(&s, .keyDown(.down))
    try expect(s.mode, equals: .browse)
}

test("cycleQuickMode navigates down") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2", "r3"])])
    panel.state.quickSession = true
    panel.state.selectedRow = 0
    panel.cycleQuickMode()
    try expect(panel.state.selectedRow, equals: 1)
    panel.dismiss()
}

test("cycleQuickMode enters tabNav at bottom") {
    let (panel, _) = makePanelWithTabs(columns: [("A", ["r1", "r2"])], tabs: ["T0", "T1"])
    panel.state.quickSession = true
    panel.state.selectedRow = 1
    panel.cycleQuickMode()
    try expect(panel.state.mode, equals: .tabNav)
    panel.dismiss()
}

test("confirmIfVisible only acts in quick session") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    panel.confirmIfVisible()
    try expect(panel.isVisible, equals: false)

    let (panel2, _) = makePanel(columns: [("A", ["r1"])])
    panel2.state.quickSession = true
    panel2.confirmIfVisible()
    try expect(panel2.isVisible, equals: false)
}

test("data actions blocked in quick session") {
    let (panel, _) = makePanel(columns: [("A", ["r1"]), ("B", ["r1"])])
    panel.state.quickSession = true
    panel.apply(.dataAction(.moveRow))
    try expect(panel.state.mode, equals: .browse)
    panel.dismiss()
}

// MARK: – Right-click

class RightClickDelegate: SpreadsheetDelegate {
    var onRightClick: ((PanelTarget) -> Void)?
    func spreadsheetDidConfirm(column: Int, row: Int) {}
    func spreadsheetDidCancel() {}
    func spreadsheetDidRequestAddColumn() {}
    func spreadsheetDidRequestDeleteColumn(column: Int) {}
    func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
    func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
    func spreadsheetDidRequestAddTab() {}
    func spreadsheetDidRequestDeleteTab(index: Int) {}
    func spreadsheetDidSwitchTab(index: Int) {}
    func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    func spreadsheetDidRightClick(target: PanelTarget) { onRightClick?(target) }
}

func rowPoint(in panel: SpreadsheetPanel, column: Int, row: Int) -> NSPoint {
    let sv = panel.spreadsheetView
    let tabStripOffset: CGFloat = panel.state.tabs.isEmpty ? 0 : sv.tabStripHeight + sv.hairlineH
    let x = sv.columnWidth * CGFloat(column) + sv.columnWidth / 2
    let y = sv.bounds.height - tabStripOffset - sv.headerHeight - sv.hairlineH - sv.rowHeight * CGFloat(row) - sv.rowHeight / 2
    return NSPoint(x: x, y: y)
}

func headerPoint(in panel: SpreadsheetPanel, column: Int) -> NSPoint {
    let sv = panel.spreadsheetView
    let tabStripOffset: CGFloat = panel.state.tabs.isEmpty ? 0 : sv.tabStripHeight + sv.hairlineH
    let x = sv.columnWidth * CGFloat(column) + sv.columnWidth / 2
    let y = sv.bounds.height - tabStripOffset - sv.headerHeight / 2
    return NSPoint(x: x, y: y)
}

test("right-click on row selects and calls delegate") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"]), ("B", ["r1"])])
    var rightClickTarget: PanelTarget?
    let d = RightClickDelegate()
    d.onRightClick = { rightClickTarget = $0 }
    panel.spreadsheetDelegate = d

    panel.handleRightClick(point: rowPoint(in: panel, column: 1, row: 0))

    try expect(panel.state.selectedColumn, equals: 1)
    try expect(panel.state.selectedRow, equals: 0)
    try expect(rightClickTarget, equals: .row(column: 1, row: 0))
    panel.dismiss()
}

test("right-click on column header calls delegate with columnHeader target") {
    let (panel, _) = makePanel(columns: [("A", []), ("B", ["r1"])])
    var rightClickTarget: PanelTarget?
    let d = RightClickDelegate()
    d.onRightClick = { rightClickTarget = $0 }
    panel.spreadsheetDelegate = d

    panel.handleRightClick(point: headerPoint(in: panel, column: 0))

    try expect(panel.state.selectedColumn, equals: 0)
    try expect(rightClickTarget, equals: .columnHeader(column: 0))
    panel.dismiss()
}

test("right-click blocked in quick session") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    var rightClickCalled = false
    let d = RightClickDelegate()
    d.onRightClick = { _ in rightClickCalled = true }
    panel.spreadsheetDelegate = d

    panel.state.quickSession = true
    panel.handleRightClick(point: rowPoint(in: panel, column: 0, row: 0))

    try expect(rightClickCalled, equals: false)
    panel.dismiss()
}

test("right-click blocked in rename mode") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    var rightClickCalled = false
    let d = RightClickDelegate()
    d.onRightClick = { _ in rightClickCalled = true }
    panel.spreadsheetDelegate = d

    panel.state.mode = .rename
    panel.handleRightClick(point: rowPoint(in: panel, column: 0, row: 0))

    try expect(rightClickCalled, equals: false)
    panel.dismiss()
}

test("startRename enters rename mode for specific target") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"]), ("B", ["r1"])])
    panel.startRename(for: .columnHeader(column: 1))
    try expect(panel.state.mode, equals: .rename)
    try expect(panel.state.renameTarget, equals: .columnHeader(column: 1))
    panel.dismiss()
}

// MARK: – Mouse drag

func makePanelWithTabs(
    columns: [(String, [String])],
    tabs: [String]
) -> (SpreadsheetPanel, MockDataSource) {
    let ds = MockDataSource(columns)
    let state = SpreadsheetState(
        tabs: tabs.map { Tab(name: $0) }, activeTab: 0,
        columns: columns.map { Column(name: $0.0, rowCount: $0.1.count) },
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    panel.layoutForState()
    return (panel, ds)
}

func tabPoint(in panel: SpreadsheetPanel, index: Int) -> NSPoint {
    let sv = panel.spreadsheetView
    guard let tabView = sv.findView(id: "tab-\(index)") else {
        return NSPoint(x: sv.bounds.width / 2, y: sv.bounds.height - sv.tabStripHeight / 2)
    }
    let frame = tabView.convert(tabView.bounds, to: sv)
    return NSPoint(x: frame.midX, y: frame.midY)
}

test("row drag within context moves window") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"]), ("B", ["r1"])])
    var moveCol: Int?
    var moveToCol: Int?

    class MoveDelegate: SpreadsheetDelegate {
        var onMove: ((Int, Int) -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) { onMove?(column, toColumn) }
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = MoveDelegate()
    d.onMove = { moveCol = $0; moveToCol = $1 }
    panel.spreadsheetDelegate = d

    panel.simulateMouseDown(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseDragged(to: rowPoint(in: panel, column: 1, row: 0))
    panel.simulateMouseUp(at: rowPoint(in: panel, column: 1, row: 0))

    try expect(moveCol, equals: 0)
    try expect(moveToCol, equals: 1)
    panel.dismiss()
}

test("header drag initiates workspace move") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1"]), ("B", ["r1"])],
        tabs: ["T0", "T1"]
    )
    var moveColumnCalled = false

    class MoveColDelegate: SpreadsheetDelegate {
        var onMoveColumn: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestMoveColumn(column: Int) { onMoveColumn?() }
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = MoveColDelegate()
    d.onMoveColumn = { moveColumnCalled = true }
    panel.spreadsheetDelegate = d

    panel.simulateMouseDown(at: headerPoint(in: panel, column: 0))
    panel.simulateMouseDragged(to: tabPoint(in: panel, index: 1))

    try expectTrue(moveColumnCalled)
    panel.dismiss()
}

test("tab hover during window drag calls switchMoveTab and descend") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1", "r2"]), ("B", ["r1"])],
        tabs: ["T0", "T1"]
    )
    var switchTabIndex: Int?
    var descendCalled = false

    class DragDelegate: SpreadsheetDelegate {
        var onSwitchMoveTab: ((Int) -> Void)?
        var onDescend: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) { onSwitchMoveTab?(index) }
        func spreadsheetDidDescendFromMoveTabNav() { onDescend?() }
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = DragDelegate()
    d.onSwitchMoveTab = { switchTabIndex = $0 }
    d.onDescend = { descendCalled = true }
    panel.spreadsheetDelegate = d

    panel.simulateMouseDown(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseDragged(to: rowPoint(in: panel, column: 1, row: 0))
    try expect(panel.state.mode, equals: .move)

    panel.simulateMouseDragged(to: tabPoint(in: panel, index: 1))

    try expect(switchTabIndex, equals: 1)
    try expectTrue(descendCalled)
    try expect(panel.state.mode, equals: .move)
    panel.dismiss()
}

test("header drag without multiple tabs does not initiate") {
    let (panel, _) = makePanel(columns: [("A", ["r1"]), ("B", ["r1"])])
    panel.simulateMouseDown(at: headerPoint(in: panel, column: 0))
    panel.simulateMouseDragged(to: headerPoint(in: panel, column: 1))
    try expect(panel.isDragging, equals: false)
    panel.dismiss()
}

// MARK: – Tab hover entry gate

test("hover from row to non-active tab does not switch immediately") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1", "r2"]), ("B", ["r1"])],
        tabs: ["T0", "T1"]
    )
    panel.tabSwitchOnHover = true
    panel.tabHoverDelay = 0.5

    panel.simulateMouseHover(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseHover(at: tabPoint(in: panel, index: 1))

    try expect(panel.state.activeTab, equals: 0)
    panel.dismiss()
}

test("hover from row to non-active tab switches after delay") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1", "r2"]), ("B", ["r1"])],
        tabs: ["T0", "T1"]
    )
    panel.tabSwitchOnHover = true
    panel.tabHoverDelay = 0.05

    panel.simulateMouseHover(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseHover(at: tabPoint(in: panel, index: 1))

    try expect(panel.state.activeTab, equals: 0)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    try expect(panel.state.activeTab, equals: 1)
    panel.dismiss()
}

test("hover from row through tab back to row cancels switch") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1", "r2"]), ("B", ["r1"])],
        tabs: ["T0", "T1"]
    )
    panel.tabSwitchOnHover = true
    panel.tabHoverDelay = 0.05

    panel.simulateMouseHover(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseHover(at: tabPoint(in: panel, index: 1))
    panel.simulateMouseHover(at: rowPoint(in: panel, column: 0, row: 0))

    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    try expect(panel.state.activeTab, equals: 0)
    panel.dismiss()
}

test("tab-to-tab hover after gate opens uses normal delay") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1", "r2"]), ("B", ["r1"])],
        tabs: ["T0", "T1", "T2"]
    )
    panel.tabSwitchOnHover = true
    panel.tabHoverDelay = 0.05

    panel.simulateMouseHover(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseHover(at: tabPoint(in: panel, index: 0))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

    panel.simulateMouseHover(at: tabPoint(in: panel, index: 1))
    try expect(panel.state.activeTab, equals: 0)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    try expect(panel.state.activeTab, equals: 1)
    panel.dismiss()
}

test("hover on active tab from row does not switch") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1", "r2"]), ("B", ["r1"])],
        tabs: ["T0", "T1"]
    )
    panel.tabSwitchOnHover = true
    panel.tabHoverDelay = 0.05

    panel.simulateMouseHover(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseHover(at: tabPoint(in: panel, index: 0))

    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    try expect(panel.state.activeTab, equals: 0)
    panel.dismiss()
}

test("re-entering tab strip restarts gate") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1", "r2"]), ("B", ["r1"])],
        tabs: ["T0", "T1"]
    )
    panel.tabSwitchOnHover = true
    panel.tabHoverDelay = 0.5

    panel.simulateMouseHover(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseHover(at: tabPoint(in: panel, index: 1))
    panel.simulateMouseHover(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseHover(at: tabPoint(in: panel, index: 1))

    try expect(panel.state.activeTab, equals: 0)
    panel.dismiss()
}

// MARK: – Move: single column fallthrough

test("moveRow with single column and multiple tabs delegates moveColumn") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1", "r2"])],
        tabs: ["T0", "T1"]
    )
    var moveColumnCalled = false

    class SingleColMoveDelegate: SpreadsheetDelegate {
        var onMoveColumn: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestMoveColumn(column: Int) { onMoveColumn?() }
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = SingleColMoveDelegate()
    d.onMoveColumn = { moveColumnCalled = true }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.moveRow))
    try expectTrue(moveColumnCalled)
    panel.dismiss()
}

test("moveRow with single column and single tab is no-op") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1"])],
        tabs: ["T0"]
    )
    panel.apply(.dataAction(.moveRow))
    try expect(panel.state.mode, equals: .browse)
    panel.dismiss()
}

test("drag with single column and multiple tabs delegates moveColumn") {
    let (panel, _) = makePanelWithTabs(
        columns: [("A", ["r1", "r2"])],
        tabs: ["T0", "T1"]
    )
    var moveColumnCalled = false

    class SingleColDragDelegate: SpreadsheetDelegate {
        var onMoveColumn: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestMoveColumn(column: Int) { onMoveColumn?() }
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = SingleColDragDelegate()
    d.onMoveColumn = { moveColumnCalled = true }
    panel.spreadsheetDelegate = d

    panel.simulateMouseDown(at: rowPoint(in: panel, column: 0, row: 0))
    panel.simulateMouseDragged(to: tabPoint(in: panel, index: 1))
    try expectTrue(moveColumnCalled)
    panel.dismiss()
}

// MARK: – MoveTabNav mode

test("up in move mode enters moveTabNav") {
    var s = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")], activeTab: 0,
        columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    apply(&s, .dataAction(.moveRow))
    try expect(s.mode, equals: .move)
    apply(&s, .keyDown(.up))
    try expect(s.mode, equals: .moveTabNav)
}

test("up in move mode without tabs stays in move") {
    var s = makeState(tabs: 0, selectedColumn: 0, selectedRow: 0)
    apply(&s, .dataAction(.moveRow))
    apply(&s, .keyDown(.up))
    try expect(s.mode, equals: .move)
}

test("left/right in moveTabNav navigates tabs") {
    var s = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1"), Tab(name: "T2")], activeTab: 0,
        columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .moveTabNav,
        moveOriginColumn: 0, moveOriginRow: 0, moveTargetColumn: 0
    )
    apply(&s, .keyDown(.right))
    try expect(s.activeTab, equals: 1)
    apply(&s, .keyDown(.left))
    try expect(s.activeTab, equals: 0)
}

test("moveTabNav wraps tabs") {
    var s = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")], activeTab: 1,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .moveTabNav,
        moveOriginColumn: 0, moveOriginRow: 0, moveTargetColumn: 0
    )
    apply(&s, .keyDown(.right))
    try expect(s.activeTab, equals: 0)
}

test("cancel in moveTabNav returns to browse") {
    var s = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")], activeTab: 1,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .moveTabNav,
        moveOriginColumn: 0, moveOriginRow: 0, moveTargetColumn: 0
    )
    apply(&s, .keyDown(.cancel))
    try expect(s.mode, equals: .browse)
}

// MARK: – Rename mode

test("rename in browse mode sets target to row") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"])])
    panel.apply(.dataAction(.rename))
    try expect(panel.state.mode, equals: .rename)
    try expect(panel.state.renameTarget, equals: .row(column: 0, row: 0))
    panel.dismiss()
}

test("rename with shift in browse targets columnHeader") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"])])
    panel.apply(.dataAction(.rename), modifiers: .shift)
    try expect(panel.state.mode, equals: .rename)
    try expect(panel.state.renameTarget, equals: .columnHeader(column: 0))
    panel.dismiss()
}

test("rename with cmd in browse targets tab") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    panel.apply(.dataAction(.rename), modifiers: .command)
    try expect(panel.state.mode, equals: .rename)
    try expect(panel.state.renameTarget, equals: .tab(index: 0))
    panel.dismiss()
}

test("close with shift+c on non-empty column is no-op") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])

    class CloseDelegate: SpreadsheetDelegate {
        var closeCalled = false
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddRow() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) { closeCalled = true }
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) { closeCalled = true }
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) { closeCalled = true }
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) {}
        func spreadsheetDidDescendFromMoveTabNav() {}
        func spreadsheetDidCancelMoveTabNav() {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = CloseDelegate()
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.close), modifiers: .shift)
    try expect(d.closeCalled, equals: false)
    panel.dismiss()
}

test("rename in browse mode with empty column sets target to columnHeader") {
    let (panel, _) = makePanel(columns: [("A", []), ("B", ["r1"])])
    panel.apply(.dataAction(.rename))
    try expect(panel.state.mode, equals: .rename)
    try expect(panel.state.renameTarget, equals: .columnHeader(column: 0))
    panel.dismiss()
}

test("rename in tabNav sets target to tab") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    panel.state.mode = .tabNav
    panel.apply(.dataAction(.rename))
    try expect(panel.state.mode, equals: .rename)
    try expect(panel.state.renameTarget, equals: .tab(index: 0))
    panel.dismiss()
}

test("dismiss during rename cancels rename") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"])])
    panel.apply(.dataAction(.rename))
    try expect(panel.state.mode, equals: .rename)
    try expect(panel.state.renameTarget, equals: .row(column: 0, row: 0))
    panel.dismiss()
    try expect(panel.state.mode, equals: .browse)
    try expect(panel.state.renameTarget, equals: nil)
}

// MARK: – Move mode: confirm (handled by panel, not reducer)

// confirm in move mode is a data action — tested in panel tests below

// MARK: – Mock data source

class MockDataSource: SpreadsheetDataSource {
    var columns: [(name: String, rows: [String])]
    init(_ columns: [(String, [String])]) { self.columns = columns }
    var columnCount: Int { columns.count }
    func columnName(_ column: Int) -> String { columns[column].name }
    func rowCount(in column: Int) -> Int { columns[column].rows.count }
    func rowLabel(column: Int, row: Int) -> String { columns[column].rows[row] }
    func rowIcon(column: Int, row: Int) -> NSImage? { nil }
}

func renderView(
    columns: [(String, [String])],
    selectedColumn: Int = 0,
    selectedRow: Int = 0,
    mode: Mode = .browse
) -> SpreadsheetView {
    let ds = MockDataSource(columns)
    let state = SpreadsheetState(
        columns: columns.map { Column(name: $0.0, rowCount: $0.1.count) },
        selectedColumn: selectedColumn,
        selectedRow: selectedRow,
        mode: mode
    )
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    return view
}

func expectNotNil(_ v: Any?, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard v != nil else { throw TestFailure("expected non-nil \(msg) (\(file):\(line))") }
}

func expectNil(_ v: Any?, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard v == nil else { throw TestFailure("expected nil \(msg) (\(file):\(line))") }
}

// MARK: – Renderer: structure

test("renders correct number of columns") {
    let view = renderView(columns: [("A", ["r1"]), ("B", ["r1", "r2"]), ("C", ["r1"])])
    try expect(view.findAllViews(id: "column-0").count, equals: 1)
    try expect(view.findAllViews(id: "column-1").count, equals: 1)
    try expect(view.findAllViews(id: "column-2").count, equals: 1)
    try expectNil(view.findView(id: "column-3"))
}

test("renders correct number of rows per column") {
    let view = renderView(columns: [("A", ["r1", "r2", "r3"]), ("B", ["r1"])])
    try expectNotNil(view.findView(id: "row-0-0"))
    try expectNotNil(view.findView(id: "row-0-1"))
    try expectNotNil(view.findView(id: "row-0-2"))
    try expectNil(view.findView(id: "row-0-3"))
    try expectNotNil(view.findView(id: "row-1-0"))
    try expectNil(view.findView(id: "row-1-1"))
}

// MARK: – Renderer: header text

test("header shows column name") {
    let view = renderView(columns: [("Code", ["x"]), ("Browse", ["y"])])
    try expect(view.findLabel(id: "header-0")?.stringValue, equals: "Code")
    try expect(view.findLabel(id: "header-1")?.stringValue, equals: "Browse")
}

// MARK: – Renderer: row labels

test("row shows correct label") {
    let view = renderView(columns: [("A", ["Terminal", "Xcode"])])
    try expect(view.findLabel(id: "label-0-0")?.stringValue, equals: "Terminal")
    try expect(view.findLabel(id: "label-0-1")?.stringValue, equals: "Xcode")
}

// MARK: – Renderer: selection

// MARK: – Renderer: focus/path highlight system

test("focus: row selection only in browse mode with non-empty column") {
    for mode in Mode.allCases {
        let view = renderView(columns: [("A", ["r1", "r2"])], selectedColumn: 0, selectedRow: 0, mode: mode)
        let hasSelection = view.findView(id: "row-0-0")?.findView(id: "selection") != nil
        let shouldShow = mode == .browse || mode == .rename
        try expect(hasSelection, equals: shouldShow)
    }
}

test("focus: empty column header gets focus in browse mode") {
    let view = renderView(columns: [("A", []), ("B", ["r1"])], selectedColumn: 0, selectedRow: 0, mode: .browse)
    let headerBg = view.findView(id: "header-bg-0")
    try expectNotNil(headerBg?.layer?.backgroundColor, "empty column header has focus")
}

test("path: header is path-highlighted in browse mode (non-empty column)") {
    let view = renderView(columns: [("A", ["r1"]), ("B", ["r1"])], selectedColumn: 0, selectedRow: 0, mode: .browse)
    let hasBg = view.findView(id: "header-bg-0")?.layer?.backgroundColor != nil
    try expectTrue(hasBg)
}

test("path: no header highlight in tabNav mode") {
    let view = renderView(columns: [("A", ["r1"])], selectedColumn: 0, selectedRow: 0, mode: .tabNav)
    let hasBg = view.findView(id: "header-bg-0")?.layer?.backgroundColor != nil
    try expect(hasBg, equals: false)
}

test("path: header highlight on target column in move mode") {
    for mode in Mode.allCases {
        let state = SpreadsheetState(
            columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
            selectedColumn: 0, selectedRow: 0, mode: mode,
            moveOriginColumn: 0, moveOriginRow: 0, moveTargetColumn: 1
        )
        let ds = MockDataSource([("A", ["r1", "r2"]), ("B", ["r1"])])
        let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        view.render(state: state, dataSource: ds)
        let targetHasBg = view.findView(id: "header-bg-1")?.layer?.backgroundColor != nil
        if mode == .move {
            try expectTrue(targetHasBg)
        }
    }
}

test("path: active tab is path-highlighted in browse mode") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")], activeTab: 0,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let ds = MockDataSource([("A", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    let tab0 = view.findView(id: "tab-0")
    let tab1 = view.findView(id: "tab-1")
    try expectNotNil(tab0?.layer?.backgroundColor, "active tab path-highlighted")
    try expectNil(tab1?.layer?.backgroundColor, "inactive tab not highlighted")
}

test("focus: active tab gets focus color in tabNav mode") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")], activeTab: 0,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .tabNav
    )
    let ds = MockDataSource([("A", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    let tab0 = view.findView(id: "tab-0")
    try expectNotNil(tab0?.layer?.backgroundColor, "active tab has focus")
}

test("path: no tab highlight in tabNav mode for inactive tabs") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")], activeTab: 0,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .tabNav
    )
    let ds = MockDataSource([("A", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    let tab1 = view.findView(id: "tab-1")
    try expectNil(tab1?.layer?.backgroundColor, "inactive tab not highlighted in tabNav")
}

test("phantom only in move mode") {
    for mode in Mode.allCases {
        let state = SpreadsheetState(
            columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
            selectedColumn: 0, selectedRow: 0, mode: mode,
            moveOriginColumn: 0, moveOriginRow: 0, moveTargetColumn: 0
        )
        let ds = MockDataSource([("A", ["r1", "r2"]), ("B", ["r1"])])
        let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        view.render(state: state, dataSource: ds)
        let hasPhantom = view.findView(id: "phantom") != nil
        try expect(hasPhantom, equals: mode == .move)
    }
}

// MARK: – Renderer: move mode specifics

test("origin row is hidden during move mode") {
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
        selectedColumn: 0, selectedRow: 1, mode: .move,
        moveOriginColumn: 0, moveOriginRow: 1, moveTargetColumn: 1
    )
    let ds = MockDataSource([("A", ["r1", "r2"]), ("B", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    try expectNotNil(view.findView(id: "row-0-0"), "row 0 still visible")
    try expectNil(view.findView(id: "row-0-1"), "origin row hidden")
}

test("phantom row appears at row 0 of target column") {
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
        selectedColumn: 0, selectedRow: 1, mode: .move,
        moveOriginColumn: 0, moveOriginRow: 1, moveTargetColumn: 1
    )
    let ds = MockDataSource([("A", ["r1", "r2"]), ("B", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    try expectNotNil(view.findView(id: "phantom"), "phantom view")
}

test("phantom pushes existing rows down") {
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .move,
        moveOriginColumn: 0, moveOriginRow: 0, moveTargetColumn: 1
    )
    let ds = MockDataSource([("A", ["r1", "r2"]), ("B", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)

    let phantom = view.findView(id: "phantom")!
    let row = view.findView(id: "row-1-0")!
    try expectTrue(phantom.frame.origin.y < row.frame.origin.y)
    try expectTrue(abs(row.frame.origin.y - phantom.frame.origin.y - view.rowHeight) < 1)
}

test("origin row is hidden during moveTabNav when carrying a window") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")], activeTab: 0,
        columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .moveTabNav,
        moveOriginColumn: 0, moveOriginRow: 0, moveTargetColumn: 0,
        movingColumn: false
    )
    let ds = MockDataSource([("A", ["r1", "r2"]), ("B", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    try expectNil(view.findView(id: "row-0-0"), "origin row should be hidden in moveTabNav")
    try expectNotNil(view.findView(id: "row-0-1"), "other rows still visible")
}

test("origin row is NOT hidden during moveTabNav when moving a workspace") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")], activeTab: 0,
        columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .moveTabNav,
        moveOriginColumn: 0, moveOriginRow: 0, moveTargetColumn: 0,
        movingColumn: true
    )
    let ds = MockDataSource([("A", ["r1", "r2"]), ("B", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    try expectNotNil(view.findView(id: "row-0-0"), "rows visible when moving workspace")
}

test("selection highlight has correct style") {
    let view = renderView(columns: [("A", ["r1"])], selectedColumn: 0, selectedRow: 0)
    let sel = view.findView(id: "row-0-0")?.findView(id: "selection")
    try expectNotNil(sel)
    try expect(sel?.layer?.cornerRadius, equals: 6)
    try expect(sel?.layer?.backgroundColor, equals: NSColor.controlAccentColor.cgColor)
}


// MARK: – Renderer: text colors

test("selected row label is white") {
    let view = renderView(columns: [("A", ["r1", "r2"])], selectedRow: 0)
    try expect(view.findLabel(id: "label-0-0")?.textColor, equals: .white)
    try expect(view.findLabel(id: "label-0-1")?.textColor, equals: .labelColor)
}

test("selected column header text is white") {
    let view = renderView(columns: [("A", ["r1"]), ("B", ["r1"])], selectedColumn: 0)
    try expect(view.findLabel(id: "header-0")?.textColor, equals: .white)
    try expect(view.findLabel(id: "header-1")?.textColor, equals: .secondaryLabelColor)
}

// MARK: – Renderer: scroll view

test("each column has a scroll view containing rows") {
    let view = renderView(columns: [("A", ["r1", "r2"])])
    let scrollView = view.findView(id: "column-0")?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
    try expectNotNil(scrollView, "scroll view in column")
    try expectNotNil(scrollView?.documentView?.findView(id: "row-0-0"), "row inside scroll view")
    try expectNotNil(scrollView?.documentView?.findView(id: "row-0-1"), "row inside scroll view")
}

test("header is outside vertical scroll view") {
    let view = renderView(columns: [("A", ["r1"])])
    let col = view.findView(id: "column-0")!
    _ = col.findView(id: "header-0")!
    let verticalScroll = col.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
    try expectNotNil(verticalScroll, "column has vertical scroll view")
    try expectNil(verticalScroll?.documentView?.findView(id: "header-0"), "header not inside vertical scroll")
}

test("scroll view document is taller than visible area when rows exceed max") {
    let rows = (0..<15).map { "r\($0)" }
    let ds = MockDataSource([("A", rows)])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 15)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let maxVisibleRows = 10
    let view = SpreadsheetView(frame: .zero)
    let h = view.headerHeight + view.hairlineH + view.rowHeight * CGFloat(maxVisibleRows)
    view.frame = NSRect(x: 0, y: 0, width: view.columnWidth, height: h)
    view.render(state: state, dataSource: ds)

    let scrollView = view.findView(id: "column-0")?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
    try expectNotNil(scrollView, "scroll view")
    let docHeight = scrollView!.documentView!.frame.height
    let visibleHeight = scrollView!.frame.height
    try expectTrue(docHeight > visibleHeight)
}

test("scroll view document fits visible area when rows within max") {
    let ds = MockDataSource([("A", ["r1", "r2", "r3"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 3)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let view = SpreadsheetView(frame: .zero)
    let h = view.headerHeight + view.hairlineH + view.rowHeight * CGFloat(3)
    view.frame = NSRect(x: 0, y: 0, width: view.columnWidth, height: h)
    view.render(state: state, dataSource: ds)

    let scrollView = view.findView(id: "column-0")?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
    try expectNotNil(scrollView, "scroll view")
    let docHeight = scrollView!.documentView!.frame.height
    let visibleHeight = scrollView!.frame.height
    try expectTrue(abs(docHeight - visibleHeight) < 1)
}

test("scroll view has vertical scroller enabled") {
    let view = renderView(columns: [("A", ["r1"])])
    let scrollView = view.findView(id: "column-0")?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
    try expectNotNil(scrollView, "scroll view")
    try expectTrue(scrollView!.hasVerticalScroller)
}

// MARK: – Renderer: tab strip

test("tab strip renders tabs") {
    let ds = MockDataSource([("A", ["r1"])])
    let state = SpreadsheetState(
        tabs: [Tab(name: "Context1"), Tab(name: "Context2")],
        activeTab: 0,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    try expectNotNil(view.findView(id: "tab-0"), "tab-0 exists")
    try expectNotNil(view.findView(id: "tab-1"), "tab-1 exists")
    try expectNil(view.findView(id: "tab-2"), "no tab-2")
    try expect(view.findLabel(id: "tab-label-0")?.stringValue, equals: "Context1")
    try expect(view.findLabel(id: "tab-label-1")?.stringValue, equals: "Context2")
}

test("active tab has accent background") {
    let ds = MockDataSource([("A", ["r1"])])
    let state = SpreadsheetState(
        tabs: [Tab(name: "Tab0"), Tab(name: "Tab1")],
        activeTab: 0,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)
    let tab0 = view.findView(id: "tab-0")
    let tab1 = view.findView(id: "tab-1")
    try expectNotNil(tab0?.layer?.backgroundColor, "active tab has background")
    try expectNil(tab1?.layer?.backgroundColor, "inactive tab has no background")
}

test("no tab strip when no tabs") {
    let view = renderView(columns: [("A", ["r1"])])
    try expectNil(view.findView(id: "tab-0"), "no tab views when tabs array is empty")
}

// MARK: – Renderer: smart tab sizing

test("tabs have different widths based on label text") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "A"), Tab(name: "Long Context Name")],
        activeTab: 0,
        columns: [Column(name: "X", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let ds = MockDataSource([("X", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)

    let tab0 = view.findView(id: "tab-0")!
    let tab1 = view.findView(id: "tab-1")!
    try expectTrue(tab1.frame.width > tab0.frame.width)
}

test("short tab has minimum width") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "A")],
        activeTab: 0,
        columns: [Column(name: "X", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let ds = MockDataSource([("X", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)

    let tab0 = view.findView(id: "tab-0")!
    try expectTrue(tab0.frame.width >= 52)
}

test("wide tabs shrink to fit available space") {
    var tabs: [Tab] = []
    for i in 0..<5 { tabs.append(Tab(name: "Very Long Context Name \(i)")) }
    let state = SpreadsheetState(
        tabs: tabs, activeTab: 0,
        columns: [Column(name: "X", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let ds = MockDataSource([("X", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)

    let tab0 = view.findView(id: "tab-0")!
    let tab4 = view.findView(id: "tab-4")!
    // All equal-length tabs should shrink to the same width
    try expect(tab0.frame.width, equals: tab4.frame.width)
    // Should be narrower than natural width
    let naturalWidth = ("Very Long Context Name 0" as NSString)
        .size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width + 20
    try expectTrue(tab0.frame.width < naturalWidth)
}

test("shrink preserves short tabs when only long tabs need shrinking") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "A"), Tab(name: "Very Long Context Name Here")],
        activeTab: 0,
        columns: [Column(name: "X", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let ds = MockDataSource([("X", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
    view.render(state: state, dataSource: ds)

    let tab0 = view.findView(id: "tab-0")!
    let tab1 = view.findView(id: "tab-1")!
    // Short tab should keep its minimum width
    try expectTrue(tab0.frame.width >= 52)
    // Long tab should be wider or equal (both may be at min if very narrow panel)
    try expectTrue(tab1.frame.width >= tab0.frame.width)
}

// MARK: – Renderer: horizontal scroll

test("columns are inside a horizontal scroll view") {
    let ds = MockDataSource([("A", ["r1"]), ("B", ["r1"]), ("C", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1), Column(name: "B", rowCount: 1), Column(name: "C", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let layout = LayoutConfig()

    let view = SpreadsheetView(frame: .zero, layout: layout)
    let w = view.columnWidth * 2
    let h = view.headerHeight + view.hairlineH + view.rowHeight
    view.frame = NSRect(x: 0, y: 0, width: w, height: h)
    view.render(state: state, dataSource: ds)

    let hScroll = view.subviews.first(where: { ($0 as? NSScrollView)?.hasHorizontalScroller == true }) as? NSScrollView
    try expectNotNil(hScroll, "horizontal scroll view")
    try expectNotNil(hScroll?.documentView?.findView(id: "column-0"), "column inside horizontal scroll")
    try expectNotNil(hScroll?.documentView?.findView(id: "column-2"), "third column inside scroll")
}

test("horizontal scroll document is wider than visible area when columns exceed max") {
    let ds = MockDataSource([("A", ["r1"]), ("B", ["r1"]), ("C", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1), Column(name: "B", rowCount: 1), Column(name: "C", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let layout = LayoutConfig()

    let view = SpreadsheetView(frame: .zero, layout: layout)
    let w = view.columnWidth * 2
    let h = view.headerHeight + view.hairlineH + view.rowHeight
    view.frame = NSRect(x: 0, y: 0, width: w, height: h)
    view.render(state: state, dataSource: ds)

    let hScroll = view.subviews.first(where: { ($0 as? NSScrollView)?.hasHorizontalScroller == true }) as? NSScrollView
    try expectNotNil(hScroll, "horizontal scroll view")
    let docWidth = hScroll!.documentView!.frame.width
    let visibleWidth = hScroll!.frame.width
    try expectTrue(docWidth > visibleWidth)
}

test("tab strip has its own scroll view") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1"), Tab(name: "T2")],
        activeTab: 0,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let ds = MockDataSource([("A", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)

    // Tab views should be inside a scroll view
    let tabView = view.findView(id: "tab-0")
    var parent = tabView?.superview
    var foundScroll = false
    while let p = parent {
        if p is NSScrollView { foundScroll = true; break }
        parent = p.superview
    }
    try expectTrue(foundScroll)
}

test("tab chevrons hidden when all tabs fit") {
    let state = SpreadsheetState(
        tabs: [Tab(name: "T0"), Tab(name: "T1")],
        activeTab: 0,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let ds = MockDataSource([("A", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)

    let left = view.findView(id: "tab-chevron-left")
    let right = view.findView(id: "tab-chevron-right")
    try expectTrue(left == nil || left!.isHidden)
    try expectTrue(right == nil || right!.isHidden)
}

test("tab right chevron visible when tabs overflow") {
    var tabs: [Tab] = []
    for i in 0..<20 { tabs.append(Tab(name: "Tab \(i)")) }
    let state = SpreadsheetState(
        tabs: tabs,
        activeTab: 0,
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let ds = MockDataSource([("A", ["r1"])])
    let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    view.render(state: state, dataSource: ds)

    let right = view.findView(id: "tab-chevron-right")
    try expectNotNil(right, "right chevron exists")
    try expectTrue(!right!.isHidden)
}

test("scroll-to-column reveals selected column when offscreen right") {
    let ds = MockDataSource([("A", ["r1"]), ("B", ["r1"]), ("C", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1), Column(name: "B", rowCount: 1), Column(name: "C", rowCount: 1)],
        selectedColumn: 2, selectedRow: 0, mode: .browse
    )
    let layout = LayoutConfig()

    let view = SpreadsheetView(frame: .zero, layout: layout)
    let w = view.columnWidth * 2
    let h = view.headerHeight + view.hairlineH + view.rowHeight
    view.frame = NSRect(x: 0, y: 0, width: w, height: h)
    view.render(state: state, dataSource: ds)

    let hScroll = view.subviews.first(where: { ($0 as? NSScrollView)?.hasHorizontalScroller == true }) as? NSScrollView
    let scrollX = hScroll!.contentView.bounds.origin.x
    let colRight = view.columnWidth * 3
    try expectTrue(scrollX > 0)
    try expectTrue(scrollX + w >= colRight)
}

test("scroll-to-column does not scroll when selected column is visible") {
    let ds = MockDataSource([("A", ["r1"]), ("B", ["r1"]), ("C", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1), Column(name: "B", rowCount: 1), Column(name: "C", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let layout = LayoutConfig()

    let view = SpreadsheetView(frame: .zero, layout: layout)
    let w = view.columnWidth * 2
    let h = view.headerHeight + view.hairlineH + view.rowHeight
    view.frame = NSRect(x: 0, y: 0, width: w, height: h)
    view.render(state: state, dataSource: ds)

    let hScroll = view.subviews.first(where: { ($0 as? NSScrollView)?.hasHorizontalScroller == true }) as? NSScrollView
    let scrollX = hScroll!.contentView.bounds.origin.x
    try expect(scrollX, equals: 0)
}

test("scroll-to-column in move mode follows target column") {
    let ds = MockDataSource([("A", ["r1"]), ("B", ["r1"]), ("C", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1), Column(name: "B", rowCount: 1), Column(name: "C", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .move,
        moveOriginColumn: 0, moveOriginRow: 0, moveTargetColumn: 2
    )
    let layout = LayoutConfig()

    let view = SpreadsheetView(frame: .zero, layout: layout)
    let w = view.columnWidth * 2
    let h = view.headerHeight + view.hairlineH + view.rowHeight
    view.frame = NSRect(x: 0, y: 0, width: w, height: h)
    view.render(state: state, dataSource: ds)

    let hScroll = view.subviews.first(where: { ($0 as? NSScrollView)?.hasHorizontalScroller == true }) as? NSScrollView
    let scrollX = hScroll!.contentView.bounds.origin.x
    try expectTrue(scrollX > 0)
}

// MARK: – Renderer: layout

test("columns are positioned side by side") {
    let view = renderView(columns: [("A", ["r1"]), ("B", ["r1"])])
    let col0 = view.findView(id: "column-0")!
    let col1 = view.findView(id: "column-1")!
    try expect(col0.frame.origin.x, equals: 0)
    try expect(col1.frame.origin.x, equals: view.columnWidth)
    try expect(col0.frame.width, equals: view.columnWidth)
    try expect(col1.frame.width, equals: view.columnWidth)
}

test("rows are stacked below header") {
    let view = renderView(columns: [("A", ["r1", "r2"])])
    let row0 = view.findView(id: "row-0-0")!
    let row1 = view.findView(id: "row-0-1")!
    try expect(row0.frame.height, equals: view.rowHeight)
    try expectTrue(row0.frame.origin.y < row1.frame.origin.y)
}

test("row label fits inside row at various screen sizes") {
    let screenHeights: [CGFloat] = [900, 1080, 1200, 1440, 1600]
    for screenH in screenHeights {
        let layout = LayoutConfig.forScreen(screenH)
        let ds = MockDataSource([("A", ["row1"])])
        let state = SpreadsheetState(
            columns: [Column(name: "A", rowCount: 1)],
            selectedColumn: 0, selectedRow: 0, mode: .browse
        )
        let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        view.layout = layout
        view.render(state: state, dataSource: ds)
        guard let label = view.findLabel(id: "label-0-0") else {
            throw TestFailure("label not found for screenH=\(screenH)")
        }
        let font = label.font!
        let lineH = ceil(font.ascender - font.descender + font.leading)
        guard label.frame.height >= lineH else {
            throw TestFailure("screenH=\(screenH): label height \(label.frame.height) < font line height \(lineH)")
        }
    }
}

test("header label fits inside header at various screen sizes") {
    let screenHeights: [CGFloat] = [900, 1080, 1200, 1440, 1600]
    for screenH in screenHeights {
        let layout = LayoutConfig.forScreen(screenH)
        let ds = MockDataSource([("Header", ["row1"])])
        let state = SpreadsheetState(
            columns: [Column(name: "Header", rowCount: 1)],
            selectedColumn: 0, selectedRow: 0, mode: .browse
        )
        let view = SpreadsheetView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        view.layout = layout
        view.render(state: state, dataSource: ds)
        guard let label = view.findLabel(id: "header-0") else {
            throw TestFailure("header not found for screenH=\(screenH)")
        }
        let font = label.font!
        let lineH = ceil(font.ascender - font.descender + font.leading)
        guard label.frame.height >= lineH else {
            throw TestFailure("screenH=\(screenH): header height \(label.frame.height) < font line height \(lineH)")
        }
    }
}

// MARK: – Renderer: empty column

test("empty column renders header but no rows") {
    let view = renderView(columns: [("Empty", [])])
    try expectNotNil(view.findLabel(id: "header-0"))
    try expect(view.findLabel(id: "header-0")?.stringValue, equals: "Empty")
    try expectNil(view.findView(id: "row-0-0"))
}

// MARK: – Integration: panel + state + renderer

private var retainedDataSourceKey: UInt8 = 0

func makePanel(
    columns: [(String, [String])],
    selectedColumn: Int = 0,
    selectedRow: Int = 0
) -> (SpreadsheetPanel, MockDataSource) {
    let ds = MockDataSource(columns)
    let state = SpreadsheetState(
        columns: columns.map { Column(name: $0.0, rowCount: $0.1.count) },
        selectedColumn: selectedColumn,
        selectedRow: selectedRow,
        mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    objc_setAssociatedObject(panel, &retainedDataSourceKey, ds, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    panel.layoutForState()
    return (panel, ds)
}

test("panel: arrow down updates state and view") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2", "r3"])])
    try expect(panel.state.selectedRow, equals: 0)

    let sel0 = panel.spreadsheetView.findAllViews(id: "selection")
    try expect(sel0.count, equals: 1)

    panel.apply(.keyDown(.down))

    try expect(panel.state.selectedRow, equals: 1)
    try expectNil(panel.spreadsheetView.findView(id: "row-0-0")?.findView(id: "selection"))
    try expectNotNil(panel.spreadsheetView.findView(id: "row-0-1")?.findView(id: "selection"))
    panel.dismiss()
}

test("panel: arrow right moves to next column and re-renders") {
    let (panel, _) = makePanel(columns: [("A", ["r1"]), ("B", ["r1", "r2"])])
    try expect(panel.state.selectedColumn, equals: 0)

    panel.apply(.keyDown(.right))

    try expect(panel.state.selectedColumn, equals: 1)
    try expectNotNil(panel.spreadsheetView.findView(id: "header-bg-1")?.layer?.backgroundColor)
    try expectNil(panel.spreadsheetView.findView(id: "header-bg-0")?.layer?.backgroundColor)
    panel.dismiss()
}

test("panel: navigate down past last row enters tabNav, no selection highlight") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])

    panel.apply(.keyDown(.down))

    try expect(panel.state.mode, equals: .tabNav)
    try expectNil(panel.spreadsheetView.findView(id: "row-0-0")?.findView(id: "selection"))
    try expectNil(panel.spreadsheetView.findView(id: "header-bg-0")?.layer?.backgroundColor)
    panel.dismiss()
}

test("panel: full navigation sequence — down, right, up, tabNav, back") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"]), ("B", ["r1", "r2", "r3"])])

    panel.apply(.keyDown(.down))
    try expect(panel.state.selectedRow, equals: 1)
    try expect(panel.state.selectedColumn, equals: 0)

    panel.apply(.keyDown(.right))
    try expect(panel.state.selectedColumn, equals: 1)
    try expect(panel.state.selectedRow, equals: 0)

    panel.apply(.keyDown(.down))
    try expect(panel.state.selectedRow, equals: 1)

    panel.apply(.keyDown(.down))
    try expect(panel.state.selectedRow, equals: 2)

    panel.apply(.keyDown(.down))
    try expect(panel.state.mode, equals: .tabNav)

    panel.apply(.keyDown(.down))
    try expect(panel.state.mode, equals: .browse)
    try expect(panel.state.selectedRow, equals: 0)
    try expectNotNil(panel.spreadsheetView.findView(id: "row-1-0")?.findView(id: "selection"))

    panel.dismiss()
}

test("panel: mouse move updates state and view") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"]), ("B", ["r1"])])

    panel.apply(.mouseMove(column: 1, row: 0))

    try expect(panel.state.selectedColumn, equals: 1)
    try expect(panel.state.selectedRow, equals: 0)
    try expectNotNil(panel.spreadsheetView.findView(id: "row-1-0")?.findView(id: "selection"))
    try expectNil(panel.spreadsheetView.findView(id: "row-0-0")?.findView(id: "selection"))
    panel.dismiss()
}

test("panel: confirm fires delegate") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"])], selectedRow: 1)
    var confirmed: (Int, Int)? = nil

    class TestDelegate: SpreadsheetDelegate {
        var onConfirm: ((Int, Int) -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) { onConfirm?(column, row) }
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddRow() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) {}
        func spreadsheetDidDescendFromMoveTabNav() {}
        func spreadsheetDidCancelMoveTabNav() {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = TestDelegate()
    d.onConfirm = { confirmed = ($0, $1) }
    panel.spreadsheetDelegate = d

    panel.apply(.keyDown(.confirm))

    try expect(confirmed?.0, equals: 0)
    try expect(confirmed?.1, equals: 1)
    panel.dismiss()
}

// MARK: – Panel: canBecomeKey

test("panel can become key window") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    try expectTrue(panel.canBecomeKey)
    panel.dismiss()
}

// MARK: – Panel: positioning

test("show positions left edge at panelX margin when not centered") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"])])
    var layout = LayoutConfig()
    layout.centered = false
    layout.panelX = 0.1
    guard let screen = NSScreen.main else { return }

    panel.show(on: screen, layout: layout)

    let sf = screen.visibleFrame
    let expectedX = sf.origin.x + sf.width * 0.1
    try expectTrue(abs(panel.frame.origin.x - expectedX) < 1)
    panel.dismiss()
}

test("show centers panel when centered = true") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"])])
    var layout = LayoutConfig()
    layout.centered = true
    layout.panelX = 0.1
    guard let screen = NSScreen.main else { return }

    panel.show(on: screen, layout: layout)

    let sf = screen.visibleFrame
    let marginPx = sf.width * 0.1
    let availableWidth = sf.width - marginPx * 2
    let expectedX = sf.origin.x + marginPx + (availableWidth - panel.frame.width) / 2
    try expectTrue(abs(panel.frame.origin.x - expectedX) < 1)
    panel.dismiss()
}

test("show centers using maxColumns not active column count") {
    let (panel2, _) = makePanel(columns: [("A", ["r1"]), ("B", ["r1"])])
    let (panel4, _) = makePanel(columns: [("A", ["r1"]), ("B", ["r1"]), ("C", ["r1"]), ("D", ["r1"])])
    var layout = LayoutConfig()
    layout.centered = true
    layout.panelX = 0.1
    guard let screen = NSScreen.main else { return }

    panel2.show(on: screen, layout: layout, maxColumns: 4)
    panel4.show(on: screen, layout: layout, maxColumns: 4)

    try expectTrue(abs(panel2.frame.origin.x - panel4.frame.origin.x) < 1)
    try expectTrue(panel2.frame.width < panel4.frame.width)
    panel2.dismiss()
    panel4.dismiss()
}

test("relayout changes width on column count change") {
    let (panel, ds) = makePanel(columns: [("A", ["r1"]), ("B", ["r1"])])
    var layout = LayoutConfig()
    layout.centered = false
    layout.panelX = 0.1
    guard let screen = NSScreen.main else { return }
    panel.show(on: screen, layout: layout)
    let originalWidth = panel.frame.width

    ds.columns = [("A", ["r1"])]
    panel.refresh()
    panel.relayout()

    try expectTrue(panel.frame.width < originalWidth)
    panel.dismiss()
}

test("relayout uses data source not stale state") {
    let (panel, ds) = makePanel(columns: [("A", ["r1"])])
    var layout = LayoutConfig()
    layout.centered = false
    layout.panelX = 0.1
    guard let screen = NSScreen.main else { return }
    panel.show(on: screen, layout: layout)
    let oneColWidth = panel.frame.width

    // Change data source WITHOUT refreshing state — simulates setColumns before refresh
    ds.columns = [("A", ["r1"]), ("B", ["r1"]), ("C", ["r1"])]
    panel.relayout()

    try expectTrue(panel.frame.width > oneColWidth)
    panel.dismiss()
}

test("relayout preserves top edge position") {
    let (panel, ds) = makePanel(columns: [("A", ["r1"]), ("B", ["r1"])])
    var layout = LayoutConfig()
    layout.centered = false
    layout.panelX = 0.1
    guard let screen = NSScreen.main else { return }
    panel.show(on: screen, layout: layout)
    let originalTop = panel.frame.origin.y + panel.frame.height

    ds.columns = [("A", ["r1"])]
    panel.refresh()
    panel.relayout()

    let newTop = panel.frame.origin.y + panel.frame.height
    try expectTrue(abs(newTop - originalTop) < 1)
    panel.dismiss()
}

test("panel does not extend below screen") {
    let cols = (0..<1).map { _ in ("A", (0..<50).map { "r\($0)" }) }
    let (panel, _) = makePanel(columns: cols)
    var layout = LayoutConfig()
    layout.maxVisibleRows = 50
    layout.panelY = 0.8
    guard let screen = NSScreen.main else { return }

    panel.show(on: screen, layout: layout)

    let screenBottom = screen.frame.origin.y
    try expectTrue(panel.frame.origin.y >= screenBottom)
    panel.dismiss()
}

// MARK: – Panel: refresh

test("refresh re-derives state from data source") {
    let ds = MockDataSource([("A", ["r1", "r2"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 2)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    panel.layoutForState()

    // Simulate data source change: add a column
    ds.columns = [("A", ["r1", "r2"]), ("B", ["r1"])]

    panel.refresh()

    try expect(panel.state.columns.count, equals: 2)
    try expect(panel.state.columns[0].name, equals: "A")
    try expect(panel.state.columns[0].rowCount, equals: 2)
    try expect(panel.state.columns[1].name, equals: "B")
    try expect(panel.state.columns[1].rowCount, equals: 1)
    panel.dismiss()
}

test("refresh clamps selection when column removed") {
    let ds = MockDataSource([("A", ["r1"]), ("B", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1), Column(name: "B", rowCount: 1)],
        selectedColumn: 1, selectedRow: 0, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    panel.layoutForState()

    // Remove column B
    ds.columns = [("A", ["r1"])]
    panel.refresh()

    try expect(panel.state.columns.count, equals: 1)
    try expect(panel.state.selectedColumn, equals: 0)
    panel.dismiss()
}

test("refresh clamps selection when row removed") {
    let ds = MockDataSource([("A", ["r1", "r2", "r3"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 3)],
        selectedColumn: 0, selectedRow: 2, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    panel.layoutForState()

    // Remove rows, only 1 left
    ds.columns = [("A", ["r1"])]
    panel.refresh()

    try expect(panel.state.columns[0].rowCount, equals: 1)
    try expect(panel.state.selectedRow, equals: 0)
    panel.dismiss()
}

test("refresh preserves selection when still valid") {
    let ds = MockDataSource([("A", ["r1", "r2"]), ("B", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
        selectedColumn: 1, selectedRow: 0, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    panel.layoutForState()

    // Add a row to B — selection still valid
    ds.columns = [("A", ["r1", "r2"]), ("B", ["r1", "r2"])]
    panel.refresh()

    try expect(panel.state.selectedColumn, equals: 1)
    try expect(panel.state.selectedRow, equals: 0)
    panel.dismiss()
}

test("refresh preserves move state") {
    let ds = MockDataSource([("A", ["r1", "r2"]), ("B", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 2), Column(name: "B", rowCount: 1)],
        selectedColumn: 0, selectedRow: 1, mode: .move,
        moveOriginColumn: 0, moveOriginRow: 1, moveTargetColumn: 1
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    panel.layoutForState()

    panel.refresh()

    try expect(panel.state.mode, equals: .move)
    try expect(panel.state.moveOriginColumn, equals: 0)
    try expect(panel.state.moveOriginRow, equals: 1)
    try expect(panel.state.moveTargetColumn, equals: 1)
    panel.dismiss()
}

test("refresh does not change panel size") {
    let ds = MockDataSource([("A", ["r1"]), ("B", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1), Column(name: "B", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    guard let screen = NSScreen.main else { return }
    panel.show(on: screen)
    let originalWidth = panel.frame.width
    let originalHeight = panel.frame.height

    ds.columns = [("A", ["r1"]), ("B", ["r1"]), ("C", ["r1"])]
    panel.refresh()

    try expect(panel.frame.width, equals: originalWidth)
    try expect(panel.frame.height, equals: originalHeight)
    panel.dismiss()
}

// MARK: – Panel: data action delegate calls

test("panel: addColumn plain calls addRow delegate") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    var addRowCalled = false

    class DataDelegate: SpreadsheetDelegate {
        var onAddRow: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddRow() { onAddRow?() }
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = DataDelegate()
    d.onAddRow = { addRowCalled = true }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.addColumn))

    try expectTrue(addRowCalled)
    panel.dismiss()
}

test("panel: addColumn with shift calls addColumn delegate") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    var addColumnCalled = false

    class DataDelegate: SpreadsheetDelegate {
        var onAddColumn: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddColumn() { onAddColumn?() }
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = DataDelegate()
    d.onAddColumn = { addColumnCalled = true }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.addColumn), modifiers: .shift)

    try expectTrue(addColumnCalled)
    panel.dismiss()
}

test("panel: close on empty column calls deleteColumn delegate") {
    let (panel, _) = makePanel(columns: [("A", []), ("B", ["r1"])], selectedColumn: 0)
    var deletedColumn: Int? = nil

    class DataDelegate: SpreadsheetDelegate {
        var onDelete: ((Int) -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddRow() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) { onDelete?(column) }
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) {}
        func spreadsheetDidDescendFromMoveTabNav() {}
        func spreadsheetDidCancelMoveTabNav() {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = DataDelegate()
    d.onDelete = { deletedColumn = $0 }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.close))

    try expect(deletedColumn, equals: 0)
    panel.dismiss()
}

test("panel: moveRow enters move mode") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"]), ("B", ["r1"])], selectedColumn: 0, selectedRow: 1)
    panel.apply(.dataAction(.moveRow))
    try expect(panel.state.mode, equals: .move)
    try expect(panel.state.moveOriginColumn, equals: 0)
    try expect(panel.state.moveOriginRow, equals: 1)
    panel.dismiss()
}

test("panel: confirm in move mode calls delegate with move indices") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"]), ("B", ["r1"])], selectedColumn: 0, selectedRow: 1)
    var moved: (Int, Int, Int)? = nil

    class MoveDelegate: SpreadsheetDelegate {
        var onMove: ((Int, Int, Int) -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddRow() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) { onMove?(column, row, toColumn) }
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) {}
        func spreadsheetDidDescendFromMoveTabNav() {}
        func spreadsheetDidCancelMoveTabNav() {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = MoveDelegate()
    d.onMove = { moved = ($0, $1, $2) }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.moveRow))
    panel.apply(.keyDown(.right))
    panel.apply(.keyDown(.confirm))

    try expect(moved?.0, equals: 0)
    try expect(moved?.1, equals: 1)
    try expect(moved?.2, equals: 1)
    try expect(panel.state.mode, equals: .browse)
    panel.dismiss()
}

test("panel: cancel in move mode does not call delegate") {
    let (panel, _) = makePanel(columns: [("A", ["r1"]), ("B", ["r1"])])
    var moveCalled = false

    class MoveDelegate: SpreadsheetDelegate {
        var onMove: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddRow() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) { onMove?() }
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) {}
        func spreadsheetDidDescendFromMoveTabNav() {}
        func spreadsheetDidCancelMoveTabNav() {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = MoveDelegate()
    d.onMove = { moveCalled = true }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.moveRow))
    panel.apply(.keyDown(.right))
    panel.apply(.keyDown(.cancel))

    try expect(moveCalled, equals: false)
    try expect(panel.state.mode, equals: .browse)
    panel.dismiss()
}

// MARK: – Panel: tabNav data actions

test("addColumn in tabNav mode emits addTab") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    panel.state.tabs = [Tab(name: "T0"), Tab(name: "T1")]
    panel.state.activeTab = 0
    panel.state.mode = .tabNav
    var addTabCalled = false
    var addColumnCalled = false

    class TabNavDelegate: SpreadsheetDelegate {
        var onAddTab: (() -> Void)?
        var onAddColumn: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddColumn() { onAddColumn?() }
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() { onAddTab?() }
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) {}
        func spreadsheetDidDescendFromMoveTabNav() {}
        func spreadsheetDidCancelMoveTabNav() {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = TabNavDelegate()
    d.onAddTab = { addTabCalled = true }
    d.onAddColumn = { addColumnCalled = true }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.addColumn))

    try expectTrue(addTabCalled)
    try expect(addColumnCalled, equals: false)
    panel.dismiss()
}

test("close in tabNav mode emits deleteTab") {
    let (panel, _) = makePanel(columns: [("A", ["r1"])])
    panel.state.tabs = [Tab(name: "T0"), Tab(name: "T1")]
    panel.state.activeTab = 1
    panel.state.mode = .tabNav
    var deleteTabIndex: Int? = nil
    var deleteColumnCalled = false

    class TabNavDelegate: SpreadsheetDelegate {
        var onDeleteTab: ((Int) -> Void)?
        var onDeleteColumn: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddRow() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) { onDeleteColumn?() }
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) {}
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) { onDeleteTab?(index) }
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) {}
        func spreadsheetDidDescendFromMoveTabNav() {}
        func spreadsheetDidCancelMoveTabNav() {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = TabNavDelegate()
    d.onDeleteTab = { deleteTabIndex = $0 }
    d.onDeleteColumn = { deleteColumnCalled = true }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.close))

    try expect(deleteTabIndex, equals: 1)
    try expect(deleteColumnCalled, equals: false)
    panel.dismiss()
}

// MARK: – Panel: close (cascading)

test("panel: close in browse mode with rows calls closeRow delegate") {
    let (panel, _) = makePanel(columns: [("A", ["r1", "r2"])], selectedColumn: 0, selectedRow: 1)
    var closedColumn: Int? = nil
    var closedRow: Int? = nil

    class CloseDelegate: SpreadsheetDelegate {
        var onClose: ((Int, Int) -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddRow() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) {}
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) { onClose?(column, row) }
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) {}
        func spreadsheetDidDescendFromMoveTabNav() {}
        func spreadsheetDidCancelMoveTabNav() {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = CloseDelegate()
    d.onClose = { closedColumn = $0; closedRow = $1 }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.close))

    try expect(closedColumn, equals: 0)
    try expect(closedRow, equals: 1)
    panel.dismiss()
}

test("panel: close in move mode is ignored") {
    let (panel, _) = makePanel(columns: [("A", ["r1"]), ("B", ["r1"])])
    var closeCalled = false
    var deleteCalled = false

    class CloseDelegate: SpreadsheetDelegate {
        var onClose: (() -> Void)?
        var onDelete: (() -> Void)?
        func spreadsheetDidConfirm(column: Int, row: Int) {}
        func spreadsheetDidCancel() {}
        func spreadsheetDidRequestAddRow() {}
        func spreadsheetDidRequestAddColumn() {}
        func spreadsheetDidRequestDeleteColumn(column: Int) { onDelete?() }
        func spreadsheetDidRequestCloseRow(column: Int, row: Int) { onClose?() }
        func spreadsheetDidRequestMoveRow(column: Int, row: Int, toColumn: Int) {}
        func spreadsheetDidRequestAddTab() {}
        func spreadsheetDidRequestDeleteTab(index: Int) {}
        func spreadsheetDidSwitchTab(index: Int) {}
        func spreadsheetDidSwitchMoveTab(index: Int) {}
        func spreadsheetDidDescendFromMoveTabNav() {}
        func spreadsheetDidCancelMoveTabNav() {}
        func spreadsheetDidRequestRename(target: PanelTarget, value: String) {}
    }
    let d = CloseDelegate()
    d.onClose = { closeCalled = true }
    d.onDelete = { deleteCalled = true }
    panel.spreadsheetDelegate = d

    panel.apply(.dataAction(.moveRow))
    try expect(panel.state.mode, equals: .move)
    panel.apply(.dataAction(.close))

    try expect(closeCalled, equals: false)
    try expect(deleteCalled, equals: false)
    panel.dismiss()
}

test("KeyBindings action(for:) returns close action") {
    var keys = KeyBindings()
    keys.close = [KeyCombo(keyCode: 13, modifiers: [])]

    try expect(keys.action(forKeyCode: 13, modifiers: []) == .dataAction(.close), equals: true)
}

// MARK: – LayoutConfig: minVisibleRows

test("layoutForState with minVisibleRows: 1 row still fills min height") {
    let ds = MockDataSource([("A", ["r1"])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 1)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    // Set layout with minVisibleRows=3, maxVisibleRows=10
    panel.spreadsheetView.layout = LayoutConfig(minVisibleRows: 3, maxVisibleRows: 10)
    panel.layoutForState()

    // Panel height should use minVisibleRows=3 worth of row space, not just 1
    let expected = panel.spreadsheetView.headerHeight
        + panel.spreadsheetView.hairlineH
        + panel.spreadsheetView.rowHeight * 3
    try expect(panel.frame.height, equals: expected)
    panel.dismiss()
}

test("layoutForState with minVisibleRows: 0 rows still fills min height") {
    let ds = MockDataSource([("A", [])])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 0)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    panel.spreadsheetView.layout = LayoutConfig(minVisibleRows: 3, maxVisibleRows: 10)
    panel.layoutForState()

    let expected = panel.spreadsheetView.headerHeight
        + panel.spreadsheetView.hairlineH
        + panel.spreadsheetView.rowHeight * 3
    try expect(panel.frame.height, equals: expected)
    panel.dismiss()
}

test("layoutForState with maxVisibleRows: many rows capped at max height") {
    let rows = (0..<15).map { "r\($0)" }
    let ds = MockDataSource([("A", rows)])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 15)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    panel.spreadsheetView.layout = LayoutConfig(minVisibleRows: 3, maxVisibleRows: 5)
    panel.layoutForState()

    // Panel height should use maxVisibleRows=5 worth of row space, not 15
    let expected = panel.spreadsheetView.headerHeight
        + panel.spreadsheetView.hairlineH
        + panel.spreadsheetView.rowHeight * 5
    try expect(panel.frame.height, equals: expected)
    panel.dismiss()
}

test("layoutForState with rows between min and max uses actual count") {
    let rows = (0..<4).map { "r\($0)" }
    let ds = MockDataSource([("A", rows)])
    let state = SpreadsheetState(
        columns: [Column(name: "A", rowCount: 4)],
        selectedColumn: 0, selectedRow: 0, mode: .browse
    )
    let panel = SpreadsheetPanel(state: state)
    panel.dataSource = ds
    panel.spreadsheetView.layout = LayoutConfig(minVisibleRows: 3, maxVisibleRows: 10)
    panel.layoutForState()

    // 4 rows is between min=3 and max=10, so panel uses actual 4
    let expected = panel.spreadsheetView.headerHeight
        + panel.spreadsheetView.hairlineH
        + panel.spreadsheetView.rowHeight * 4
    try expect(panel.frame.height, equals: expected)
    panel.dismiss()
}

test("LayoutConfig default minVisibleRows is 1") {
    let layout = LayoutConfig()
    try expect(layout.minVisibleRows, equals: 1)
}

test("LayoutConfig default maxVisibleRows is 10") {
    let layout = LayoutConfig()
    try expect(layout.maxVisibleRows, equals: 10)
}

// MARK: – Results

if failCount > 0 {
    print("\n\(failCount) test(s) failed")
    exit(1)
} else {
    print("\nAll \(testCount) tests passed")
}
