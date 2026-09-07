public func reduce(state: inout SpreadsheetState, action: SpreadsheetAction) {
    switch action {
    case .keyDown(let key):
        handleKey(state: &state, key: key)
    case .mouseMove(let column, let row):
        handleMouseMove(state: &state, column: column, row: row)
    case .mouseClickTab(let index):
        handleMouseClickTab(state: &state, index: index)
    case .dataAction(let da):
        handleDataActionReduce(state: &state, action: da)
    }
}

private func handleKey(state: inout SpreadsheetState, key: KeyAction) {
    switch state.mode {
    case .browse:
        handleBrowseKey(state: &state, key: key)
    case .tabNav:
        handleTabNavKey(state: &state, key: key)
    case .move:
        handleMoveKey(state: &state, key: key)
    case .moveTabNav:
        handleMoveTabNavKey(state: &state, key: key)
    case .rename:
        break
    }
}

private func handleDataActionReduce(state: inout SpreadsheetState, action: DataAction) {
    switch action {
    case .moveRow:
        guard state.mode == .browse,
              state.columns.count > 1,
              state.selectedColumn < state.columns.count,
              state.columns[state.selectedColumn].rowCount > 0 else { return }
        state.moveOriginColumn = state.selectedColumn
        state.moveOriginRow = state.selectedRow
        state.moveTargetColumn = state.selectedColumn
        state.mode = .move
    default:
        break
    }
}

private func handleBrowseKey(state: inout SpreadsheetState, key: KeyAction) {
    guard !state.columns.isEmpty else { return }
    let col = state.columns[state.selectedColumn]

    switch key {
    case .down:
        if col.rowCount == 0 || state.selectedRow >= col.rowCount - 1 {
            state.mode = .tabNav
        } else {
            state.selectedRow += 1
        }
    case .up:
        if state.selectedRow <= 0 {
            state.mode = .tabNav
        } else {
            state.selectedRow -= 1
        }
    case .left:
        if state.columns.count > 1 {
            state.selectedColumn = (state.selectedColumn - 1 + state.columns.count) % state.columns.count
            state.selectedRow = 0
        }
    case .right:
        if state.columns.count > 1 {
            state.selectedColumn = (state.selectedColumn + 1) % state.columns.count
            state.selectedRow = 0
        }
    case .confirm, .cancel:
        break
    }
}

private func navigateTab(state: inout SpreadsheetState, key: KeyAction) {
    switch key {
    case .left where state.tabs.count > 1:
        state.activeTab = (state.activeTab - 1 + state.tabs.count) % state.tabs.count
    case .right where state.tabs.count > 1:
        state.activeTab = (state.activeTab + 1) % state.tabs.count
    default: break
    }
}

private func handleTabNavKey(state: inout SpreadsheetState, key: KeyAction) {
    switch key {
    case .left, .right:
        navigateTab(state: &state, key: key)
    case .down, .confirm:
        state.mode = .browse
        state.selectedRow = 0
    case .up:
        state.mode = .browse
        let col = state.columns[state.selectedColumn]
        state.selectedRow = max(col.rowCount - 1, 0)
    case .cancel:
        state.mode = .browse
    }
}

private func handleMoveKey(state: inout SpreadsheetState, key: KeyAction) {
    switch key {
    case .right:
        if state.columns.count > 1 {
            state.moveTargetColumn = (state.moveTargetColumn + 1) % state.columns.count
        }
    case .left:
        if state.columns.count > 1 {
            state.moveTargetColumn = (state.moveTargetColumn - 1 + state.columns.count) % state.columns.count
        }
    case .cancel:
        state.selectedColumn = state.moveOriginColumn
        state.selectedRow = state.moveOriginRow
        state.mode = .browse
    case .confirm:
        break
    case .up:
        if !state.tabs.isEmpty { state.mode = .moveTabNav }
    case .down:
        break
    }
}

private func handleMoveTabNavKey(state: inout SpreadsheetState, key: KeyAction) {
    switch key {
    case .left, .right:
        navigateTab(state: &state, key: key)
    case .down:
        if !state.movingColumn { state.mode = .move }
    case .cancel:
        state.selectedColumn = state.moveOriginColumn
        state.selectedRow = state.moveOriginRow
        state.mode = .browse
    case .confirm, .up:
        break
    }
}

private func handleMouseMove(state: inout SpreadsheetState, column: Int, row: Int) {
    guard state.mode == .browse || state.mode == .tabNav else { return }
    guard column >= 0, column < state.columns.count,
          row >= 0, row < max(state.columns[column].rowCount, 1) else { return }
    if state.mode == .tabNav { state.mode = .browse }
    state.selectedColumn = column
    state.selectedRow = row
}

private func handleMouseClickTab(state: inout SpreadsheetState, index: Int) {
    guard index >= 0, index < state.tabs.count else { return }
    state.activeTab = index
    state.selectedRow = 0
}
