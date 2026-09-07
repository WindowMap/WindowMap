public enum KeyAction: Equatable {
    case up, down, left, right
    case confirm, cancel
}

public enum DataAction: Equatable {
    case addColumn
    case close
    case moveRow
    case moveColumn
    case rename
}

public enum SpreadsheetAction: Equatable {
    case keyDown(KeyAction)
    case dataAction(DataAction)
    case mouseMove(column: Int, row: Int)
    case mouseClickTab(index: Int)
}
