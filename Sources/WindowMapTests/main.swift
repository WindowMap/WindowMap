import AppKit
import SpreadsheetKit
import WindowMapCore
import WindowMapApp

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

func expectNil(_ v: Any?, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard v == nil else { throw TestFailure("expected nil \(msg) (\(file):\(line))") }
}

func expectNotNil(_ v: Any?, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard v != nil else { throw TestFailure("expected non-nil \(msg) (\(file):\(line))") }
}

// MARK: – Helpers

let dummyAx = AXUIElementCreateSystemWide()
let currentApp = NSRunningApplication.current

func makeWindow(id: CGWindowID, title: String, app: NSRunningApplication = currentApp) -> Window {
    Window(id: id, app: app, title: title, axElement: dummyAx)
}

// MARK: – Data source mapping tests

test("column count matches workspace count") {
    let ds = WindowMapDataSource()
    let ws1 = Workspace(name: "Code")
    let ws2 = Workspace(name: "Browse")
    ds.columns = [
        (ws1, [makeWindow(id: 1, title: "Terminal")]),
        (ws2, [makeWindow(id: 2, title: "Safari")]),
    ]
    try expect(ds.columnCount, equals: 2)
}

test("column name is workspace name") {
    let ds = WindowMapDataSource()
    ds.columns = [
        (Workspace(name: "Code"), [makeWindow(id: 1, title: "Terminal")]),
        (Workspace(name: "Browse"), [makeWindow(id: 2, title: "Safari")]),
    ]
    try expect(ds.columnName(0), equals: "Code")
    try expect(ds.columnName(1), equals: "Browse")
}

test("row count matches windows in workspace") {
    let ds = WindowMapDataSource()
    ds.columns = [
        (Workspace(name: "Code"), [makeWindow(id: 1, title: "A"), makeWindow(id: 2, title: "B")]),
        (Workspace(name: "Browse"), [makeWindow(id: 3, title: "C")]),
    ]
    try expect(ds.rowCount(in: 0), equals: 2)
    try expect(ds.rowCount(in: 1), equals: 1)
}

test("row count for out-of-bounds column is 0") {
    let ds = WindowMapDataSource()
    ds.columns = [(Workspace(name: "Code"), [makeWindow(id: 1, title: "A")])]
    try expect(ds.rowCount(in: 1), equals: 0)
    try expect(ds.rowCount(in: 99), equals: 0)
}

test("row label is window title") {
    let ds = WindowMapDataSource()
    ds.columns = [
        (Workspace(name: "Code"), [makeWindow(id: 1, title: "Terminal — zsh"), makeWindow(id: 2, title: "Xcode — MyProject")]),
    ]
    try expect(ds.rowLabel(column: 0, row: 0), equals: "Terminal — zsh")
    try expect(ds.rowLabel(column: 0, row: 1), equals: "Xcode — MyProject")
}

test("row label for out-of-bounds is empty") {
    let ds = WindowMapDataSource()
    ds.columns = [(Workspace(name: "Code"), [makeWindow(id: 1, title: "A")])]
    try expect(ds.rowLabel(column: 0, row: 5), equals: "")
    try expect(ds.rowLabel(column: 1, row: 0), equals: "")
}

test("row icon is app icon") {
    let finder = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }!
    let ds = WindowMapDataSource()
    ds.columns = [(Workspace(name: "Code"), [makeWindow(id: 1, title: "Test", app: finder)])]
    let icon = ds.rowIcon(column: 0, row: 0)
    try expectNotNil(icon)
}

test("row icon for out-of-bounds is nil") {
    let ds = WindowMapDataSource()
    ds.columns = [(Workspace(name: "Code"), [makeWindow(id: 1, title: "A")])]
    try expect(ds.rowIcon(column: 0, row: 5) == nil, equals: true)
    try expect(ds.rowIcon(column: 1, row: 0) == nil, equals: true)
}

test("window lookup by column and row") {
    let ds = WindowMapDataSource()
    ds.columns = [
        (Workspace(name: "Code"), [makeWindow(id: 1, title: "Terminal")]),
        (Workspace(name: "Browse"), [makeWindow(id: 2, title: "Safari")]),
    ]
    try expect(ds.window(column: 0, row: 0)?.id, equals: 1)
    try expect(ds.window(column: 1, row: 0)?.id, equals: 2)
    try expect(ds.window(column: 2, row: 0) == nil, equals: true)
}

test("empty columns list") {
    let ds = WindowMapDataSource()
    ds.columns = []
    try expect(ds.columnCount, equals: 0)
}

// MARK: – Title normalization (from WindowMapCore)

test("title normalization trims whitespace and collapses newlines") {
    try expect(normalizeTitle("  hello  \n  world  "), equals: "hello world")
    try expect(normalizeTitle("single"), equals: "single")
    try expect(normalizeTitle("  \n  \n  "), equals: "")
    try expect(normalizeTitle("line1\nline2\nline3"), equals: "line1 line2 line3")
}

// MARK: – Toggle controller tests

test("toggle from hidden shows panel") {
    var callCount = 0
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        callCount += 1
        return [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1"),
                makeWindowWithBundle(id: 2, title: "Win2", bundleId: "com.test.2")]
    })
    guard let screen = NSScreen.main else { return }

    try expect(ctrl.panel.isVisible, equals: false)
    ctrl.toggle(on: screen)
    try expect(ctrl.panel.isVisible, equals: true)
    try expect(callCount, equals: 1)
    ctrl.panel.dismiss()
}

test("toggle from visible dismisses panel") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(ctrl.panel.isVisible, equals: true)

    ctrl.toggle(on: screen)
    try expect(ctrl.panel.isVisible, equals: false)
}

test("panel dismisses on resignKey notification") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)
    try expect(ctrl.panel.isVisible, equals: true)

    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: ctrl.panel)

    try expect(ctrl.panel.isVisible, equals: false)
}

test("panel does not dismiss on resignKey during suppress window") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    })
    ctrl.onCloseWindow = { _ in }
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    // Close a window — sets suppressResignUntil
    ctrl.spreadsheetDidRequestCloseRow(column: 0, row: 0)
    try expect(ctrl.panel.isVisible, equals: true)

    // Resign during suppress window should NOT dismiss
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: ctrl.panel)
    try expect(ctrl.panel.isVisible, equals: true)
    ctrl.panel.dismiss()
}

test("show populates data source via store workspace columns") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
         makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari")]
    })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)

    try expect(ctrl.dataSource.columnCount, equals: 1)
    try expect(ctrl.dataSource.columnName(0), equals: "Workspace0")
    try expect(ctrl.dataSource.rowCount(in: 0), equals: 2)
    try expect(ctrl.dataSource.rowLabel(column: 0, row: 0), equals: "Terminal")
    try expect(ctrl.dataSource.rowLabel(column: 0, row: 1), equals: "Safari")
    ctrl.panel.dismiss()
}

test("show builds state with workspace columns") {
    let store = makeTestStore()
    store.addWorkspace(name: "Code")
    // workspaces: [Code(0), Workspace0(1)]

    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "A", bundleId: "com.a"),
         makeWindowWithBundle(id: 2, title: "B", bundleId: "com.b")]
    })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)

    // All windows assigned to active workspace (Code at index 0)
    try expect(ctrl.panel.state.columns.count, equals: 2)
    try expect(ctrl.panel.state.selectedColumn, equals: 0)
    try expect(ctrl.panel.state.selectedRow, equals: 0)
    try expect(ctrl.panel.state.mode, equals: .browse)
    ctrl.panel.dismiss()
}

test("each show fetches fresh windows") {
    var callCount = 0
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        callCount += 1
        return (1...callCount).map { makeWindowWithBundle(id: CGWindowID($0), title: "Win\($0)", bundleId: "com.test.\($0)") }
    })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(ctrl.dataSource.rowCount(in: 0), equals: 1)
    ctrl.toggle(on: screen) // dismiss

    ctrl.toggle(on: screen) // show again
    try expect(ctrl.dataSource.rowCount(in: 0), equals: 2)
    try expect(callCount, equals: 2)
    ctrl.panel.dismiss()
}

test("show always starts with selection at (0,0)") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
         makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari")]
    })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    ctrl.panel.state.selectedColumn = 0
    ctrl.panel.state.selectedRow = 1
    ctrl.toggle(on: screen) // dismiss

    ctrl.toggle(on: screen) // re-show
    try expect(ctrl.panel.state.selectedColumn, equals: 0)
    try expect(ctrl.panel.state.selectedRow, equals: 0)
    ctrl.panel.dismiss()
}

test("data actions do not re-query window list") {
    var callCount = 0
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        callCount += 1
        return [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
                makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari")]
    })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(callCount, equals: 1)

    ctrl.spreadsheetDidRequestAddColumn()
    try expect(callCount, equals: 1)

    ctrl.spreadsheetDidRequestDeleteColumn(column: 0)
    try expect(callCount, equals: 1)

    ctrl.panel.dismiss()
}

test("cancel dismisses panel without terminating") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(ctrl.panel.isVisible, equals: true)

    ctrl.panel.apply(.keyDown(.cancel))
    try expect(ctrl.panel.isVisible, equals: false)
}

test("confirm dismisses panel") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(ctrl.panel.isVisible, equals: true)

    ctrl.panel.apply(.keyDown(.confirm))
    try expect(ctrl.panel.isVisible, equals: false)
}

// MARK: – Store helpers

func makeWindowWithBundle(id: CGWindowID, title: String, bundleId: String, frame: CGRect = .zero) -> Window {
    Window(id: id, app: currentApp, title: title, axElement: dummyAx, bundleId: bundleId, frame: frame)
}

func makeTestConfig(overrides: [String: String] = [:]) -> Config {
    let toml = makeConfigTOML(overrides: overrides)
    let (config, _) = Config.parse(toml)
    return config!
}

var storeTestIndex = 0
func makeTestStore() -> Store {
    storeTestIndex += 1
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("windowmap-test-\(ProcessInfo.processInfo.processIdentifier)-\(storeTestIndex)")
    try? FileManager.default.removeItem(at: dir)
    return Store(storageDir: dir)
}

// MARK: – Store: default state

test("new store has one workspace named Workspace0") {
    let store = makeTestStore()
    let ws = store.workspaces()
    try expect(ws.count, equals: 1)
    try expect(ws[0].name, equals: "Workspace0")
}

// MARK: – Store: window ingestion

test("first update assigns all windows to active workspace") {
    let store = makeTestStore()
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    store.update(windows: windows)

    let ws = store.workspaces()
    try expect(ws[0].windowIds.count, equals: 2)
    try expectTrue(ws[0].windowIds.contains(1))
    try expectTrue(ws[0].windowIds.contains(2))
}

test("windows persist across updates with same IDs") {
    let store = makeTestStore()
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    store.update(windows: windows)
    store.update(windows: windows)

    let ws = store.workspaces()
    try expect(ws[0].windowIds.count, equals: 2)
}

test("stale windows are kept in workspace (not dropped)") {
    let store = makeTestStore()
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ])
    // Safari disappeared (closed or transient)
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])

    // windowIds still has both — stale IDs are kept for resilience
    let ws = store.workspaces()
    try expectTrue(ws[0].windowIds.contains(1))
    try expectTrue(ws[0].windowIds.contains(2))

    // but groupCurrentWorkspaces filters to live only
    let groups = store.groupCurrentWorkspaces(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])
    try expect(groups[0].1.count, equals: 1)
}

test("new windows are appended to active workspace") {
    let store = makeTestStore()
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])
    // Safari opens
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ])

    let ws = store.workspaces()
    try expect(ws[0].windowIds.count, equals: 2)
    try expectTrue(ws[0].windowIds.contains(2))
}

// MARK: – Store: ID remap

test("remap step 1: direct ID match preserves assignment") {
    let store = makeTestStore()
    store.addWorkspace(name: "Other")
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])
    store.moveWindow(1, toWorkspace: store.workspaces()[1].id)

    // Same ID, same bundleId — stays in "Other"
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal - zsh", bundleId: "com.apple.Terminal"),
    ])

    let ws = store.workspaces()
    try expectTrue(!ws[0].windowIds.contains(1))
    try expectTrue(ws[1].windowIds.contains(1))
}

test("remap step 2: title+bundleId match preserves assignment across ID change") {
    let store = makeTestStore()
    store.addWorkspace(name: "Other")
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])
    store.moveWindow(1, toWorkspace: store.workspaces()[1].id)

    // App restarted: new ID, same title + bundleId
    store.update(windows: [
        makeWindowWithBundle(id: 99, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])

    let ws = store.workspaces()
    try expectTrue(!ws[0].windowIds.contains(99))
    try expectTrue(ws[1].windowIds.contains(99))
}

test("remap step 3: bundleId-only match preserves assignment") {
    let store = makeTestStore()
    store.addWorkspace(name: "Other")
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Old Title", bundleId: "com.app.unique"),
    ])
    store.moveWindow(1, toWorkspace: store.workspaces()[1].id)

    // App restarted: new ID, new title, same bundleId (only one window for this app)
    store.update(windows: [
        makeWindowWithBundle(id: 50, title: "New Title", bundleId: "com.app.unique"),
    ])

    let ws = store.workspaces()
    try expectTrue(!ws[0].windowIds.contains(50))
    try expectTrue(ws[1].windowIds.contains(50))
}

test("remap step 3: custom-titled entries participate in bundleId match") {
    let store = makeTestStore()
    store.addWorkspace(name: "Other")
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Tab", bundleId: "com.google.Chrome"),
    ])
    store.setTitle("Mail", for: 1)
    store.moveWindow(1, toWorkspace: store.workspaces()[1].id)

    store.update(windows: [
        makeWindowWithBundle(id: 50, title: "New Title", bundleId: "com.google.Chrome"),
    ])

    let ws = store.workspaces()
    try expectTrue(ws[1].windowIds.contains(50))
    try expect(store.title(for: 50), equals: "Mail")
}

test("remap step 4: frame+bundleId match preserves assignment") {
    let store = makeTestStore()
    store.addWorkspace(name: "Other")
    let leftFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
    let rightFrame = CGRect(x: 800, y: 0, width: 800, height: 600)
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Tab", bundleId: "com.google.Chrome", frame: leftFrame),
        makeWindowWithBundle(id: 2, title: "Tab", bundleId: "com.google.Chrome", frame: rightFrame),
    ])
    store.moveWindow(2, toWorkspace: store.workspaces()[1].id)

    store.update(windows: [
        makeWindowWithBundle(id: 50, title: "Tab", bundleId: "com.google.Chrome", frame: leftFrame),
        makeWindowWithBundle(id: 51, title: "Tab", bundleId: "com.google.Chrome", frame: rightFrame),
    ])

    let ws = store.workspaces()
    try expectTrue(ws[0].windowIds.contains(50))
    try expectTrue(ws[1].windowIds.contains(51))
}

test("remap step 4: same frame (maximized) does not match") {
    let store = makeTestStore()
    store.addWorkspace(name: "Other")
    let fullFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Tab", bundleId: "com.google.Chrome", frame: fullFrame),
        makeWindowWithBundle(id: 2, title: "Tab", bundleId: "com.google.Chrome", frame: fullFrame),
    ])
    store.moveWindow(2, toWorkspace: store.workspaces()[1].id)

    store.update(windows: [
        makeWindowWithBundle(id: 50, title: "Tab", bundleId: "com.google.Chrome", frame: fullFrame),
        makeWindowWithBundle(id: 51, title: "Tab", bundleId: "com.google.Chrome", frame: fullFrame),
    ])

    // Can't disambiguate — new windows go to active workspace, old IDs kept
    let ws = store.workspaces()
    try expectTrue(ws[0].windowIds.contains(50))
    try expectTrue(ws[0].windowIds.contains(51))
    // Old stale IDs (1, 2) also kept
    try expectTrue(ws[0].windowIds.contains(1))
    try expectTrue(ws[1].windowIds.contains(2))
}

// MARK: – Store: updateAndGroup

test("updateAndGroup returns workspace-window pairs") {
    let store = makeTestStore()
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    let cols = store.updateAndGroup(for: windows)

    try expect(cols.count, equals: 1)
    try expect(cols[0].0.name, equals: "Workspace0")
    try expect(cols[0].1.count, equals: 2)
}

test("updateAndGroup MRU: workspace with frontmost window comes first") {
    let store = makeTestStore()
    store.addWorkspace(name: "Secondary")
    // workspaces: [Secondary(0), Workspace0(1)]

    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ])
    // Both in Secondary (active workspace). Move Terminal to Workspace0.
    store.moveWindow(1, toWorkspace: store.workspaces()[1].id)
    // Secondary: [Safari], Workspace0: [Terminal]

    // Terminal (id=1) is frontmost (first in array) → Workspace0 should come first
    let cols = store.updateAndGroup(for: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ])

    try expect(cols[0].0.name, equals: "Workspace0")
    try expect(cols[1].0.name, equals: "Secondary")
}

test("updateAndGroup preserves z-order (MRU) within each workspace") {
    let store = makeTestStore()
    // Add 3 windows — store persists them in insertion order
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "A", bundleId: "com.a"),
        makeWindowWithBundle(id: 2, title: "B", bundleId: "com.b"),
        makeWindowWithBundle(id: 3, title: "C", bundleId: "com.c"),
    ])

    // Query with different z-order: C is frontmost, then A, then B
    let cols = store.updateAndGroup(for: [
        makeWindowWithBundle(id: 3, title: "C", bundleId: "com.c"),
        makeWindowWithBundle(id: 1, title: "A", bundleId: "com.a"),
        makeWindowWithBundle(id: 2, title: "B", bundleId: "com.b"),
    ])

    // Windows within workspace must follow input z-order, not store order
    try expect(cols[0].1[0].title, equals: "C")
    try expect(cols[0].1[1].title, equals: "A")
    try expect(cols[0].1[2].title, equals: "B")
}

test("updateAndGroup filters to live windows only") {
    let store = makeTestStore()
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ])

    // Safari closed — only Terminal is live
    let cols = store.updateAndGroup(for: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])

    try expect(cols[0].1.count, equals: 1)
    try expect(cols[0].1[0].title, equals: "Terminal")
}

// MARK: – Store: workspace CRUD

test("addWorkspace creates a new workspace") {
    let store = makeTestStore()
    store.addWorkspace(name: "Code")

    let ws = store.workspaces()
    try expect(ws.count, equals: 2)
    try expectTrue(ws.contains { $0.name == "Code" })
}

test("removeWorkspace removes a workspace") {
    let store = makeTestStore()
    let id = store.addWorkspace(name: "Temp")
    store.removeWorkspace(id: id)

    let ws = store.workspaces()
    try expect(ws.count, equals: 1)
    try expect(ws[0].name, equals: "Workspace0")
}

test("cannot remove last workspace") {
    let store = makeTestStore()
    let ws = store.workspaces()
    store.removeWorkspace(id: ws[0].id)

    try expect(store.workspaces().count, equals: 1)
}

test("renameWorkspace changes name") {
    let store = makeTestStore()
    let ws = store.workspaces()
    store.renameWorkspace(id: ws[0].id, name: "Code")

    try expect(store.workspaces()[0].name, equals: "Code")
}

// MARK: – Store: deleteContext

test("isContextDeletable returns false for last context") {
    let store = makeTestStore()
    let ctxs = store.contexts()
    try expectTrue(!store.isContextDeletable(id: ctxs[0].id))
}

test("isContextDeletable returns false for context with windows") {
    let store = makeTestStore()
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])
    store.addContext(name: "Second")
    let ctxs = store.contexts()
    try expect(ctxs.count, equals: 2)
    let original = ctxs.first(where: { $0.name != "Second" })!
    let second = ctxs.first(where: { $0.name == "Second" })!
    try expectTrue(!store.isContextDeletable(id: original.id))
    try expectTrue(store.isContextDeletable(id: second.id))
}

test("isContextDeletable returns true for empty non-last context") {
    let store = makeTestStore()
    store.addContext(name: "Second")
    let ctxs = store.contexts()
    try expect(ctxs.count, equals: 2)
    try expectTrue(store.isContextDeletable(id: ctxs[0].id))
    try expectTrue(store.isContextDeletable(id: ctxs[1].id))
}

test("deleteContext does not delete context with windows") {
    let store = makeTestStore()
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])
    store.addContext(name: "Second")
    let ctxs = store.contexts()
    let originalId = ctxs.first(where: { $0.name != "Second" })!.id
    store.setActiveContext(id: originalId)
    store.deleteContext(id: originalId)
    try expect(store.contexts().count, equals: 2)
}

test("deleteContext cannot delete last context") {
    let store = makeTestStore()
    let ctxs = store.contexts()
    store.deleteContext(id: ctxs[0].id)
    try expect(store.contexts().count, equals: 1)
}

// MARK: – Store: moveWindow

test("moveWindow moves window between workspaces") {
    let store = makeTestStore()
    store.addWorkspace(name: "Other")
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])

    try expectTrue(store.workspaces()[0].windowIds.contains(1))

    store.moveWindow(1, toWorkspace: store.workspaces()[1].id)

    try expectTrue(!store.workspaces()[0].windowIds.contains(1))
    try expectTrue(store.workspaces()[1].windowIds.contains(1))
}

// MARK: – Store: custom titles

test("custom title can be set and retrieved") {
    let store = makeTestStore()
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])

    try expect(store.title(for: 1), equals: nil)

    store.setTitle("My Terminal", for: 1)
    try expect(store.title(for: 1), equals: "My Terminal")
}

// MARK: – Store: setActiveFocus

test("setActiveFocus switches context to match window") {
    let store = makeTestStore()
    let ctx1 = store.activeContextId()!
    let ctx2 = store.addContext(name: "Work")

    // Get ctx2's workspace while it's active
    let ctx2ws = store.workspaces()[0].id
    store.setActiveContext(id: ctx1)

    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1"),
        makeWindowWithBundle(id: 2, title: "Win2", bundleId: "com.test.2"),
    ])

    store.moveWindow(2, toWorkspace: ctx2ws)

    try expect(store.activeContextId(), equals: ctx1)
    store.setActiveFocus(windowId: 2)
    try expect(store.activeContextId(), equals: ctx2)
}

test("setActiveFocus is no-op when already on correct context") {
    let store = makeTestStore()
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1"),
    ])
    let ctx = store.activeContextId()!
    store.setActiveFocus(windowId: 1)
    try expect(store.activeContextId(), equals: ctx)
}

test("setActiveFocus is no-op for unknown window") {
    let store = makeTestStore()
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1"),
    ])
    let ctx = store.activeContextId()!
    store.setActiveFocus(windowId: 999)
    try expect(store.activeContextId(), equals: ctx)
}

// MARK: – PanelController: data actions

test("addColumn creates workspace and updates panel") {
    let store = makeTestStore()
    let windows = [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(ctrl.panel.state.columns.count, equals: 1)

    ctrl.spreadsheetDidRequestAddColumn()

    try expect(ctrl.panel.state.columns.count, equals: 2)
    try expect(store.workspaces().count, equals: 2)
    ctrl.panel.dismiss()
}

test("deleteColumn removes empty workspace and updates panel") {
    let store = makeTestStore()
    store.addWorkspace(name: "Code")
    let windows = [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    // Add another workspace, then delete the empty one
    ctrl.spreadsheetDidRequestAddColumn()
    let emptyCol = ctrl.dataSource.columns.firstIndex(where: { $0.1.isEmpty })!
    ctrl.spreadsheetDidRequestDeleteColumn(column: emptyCol)

    try expect(store.workspaces().count, equals: 2)
    ctrl.panel.dismiss()
}

test("moveRow moves window and selection follows") {
    let store = makeTestStore()
    store.addWorkspace(name: "Other")
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    // Move Terminal from column 0 to column 1
    ctrl.spreadsheetDidRequestMoveRow(column: 0, row: 0, toColumn: 1)

    // Selection follows to target column, row 0
    try expect(ctrl.panel.state.selectedColumn, equals: 1)
    try expect(ctrl.panel.state.selectedRow, equals: 0)
    // Terminal is at row 0 of target column in data source
    try expect(ctrl.dataSource.rowLabel(column: 1, row: 0), equals: "Terminal")
    ctrl.panel.dismiss()
}

test("moveRow preserves column order") {
    let store = makeTestStore()
    store.addWorkspace(name: "Other")
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    let col0Name = ctrl.dataSource.columnName(0)
    let col1Name = ctrl.dataSource.columnName(1)

    ctrl.spreadsheetDidRequestMoveRow(column: 0, row: 0, toColumn: 1)

    // Column order unchanged
    try expect(ctrl.dataSource.columnName(0), equals: col0Name)
    try expect(ctrl.dataSource.columnName(1), equals: col1Name)
    ctrl.panel.dismiss()
}

// MARK: – PanelController: closeRow

test("closeRow removes window from data source and store") {
    let store = makeTestStore()
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(ctrl.dataSource.rowCount(in: 0), equals: 2)

    ctrl.spreadsheetDidRequestCloseRow(column: 0, row: 0)

    try expect(ctrl.dataSource.rowCount(in: 0), equals: 1)
    try expect(ctrl.dataSource.rowLabel(column: 0, row: 0), equals: "Safari")
    // Window 1 should be removed from the store workspace
    let ws = store.workspaces()
    try expect(ws[0].windowIds.contains(1), equals: false)
    try expectTrue(ws[0].windowIds.contains(2))
    ctrl.panel.dismiss()
}

test("closeRow calls onCloseWindow callback") {
    let store = makeTestStore()
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    var closedWindowId: CGWindowID? = nil
    ctrl.onCloseWindow = { closedWindowId = $0.id }
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    ctrl.spreadsheetDidRequestCloseRow(column: 0, row: 0)

    try expect(closedWindowId, equals: 1)
    ctrl.panel.dismiss()
}

test("closeRow sets suppressResignUntil timestamp") {
    let store = makeTestStore()
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    ctrl.onCloseWindow = { _ in }
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    let before = CFAbsoluteTimeGetCurrent()
    ctrl.spreadsheetDidRequestCloseRow(column: 0, row: 0)

    // suppressResignUntil should be ~0.3s in the future
    try expectTrue(ctrl.suppressResignUntil >= before + 0.2)
    try expectTrue(ctrl.suppressResignUntil <= before + 0.5)
    ctrl.panel.dismiss()
}

test("closeRow selection moves to min(row, rowCount-1)") {
    let store = makeTestStore()
    let windows = [
        makeWindowWithBundle(id: 1, title: "A", bundleId: "com.a"),
        makeWindowWithBundle(id: 2, title: "B", bundleId: "com.b"),
        makeWindowWithBundle(id: 3, title: "C", bundleId: "com.c"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    ctrl.onCloseWindow = { _ in }
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    // Close last row (row 2)
    ctrl.spreadsheetDidRequestCloseRow(column: 0, row: 2)
    try expect(ctrl.panel.state.selectedRow, equals: 1)

    // Close middle row (row 1, now last)
    ctrl.spreadsheetDidRequestCloseRow(column: 0, row: 1)
    try expect(ctrl.panel.state.selectedRow, equals: 0)
    ctrl.panel.dismiss()
}

test("closeRow on last window leaves column empty without auto-delete") {
    let store = makeTestStore()
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    ctrl.onCloseWindow = { _ in }
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(ctrl.dataSource.columnCount, equals: 1)
    try expect(ctrl.dataSource.rowCount(in: 0), equals: 1)

    ctrl.spreadsheetDidRequestCloseRow(column: 0, row: 0)

    // Column still exists, just empty
    try expect(ctrl.dataSource.columnCount, equals: 1)
    try expect(ctrl.dataSource.rowCount(in: 0), equals: 0)
    ctrl.panel.dismiss()
}

test("closeRow removes window from cachedWindows so it does not reappear on tab switch") {
    let store = makeTestStore()
    store.addContext(name: "Work")
    // contexts: [Work(active), Context0]
    // Assign windows to Work
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    store.update(windows: windows)

    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    ctrl.onCloseWindow = { _ in }
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(ctrl.dataSource.rowCount(in: 0), equals: 2)

    // Close Terminal (id=1)
    ctrl.spreadsheetDidRequestCloseRow(column: 0, row: 0)
    try expect(ctrl.dataSource.rowCount(in: 0), equals: 1)

    // Switch tab — this reloads data for the context using cachedWindows.
    // The closed window should not reappear.
    ctrl.spreadsheetDidSwitchTab(index: ctrl.panel.state.activeTab)
    try expect(ctrl.dataSource.rowCount(in: 0), equals: 1)
    try expect(ctrl.dataSource.rowLabel(column: 0, row: 0), equals: "Safari")
    ctrl.panel.dismiss()
}

// MARK: – PanelController: context integration

test("show populates tabs from store contexts") {
    let store = makeTestStore()
    store.addContext(name: "Work")
    // contexts: [Work, Context0] — Work was inserted at front and made active
    // Switch back so both exist
    let windows = [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)

    try expect(ctrl.panel.state.tabs.count, equals: 2)
    let tabNames = ctrl.panel.state.tabs.map { $0.name }
    try expectTrue(tabNames.contains("Work"))
    try expectTrue(tabNames.contains("Context0"))
    ctrl.panel.dismiss()
}

test("tab switch reloads workspaces for new context") {
    let store = makeTestStore()
    // Rename the default workspace to distinguish it
    store.renameWorkspace(id: store.workspaces()[0].id, name: "DefaultWS")
    store.addContext(name: "Work")
    // contexts: [Work(active, has "Workspace0"), Context0(has "DefaultWS")]
    // Assign window 1 to Work
    store.update(windows: [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")])
    // Switch to Context0 and assign window 2
    store.setActiveContext(id: store.contexts()[1].id)
    store.update(windows: [makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari")])
    // Switch back to Work for show
    store.setActiveContext(id: store.contexts()[0].id)

    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    // Work context is active — should show "Workspace0" with Terminal
    let workLabel = ctrl.dataSource.rowLabel(column: 0, row: 0)
    try expect(ctrl.dataSource.columnName(0), equals: "Workspace0")
    try expect(workLabel, equals: "Terminal")

    // Switch to Context0
    store.setActiveContext(id: store.contexts()[1].id)
    let cols2 = store.updateAndGroup(for: windows)
    ctrl.dataSource.columns = cols2
    ctrl.panel.refresh()

    // Context0 has "DefaultWS" with Safari
    try expect(ctrl.dataSource.columnName(0), equals: "DefaultWS")
    try expect(ctrl.dataSource.rowLabel(column: 0, row: 0), equals: "Safari")
    ctrl.panel.dismiss()
}

test("addTab creates context and updates panel") {
    let store = makeTestStore()
    let windows = [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(store.contexts().count, equals: 1)
    try expect(ctrl.panel.state.tabs.count, equals: 1)

    ctrl.spreadsheetDidRequestAddTab()

    try expect(store.contexts().count, equals: 2)
    try expect(ctrl.panel.state.tabs.count, equals: 2)
    // New context has auto-generated name
    let newCtx = store.contexts().first { $0.name != "Context0" }
    try expectNotNil(newCtx, "new context")
    ctrl.panel.dismiss()
}

test("deleteTab removes context") {
    let store = makeTestStore()
    // Assign the window to Context0 first so it won't go to Temp
    store.update(windows: [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")])
    // Now add Temp — it has one empty workspace, no windows
    store.addContext(name: "Temp")
    // contexts: [Temp(active, empty), Context0(has Terminal)]
    // Switch to Context0 so Temp stays empty during show
    store.setActiveContext(id: store.contexts()[1].id)

    let windows = [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }

    ctrl.toggle(on: screen)
    try expect(store.contexts().count, equals: 2)
    try expect(ctrl.panel.state.tabs.count, equals: 2)

    // Find the Temp tab in MRU order
    let tempTabIdx = ctrl.panel.state.tabs.firstIndex(where: { $0.name == "Temp" })!
    ctrl.spreadsheetDidRequestDeleteTab(index: tempTabIdx)

    try expect(store.contexts().count, equals: 1)
    try expect(ctrl.panel.state.tabs.count, equals: 1)
    try expect(store.contexts()[0].name, equals: "Context0")
    ctrl.panel.dismiss()
}

test("tab MRU ordering: context with frontmost window first") {
    let store = makeTestStore()
    store.addContext(name: "Secondary")
    // contexts: [Secondary(active), Context0]
    // Assign window 1 to Secondary
    store.update(windows: [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.a")])
    // Switch to Context0, assign window 2
    store.setActiveContext(id: store.contexts()[1].id)
    store.update(windows: [makeWindowWithBundle(id: 2, title: "Win2", bundleId: "com.b")])

    // Window 2 is frontmost (first in array) — it belongs to Context0
    // So Context0 should be the first tab
    let windows = [
        makeWindowWithBundle(id: 2, title: "Win2", bundleId: "com.b"),
        makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.a"),
    ]

    // Build tab order based on MRU: iterate windows front-to-back,
    // first context encountered becomes first tab
    let ctxs = store.contexts()
    var tabOrder: [String] = []
    var seen = Set<UUID>()
    for w in windows {
        for ctx in ctxs {
            if ctx.workspaces.contains(where: { $0.windowIds.contains(w.id) }),
               seen.insert(ctx.id).inserted {
                tabOrder.append(ctx.name)
            }
        }
    }
    // Append contexts with no live windows
    for ctx in ctxs where !seen.contains(ctx.id) {
        tabOrder.append(ctx.name)
    }

    // Context0 has the frontmost window (id=2), so it should be first
    try expect(tabOrder[0], equals: "Context0")
    try expect(tabOrder[1], equals: "Secondary")
}

test("tab switch immediately updates columns for new context") {
    let store = makeTestStore()
    store.addContext(name: "Work")
    // contexts: [Work(active), Context0]
    // Assign win1 to Work
    store.update(windows: [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ])
    // Switch to Context0, assign win2
    store.setActiveContext(id: store.contexts()[1].id)
    store.update(windows: [
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ])

    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    // Initially showing one context's workspaces
    let initialLabel = ctrl.dataSource.rowLabel(column: 0, row: 0)

    // Switch tab — columns should update to show the other context's windows
    let otherTabIdx = ctrl.panel.state.activeTab == 0 ? 1 : 0
    ctrl.spreadsheetDidSwitchTab(index: otherTabIdx)

    let newLabel = ctrl.dataSource.rowLabel(column: 0, row: 0)
    try expect(initialLabel != newLabel, equals: true)
    ctrl.panel.dismiss()
}

test("tab switch remembers selected workspace per context") {
    let store = makeTestStore()
    store.addContext(name: "Work")
    // contexts: [Work(0/active), Context0(1)]
    // Add second workspace to Work so it has 2 columns
    store.addWorkspace(name: "Code")

    let allWindows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    store.update(windows: allWindows)
    // Both in Work. Move win2 to Code workspace (index 0), win1 stays in Workspace0 (index 1)
    // Move win2 to Context0 so both contexts have windows
    store.setActiveContext(id: store.contexts()[1].id)
    store.moveWindow(2, toWorkspace: store.workspaces()[0].id)
    // Work: Code[win1] + Workspace0[], Context0: Workspace0[win2]

    // Frontmost = win1 (Terminal) → Work context first in MRU
    let windows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    // Work is active (tab 0), has 2 columns. Select column 1.
    try expectTrue(ctrl.dataSource.columnCount >= 2)
    ctrl.panel.state.selectedColumn = 1

    // Switch to Context0 (tab 1)
    ctrl.spreadsheetDidSwitchTab(index: 1)
    try expect(ctrl.panel.state.selectedColumn, equals: 0)

    // Switch back to Work (tab 0)
    ctrl.spreadsheetDidSwitchTab(index: 0)

    // Column 1 should be restored
    try expect(ctrl.panel.state.selectedColumn, equals: 1)
    ctrl.panel.dismiss()
}

test("tab switch maps MRU tab index to correct store context") {
    let store = makeTestStore()
    store.addContext(name: "Work")
    // Store order: [Work(0), Context0(1)]
    let allWindows = [
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
    ]
    // Assign both to Work (active)
    store.update(windows: allWindows)
    // Move win2 to Context0
    store.setActiveContext(id: store.contexts()[1].id)
    store.moveWindow(2, toWorkspace: store.workspaces()[0].id)
    // Now: Work has [win1], Context0 has [win2]

    // MRU: Safari frontmost → Context0 first, Work second
    let windows = [
        makeWindowWithBundle(id: 2, title: "Safari", bundleId: "com.apple.Safari"),
        makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    try expect(ctrl.panel.state.tabs[0].name, equals: "Context0")
    try expect(ctrl.panel.state.tabs[1].name, equals: "Work")

    // Switch to tab 1 (Work)
    ctrl.spreadsheetDidSwitchTab(index: 1)
    try expect(ctrl.dataSource.rowLabel(column: 0, row: 0), equals: "Terminal")
    ctrl.panel.dismiss()
}

// MARK: – Config: test helpers

/// Builds a valid TOML config string. Override individual keys via the overrides dictionary.
/// Keys use dotted notation: "panel_opacity", "picker.min_height_rows", etc.
func makeConfigTOML(overrides: [String: String] = [:]) -> String {
    func val(_ key: String, _ default_: String) -> String {
        overrides[key] ?? default_
    }
    return """
    log_level = "\(val("log_level", "info"))"
    panel_opacity = \(val("panel_opacity", "0.9"))

    [picker]
    trigger = "\(val("picker.trigger", "opt+space"))"
    quick_trigger = "\(val("picker.quick_trigger", "opt+tab"))"
    gesture = ""
    dismiss_gesture = ""
    show_plus_buttons = \(val("picker.show_plus_buttons", "true"))
    centered = \(val("picker.centered", "true"))
    panel_x = \(val("picker.panel_x", "0.1"))
    panel_y = \(val("picker.panel_y", "0.33"))
    column_width = \(val("picker.column_width", "5"))
    min_height_rows = \(val("picker.min_height_rows", "3"))
    max_height_rows = \(val("picker.max_height_rows", "10"))
    mru_order = \(val("picker.mru_order", "true"))
    click_outside = "\(val("picker.click_outside", "confirm"))"
    tab_switch = "\(val("picker.tab_switch", "hover"))"
    tab_hover_delay = \(val("picker.tab_hover_delay", "100"))

    [actions]
    rename = "r"
    move = "m"
    new = "n"
    close = "c"
    confirm = "return"
    cancel = "escape"

    [navigation]
    up = "up"
    down = "down"
    left = "left"
    right = "right"

    [switcher]
    trigger = ""
    visible_rows = 8
    width = \(val("switcher.width", "0.22"))

    [launcher]
    paths = "/Applications"

    [preview]
    cache_limit = 50
    border = 2
    border_radius = 9
    border_curve = "circular"
    """
}

// MARK: – Config: parsing new fields

test("config parses panel_opacity") {
    let toml = makeConfigTOML(overrides: ["panel_opacity": "0.75"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.panelOpacity, equals: 0.75)
}

test("config parses min_height_rows") {
    let toml = makeConfigTOML(overrides: ["picker.min_height_rows": "5"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.minHeightRows, equals: 5)
}

test("config parses max_height_rows") {
    let toml = makeConfigTOML(overrides: ["picker.max_height_rows": "8"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.maxHeightRows, equals: 8)
}

test("config parses mru_order true") {
    let toml = makeConfigTOML(overrides: ["picker.mru_order": "true"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.mruOrder, equals: true)
}

test("config parses mru_order false") {
    let toml = makeConfigTOML(overrides: ["picker.mru_order": "false"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.mruOrder, equals: false)
}

test("config parses panel_x as float") {
    let toml = makeConfigTOML(overrides: ["picker.panel_x": "0.25"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.panelX, equals: 0.25)
}

test("config parses column_width") {
    let toml = makeConfigTOML(overrides: ["picker.column_width": "6"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.columnWidth, equals: 6.0)
}

test("config parses centered") {
    let toml = makeConfigTOML(overrides: ["picker.centered": "false"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.centered, equals: false)
}

test("config parses click_outside") {
    let toml = makeConfigTOML(overrides: ["picker.click_outside": "cancel"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.clickOutside, equals: "cancel")
}

test("config parses switcher width") {
    let toml = makeConfigTOML(overrides: ["switcher.width": "0.30"])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.switcherWidth, equals: 0.30)
}

test("config missing panel_opacity reports error") {
    // Build TOML without panel_opacity line
    let toml = """
    log_level = "info"

    [picker]
    trigger = "opt+space"
    quick_trigger = "opt+tab"
    gesture = ""
    dismiss_gesture = ""
    show_plus_buttons = true
    centered = true
    panel_x = 0.1
    panel_y = 0.33
    column_width = 5
    min_height_rows = 3
    max_height_rows = 10
    mru_order = true
    click_outside = "confirm"

    [actions]
    rename = "r"
    move = "m"
    new = "n"
    close = "c"
    confirm = "return"
    cancel = "escape"

    [navigation]
    up = "up"
    down = "down"
    left = "left"
    right = "right"

    [switcher]
    trigger = ""
    visible_rows = 8
    width = 0.22

    [launcher]
    paths = "/Applications"

    [preview]
    cache_limit = 50
    border = 2
    border_radius = 9
    border_curve = "circular"
    """
    let (config, warnings) = Config.parse(toml)
    try expect(config == nil, equals: true)
    try expectTrue(warnings.contains { $0.contains("panel_opacity") })
}

test("config missing min_height_rows reports error") {
    // Use a TOML where min_height_rows is absent
    let toml = """
    log_level = "info"
    panel_opacity = 0.9

    [picker]
    trigger = "opt+space"
    quick_trigger = "opt+tab"
    gesture = ""
    dismiss_gesture = ""
    show_plus_buttons = true
    centered = true
    panel_x = 0.1
    panel_y = 0.33
    column_width = 5
    max_height_rows = 10
    mru_order = true
    click_outside = "confirm"

    [actions]
    rename = "r"
    move = "m"
    new = "n"
    close = "c"
    confirm = "return"
    cancel = "escape"

    [navigation]
    up = "up"
    down = "down"
    left = "left"
    right = "right"

    [switcher]
    trigger = ""
    visible_rows = 8
    width = 0.22

    [launcher]
    paths = "/Applications"

    [preview]
    cache_limit = 50
    border = 2
    border_radius = 9
    border_curve = "circular"
    """
    let (config, warnings) = Config.parse(toml)
    try expect(config == nil, equals: true)
    try expectTrue(warnings.contains { $0.contains("min_height_rows") })
}

test("config invalid min_height_rows (zero) reports error") {
    let toml = makeConfigTOML(overrides: ["picker.min_height_rows": "0"])
    let (config, warnings) = Config.parse(toml)
    try expect(config == nil, equals: true)
    try expectTrue(warnings.contains { $0.contains("min_height_rows") })
}

test("config invalid max_height_rows (negative) reports error") {
    let toml = makeConfigTOML(overrides: ["picker.max_height_rows": "-1"])
    let (config, warnings) = Config.parse(toml)
    try expect(config == nil, equals: true)
    try expectTrue(warnings.contains { $0.contains("max_height_rows") })
}

test("config invalid panel_opacity (not a number) reports error") {
    let toml = makeConfigTOML(overrides: ["panel_opacity": "\"abc\""])
    let (config, warnings) = Config.parse(toml)
    try expect(config == nil, equals: true)
    try expectTrue(warnings.contains { $0.contains("panel_opacity") })
}

test("config all new fields parse together") {
    let toml = makeConfigTOML(overrides: [
        "panel_opacity": "0.85",
        "picker.min_height_rows": "2",
        "picker.max_height_rows": "12",
        "picker.mru_order": "false",
    ])
    let (config, _) = Config.parse(toml)
    try expectNotNil(config, "config should parse")
    try expect(config!.panelOpacity, equals: 0.85)
    try expect(config!.minHeightRows, equals: 2)
    try expect(config!.maxHeightRows, equals: 12)
    try expect(config!.mruOrder, equals: false)
}

// MARK: – PanelController: rename

test("rename window sets custom title in Store") {
    let store = makeTestStore()
    let windows = [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    ctrl.spreadsheetDidRequestRename(target: .row(column: 0, row: 0), value: "My Terminal")

    try expect(store.title(for: 1), equals: "My Terminal")
    ctrl.panel.dismiss()
}

test("rename window with empty value removes custom title") {
    let store = makeTestStore()
    let windows = [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    store.update(windows: windows)
    store.setTitle("Old Name", for: 1)
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    ctrl.spreadsheetDidRequestRename(target: .row(column: 0, row: 0), value: "")

    try expect(store.title(for: 1) == nil, equals: true)
    ctrl.panel.dismiss()
}

test("rename workspace updates Store") {
    let store = makeTestStore()
    let windows = [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    ctrl.spreadsheetDidRequestRename(target: .columnHeader(column: 0), value: "Code")

    try expect(store.workspaces()[0].name, equals: "Code")
    ctrl.panel.dismiss()
}

test("rename context updates Store") {
    let store = makeTestStore()
    let windows = [makeWindowWithBundle(id: 1, title: "Terminal", bundleId: "com.apple.Terminal")]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    ctrl.spreadsheetDidRequestRename(target: .tab(index: 0), value: "Work")

    try expect(store.contexts()[0].name, equals: "Work")
    ctrl.panel.dismiss()
}

test("rename does not reorder columns or change selection") {
    let store = makeTestStore()
    store.addWorkspace(name: "Code")
    let windows = [
        makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1"),
        makeWindowWithBundle(id: 2, title: "Win2", bundleId: "com.test.2"),
    ]
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: { windows })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    let colsBefore = (0..<ctrl.dataSource.columnCount).map { ctrl.dataSource.columnName($0) }
    ctrl.panel.state.selectedColumn = 1
    ctrl.panel.state.selectedRow = 0

    ctrl.spreadsheetDidRequestRename(target: .columnHeader(column: 0), value: "Renamed")

    let colsAfter = (0..<ctrl.dataSource.columnCount).map { ctrl.dataSource.columnName($0) }
    try expect(colsAfter[0], equals: "Renamed")
    try expect(colsAfter.count, equals: colsBefore.count)
    try expect(ctrl.panel.state.selectedColumn, equals: 1)
    try expect(ctrl.panel.state.selectedRow, equals: 0)
    ctrl.panel.dismiss()
}

// MARK: – Results

// MARK: – PanelController: preview callbacks

test("onShowPreview called with focused window and priority order") {
    var capturedFocusedId: CGWindowID?
    var capturedPriority: [CGWindowID]?
    let store = makeTestStore()
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1"),
         makeWindowWithBundle(id: 2, title: "Win2", bundleId: "com.test.2"),
         makeWindowWithBundle(id: 3, title: "Win3", bundleId: "com.test.3")]
    })
    ctrl.onShowPreview = { focusedId, priority in
        capturedFocusedId = focusedId
        capturedPriority = priority
    }
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)
    try expectNotNil(capturedFocusedId, "focused id captured")
    try expect(capturedFocusedId!, equals: 1)
    try expectNotNil(capturedPriority, "priority captured")
    try expectTrue(capturedPriority!.contains(2))
    try expectTrue(capturedPriority!.contains(3))
    try expectTrue(!capturedPriority!.contains(1))
    ctrl.panel.dismiss()
}

test("onSelectionChanged called on navigation") {
    var changedWindows: [UInt32?] = []
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1"),
         makeWindowWithBundle(id: 2, title: "Win2", bundleId: "com.test.2")]
    })
    ctrl.onSelectionChanged = { win in changedWindows.append(win?.id) }
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)
    changedWindows = []
    ctrl.panel.apply(.keyDown(.down))
    try expectTrue(changedWindows.count >= 1)
    ctrl.panel.dismiss()
}

test("onDismiss called on cancel") {
    var dismissed = false
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    ctrl.panel.onDismiss = { dismissed = true }
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)
    ctrl.panel.apply(.keyDown(.cancel))
    try expectTrue(dismissed)
}

test("onSelectionChanged nil in tabNav mode") {
    var lastChange: UInt32?? = .some(99)
    let store = makeTestStore()
    store.addContext(name: "Extra")
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    ctrl.onSelectionChanged = { win in lastChange = win?.id }
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)
    lastChange = .some(99)
    ctrl.panel.apply(.keyDown(.down))
    // After down past last row, enters tabNav → selection should be nil
    if let change = lastChange, change == nil {
        // nil was sent — tab focused, no window preview
    } else {
        // might not fire if selection didn't change — check mode
        try expect(ctrl.panel.state.mode, equals: .tabNav)
    }
    ctrl.panel.dismiss()
}

// MARK: – AppLauncher: listApps

test("listApps finds apps in /Applications") {
    let apps = listApps(paths: ["/Applications"])
    try expectTrue(apps.count > 10)
}

test("listApps returns AppInfo with bundleID and name") {
    let apps = listApps(paths: ["/Applications"])
    guard let first = apps.first else { throw TestFailure("no apps found") }
    try expectTrue(!first.bundleID.isEmpty)
    try expectTrue(!first.name.isEmpty)
    try expect(first.nameLowercased, equals: first.name.lowercased())
}

test("listApps sorted alphabetically") {
    let apps = listApps(paths: ["/Applications"])
    for i in 1..<apps.count {
        try expectTrue(apps[i-1].nameLowercased <= apps[i].nameLowercased)
    }
}

// MARK: – Hotkey parsing

test("parseHotkeys parses multiple combos") {
    let keys = parseHotkeys("opt+tab,opt+k")
    try expectNotNil(keys, "should parse")
    try expect(keys!.count, equals: 2)
}

test("parseHotkeys parses punctuation keys") {
    let keys = parseHotkeys("opt+slash")
    try expectNotNil(keys, "slash should parse")
    let keys2 = parseHotkeys("cmd+/")
    try expectNotNil(keys2, "/ should parse")
}

test("parseHotkeys returns nil for invalid key") {
    let keys = parseHotkeys("opt+nonexistent")
    try expectNil(keys, "should fail")
}

test("parseHotkeys returns nil for empty string") {
    let keys = parseHotkeys("")
    try expectNil(keys, "should fail")
}

// MARK: – AppMRU

test("AppMRU records and retrieves bundle IDs") {
    let tmpDir = URL(fileURLWithPath: ".build/test-tmp/mru1", isDirectory: true)
    try? FileManager.default.removeItem(at: tmpDir)
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let mru = AppMRU(storageDir: tmpDir)
    mru.record("com.test.a")
    mru.record("com.test.b")
    let ids = mru.mruBundleIDs()
    try expect(ids.first, equals: "com.test.b")
    try expect(ids[1], equals: "com.test.a")
}

test("AppMRU moves repeated app to front") {
    let tmpDir = URL(fileURLWithPath: ".build/test-tmp/mru2", isDirectory: true)
    try? FileManager.default.removeItem(at: tmpDir)
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let mru = AppMRU(storageDir: tmpDir)
    mru.record("com.test.a")
    mru.record("com.test.b")
    mru.record("com.test.a")
    let ids = mru.mruBundleIDs()
    try expect(ids.first, equals: "com.test.a")
    try expect(ids.count, equals: 2)
}

test("AppMRU persists to disk") {
    let tmpDir = URL(fileURLWithPath: ".build/test-tmp/mru3", isDirectory: true)
    try? FileManager.default.removeItem(at: tmpDir)
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let mru1 = AppMRU(storageDir: tmpDir)
    mru1.record("com.test.persist")

    let fileURL = tmpDir.appendingPathComponent("app-mru.json")
    let data = try? Data(contentsOf: fileURL)
    try expectNotNil(data, "app-mru.json written to disk")
}

// MARK: – PanelController: launcher callback

test("onStartLauncher called on n key press") {
    var launcherStarted = false
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    ctrl.onStartLauncher = { launcherStarted = true }
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)
    launcherStarted = false

    ctrl.panel.apply(.dataAction(.addColumn))
    try expectTrue(launcherStarted)
    ctrl.panel.dismiss()
}

// MARK: – PanelController: right-click context menu

test("right-click on window row builds correct menu") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1"),
         makeWindowWithBundle(id: 2, title: "Win2", bundleId: "com.test.2")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    let menu = ctrl.buildContextMenu(for: .row(column: 0, row: 0))
    let titles = menu.items.map(\.title)
    try expect(titles, equals: ["Close Window", "Rename Window", "New Window"])
    ctrl.panel.dismiss()
}

test("right-click on non-empty workspace header builds correct menu") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    let menu = ctrl.buildContextMenu(for: .columnHeader(column: 0))
    let titles = menu.items.map(\.title)
    try expect(titles, equals: ["Rename Workspace", "New Workspace", "New Window"])
    ctrl.panel.dismiss()
}

test("right-click on empty workspace header includes Close") {
    let store = makeTestStore()
    store.addWorkspace(name: "Empty")
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    // Find the empty workspace column
    var emptyCol: Int?
    for i in 0..<ctrl.dataSource.columnCount {
        if ctrl.dataSource.rowCount(in: i) == 0 { emptyCol = i; break }
    }
    guard let col = emptyCol else { return }

    let menu = ctrl.buildContextMenu(for: .columnHeader(column: col))
    let titles = menu.items.map(\.title)
    try expect(titles, equals: ["Close Workspace", "Rename Workspace", "New Workspace", "New Window"])
    ctrl.panel.dismiss()
}

test("right-click on last tab omits Close") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    let menu = ctrl.buildContextMenu(for: .tab(index: 0))
    let titles = menu.items.map(\.title)
    try expect(titles, equals: ["Rename Context", "New Context"])
    ctrl.panel.dismiss()
}

test("right-click on non-last tab with windows omits Close") {
    let store = makeTestStore()
    store.addContext(name: "Second")
    let ctrl = PanelController(store: store, config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    let menu = ctrl.buildContextMenu(for: .tab(index: 0))
    let titles = menu.items.map(\.title)
    try expect(titles, equals: ["Rename Context", "New Context"])
    ctrl.panel.dismiss()
}

// MARK: – PanelController: launcher as modal

test("suspendForLauncher keeps panel visible") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)
    try expectTrue(ctrl.panel.isVisible)

    ctrl.suspendForLauncher()
    try expectTrue(ctrl.panel.isVisible)
    try expectTrue(ctrl.launcherActive)
    ctrl.panel.dismiss()
}

test("resumeFromLauncher clears launcherActive flag") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)
    ctrl.suspendForLauncher()

    ctrl.resumeFromLauncher()
    try expect(ctrl.launcherActive, equals: false)
    try expectTrue(ctrl.panel.isVisible)
    ctrl.panel.dismiss()
}

test("panel does not dismiss on resignKey when launcherActive") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)
    ctrl.suspendForLauncher()

    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: ctrl.panel)
    try expectTrue(ctrl.panel.isVisible)
    ctrl.panel.dismiss()
}

test("panel dismisses on resignKey when launcherActive is false") {
    let ctrl = PanelController(store: makeTestStore(), config: makeTestConfig(), listWindows: {
        [makeWindowWithBundle(id: 1, title: "Win1", bundleId: "com.test.1")]
    })
    guard let screen = NSScreen.main else { return }
    ctrl.toggle(on: screen)

    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: ctrl.panel)
    try expect(ctrl.panel.isVisible, equals: false)
}

if failCount > 0 {
    print("\n\(failCount) test(s) failed")
    exit(1)
} else {
    print("\nAll \(testCount) tests passed")
}
