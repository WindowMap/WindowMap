# SpreadsheetKit Specification

A generic UI component: a panel with tabs at the top and a grid of columns below. Each column contains rows. One tab is active, one column and row are selected.

## Data Source

The component does not own any content data. A consumer provides a data source:

- column count
- column name (by index)
- row count (by column index)
- row label (by column and row index)
- row icon (by column and row index, optional)

The component renders content by querying the data source. It never interprets what the data means.

## Actions

There are two kinds of actions:

### State actions

Pure state transitions handled entirely by the reducer. No delegate involvement.

- Navigation (up, down, left, right)
- Mode switching (browse ↔ tabNav)

### Data actions

Impure operations that modify the underlying data. The panel does not handle these — it calls the delegate, which modifies the model, updates the data source, and calls `panel.reloadData()` to re-render.

- **confirm(column, row)**: user confirmed the selected row (enter key or click)
- **cancel**: user dismissed (escape key)
- **addColumn**: user requested a new column
- **addTab**: user requested a new tab (add key pressed in tabNav mode)
- **close**: cascading close based on mode and state (see close routing below)
- **moveRow(originColumn, originRow, targetColumn)**: user confirmed a move in move mode
- **rename**: enter rename mode for the current target (see rename routing below)
- **didRequestRename(target, value)**: user confirmed a rename in rename mode

The consumer decides what these actions mean in their domain.

#### Close routing

The `close` key triggers different delegate methods based on mode and state:

| Mode | State | Delegate call |
|------|-------|--------------|
| browse | selected row exists | `didRequestCloseRow(column, row)` |
| browse | column is empty | `didRequestDeleteColumn(column)` |
| tabNav | — | `didRequestDeleteTab(index)` |

The consumer applies its own guards (can't delete last column, can't delete last tab, etc.).

#### Rename routing

The `rename` key enters rename mode. The target depends on mode:

| Mode | Target | Editor position |
|------|--------|----------------|
| browse | row (selected row's label) | over `label-{column}-{row}` |
| browse (empty column) | column header | over `header-{column}` |
| tabNav | tab (active tab) | over `tab-label-{index}` |

On commit, the delegate receives `didRequestRename(target, value)` where target is `.row(column, row)`, `.columnHeader(column)`, or `.tab(index)`.

## Data Model

- **Tab**: has an id and a name
- **Column**: has an id, a name, and a row count
- **State**: a list of tabs, active tab index, a list of columns, selected column index, selected row index, and a mode
- **KeyBindings**: maps key codes to actions. Configurable by the consumer. Default bindings cover navigation (arrow keys), confirm (return), and cancel (escape). Data action bindings (addColumn, close, moveRow, rename) have no defaults — the consumer must configure them.

## Modes

### Browse

The grid is focused. One row in one column is selected.

#### Keyboard

| Input | Condition | Result |
|-------|-----------|--------|
| down | selected row < last row | select next row |
| down | selected row = last row OR column is empty | enter tabNav |
| up | selected row > 0 | select previous row |
| up | selected row = 0 | enter tabNav |
| right | more than one column | select next column (wrap around); select row 0 |
| left | more than one column | select previous column (wrap around); select row 0 |
| confirm | — | emit confirm(column, row) to delegate |
| cancel | — | emit cancel to delegate |
| addColumn | — | emit addColumn to delegate |
| close | — | route via close routing (see above) |
| moveRow | more than one column, selected row valid | enter move mode (see Move below) |
| moveRow | single column, selected row valid, more than one tab | delegate moveColumn (cross-context) |
| rename | — | enter rename mode (see rename routing above) |

#### Mouse

| Input | Condition | Result |
|-------|-----------|--------|
| move over row | valid column and row | select that column and row |
| click tab | — | switch to that tab (emit switchTab to delegate) |

### TabNav

The tab strip is focused. One tab is highlighted.

#### Keyboard

| Input | Condition | Result |
|-------|-----------|--------|
| left | more than one tab | activate previous tab (wrap around) |
| right | more than one tab | activate next tab (wrap around) |
| down | — | return to browse, select row 0 |
| confirm | — | return to browse, select row 0 |
| up | — | return to browse, select last row |
| cancel | — | return to browse, keep current row |
| addColumn | — | emit addTab to delegate |
| close | — | emit deleteTab(activeTab) to delegate |
| rename | — | enter rename mode for active tab |

#### Mouse

| Input | Condition | Result |
|-------|-----------|--------|
| move over row | valid column and row | exit tabNav, enter browse, select that row |
| click tab | different tab | switch to that tab |

### Move

A row is being moved between columns. The state tracks:
- `moveOriginColumn`, `moveOriginRow`: where the row was picked up from
- `moveTargetColumn`: where the phantom currently sits (starts equal to origin)

The row at the origin position is hidden during move mode. The phantom always appears at row 0 of the target column, pushing existing rows down. The panel height adjusts dynamically as the phantom moves between columns — if the target column gains a row, the panel expands downward instead of showing a scrollbar.

#### Keyboard

| Input | Condition | Result |
|-------|-----------|--------|
| right | more than one column | move phantom to next column (wrap around) |
| left | more than one column | move phantom to previous column (wrap around) |
| up | tabs exist | enter moveTabNav (see below) |
| confirm | — | emit moveRow(originColumn, originRow, targetColumn) to delegate; return to browse |
| cancel | — | cancel move, return to browse at origin position |

#### Mouse

Mouse drag initiates and controls move mode:

1. **Mouse down** on a row: records origin column and row. On a column header: records origin column (workspace drag).
2. **Drag** (leftMouseDragged): enters move mode if not already in it. Phantom follows the column under the mouse cursor. Cursor changes to closed hand.
3. **Drag over tab**: if the mouse enters the tab strip during drag, emit `spreadsheetDidSwitchMoveTab(index:)` for the hovered tab. The context switches immediately (no delay). For row drag, also emit `spreadsheetDidDescendFromMoveTabNav()` to place the row in the new context. For header drag, the workspace phantom moves to the new context.
4. **Mouse up** on a column: commits the move (same as keyboard confirm). Cursor restores.
5. **Mouse up** outside or escape: cancels the move. Cursor restores. If context was switched during drag, restores original context.

Drag reuses the same move mode state and delegate — `spreadsheetDidRequestMoveRow` on commit for row drags, `spreadsheetDidConfirmMoveTab` for header drags. No separate drag action needed.

### MoveTabNav

Tab navigation while carrying a row or column. The tab strip is focused with phantom styling. Left/right navigate tabs. The grid below updates to preview the target context's columns.

When carrying a row (not a column), the origin row is hidden from the grid — the window is "being carried" and should not appear in any column until the user descends into a context. When carrying a column (workspace move), rows are not hidden.

This mode is entered from:
- Move mode via `up` (carrying a row/window)
- Browse mode via `spreadsheetDidRequestMoveColumn` (carrying a column/workspace)

The panel emits `spreadsheetDidSwitchMoveTab(index:)` on tab change, `spreadsheetDidDescendFromMoveTabNav()` on down (row move only), and `spreadsheetDidConfirmMoveTab()` on confirm (workspace move).

#### Keyboard

| Input | Condition | Result |
|-------|-----------|--------|
| left | more than one tab | activate previous tab (wrap); emit switchMoveTab |
| right | more than one tab | activate next tab (wrap); emit switchMoveTab |
| down | — | emit descendFromMoveTabNav; return to move mode |
| confirm | — | emit moveRow to delegate; return to browse |
| cancel | — | emit cancelMoveTabNav; return to browse |

### Rename

An inline text editor is active, allowing the user to edit a name. The state tracks:
- `renameTarget`: what is being renamed — `.row`, `.columnHeader`, or `.tab`

#### Keyboard

All keyDown events are passed to the text field (`super.sendEvent`). The panel does NOT route keys to actions while in rename mode. Standard editing shortcuts work natively (Cmd+A/C/V/X, arrow keys, option+arrows for word movement, etc.).

Enter and escape are intercepted via `NSControlTextEditingDelegate.doCommandBy`:

| Selector | Result |
|----------|--------|
| `insertNewline` | commit rename: emit `didRequestRename(target, value)` to delegate, return to previous mode |
| `cancelOperation` | cancel rename: discard changes, return to previous mode |

#### Mouse

Mouse input is ignored during rename mode.

#### Inline editor

The text field is an NSTextField overlaid on the item being renamed:
- For a row: positioned over the row label
- For a column header: positioned over the header label
- For a tab: positioned over the tab label

The editor has accent color border, corner radius, and is made first responder.

## Rendering

The renderer takes a state and a data source and produces a view hierarchy. It is data-driven: given the same state and data, it always produces the same output.

### Tab strip

The tab strip sits at the top of the panel, above the column headers and hairline separator.

- One tab view per tab in state, identified as `tab-{index}`
- Each tab shows the tab name as a label, identified as `tab-label-{index}`
- Active tab: accent color background (control accent at 0.35 alpha), white text, corner radius 6
- Inactive tabs: no background, secondary label color text
- In tabNav mode, the focused tab uses the selected content background color (instead of the 0.35 alpha accent) and white text
- The tab strip has a fixed height (`tabStripHeight`)
- A 1px hairline separator sits between the tab strip and the column headers

#### Smart tab sizing

Tabs have dynamic widths based on their label text:

1. **Natural width**: measure label text width + horizontal padding (2 × 10pt) + spacing between tabs (4pt). Clamp to minimum width (52pt).
2. **Shrink to fit**: if total natural width exceeds available space, iteratively shrink the widest tabs toward the second-widest until all tabs fit. Never shrink below minimum width.
3. **Overflow**: if tabs still don't fit at minimum width, the tab scroll view enables scrolling and chevrons appear.

The shrink algorithm is fair — it reduces the widest tabs first, distributing the reduction evenly among tabs of the same width. This ensures short-named tabs keep their natural size while long-named tabs truncate proportionally.

Tab labels use `lineBreakMode = .byTruncatingTail` so text truncates with ellipsis when the tab is narrower than the text.

### Structure

- One column view per column in state, identified as `column-{index}`
- Each column has a header background (`header-bg-{index}`), header label (`header-{index}`), and rows
- Each row is identified as `row-{column}-{row}`, contains a label (`label-{column}-{row}`) and optionally an icon (`icon-{column}-{row}`)
- Empty columns render the header but no rows

### Layout

#### Screen-adaptive sizing

All dimensions are derived from the screen's visible frame at show time. The panel uses the visible frame of the screen containing the mouse cursor (falling back to main screen). The consumer provides a `LayoutConfig` struct with precomputed sizes. SpreadsheetKit ships a default config computed from screen dimensions, but the consumer can override any value.

**Primary dimensions** follow the pattern `clamp(screenDimension * fraction, min, max).rounded()`:

| Property | Input | Fraction | Min | Max | Default (1440x900) |
|----------|-------|----------|-----|-----|---------------------|
| `rowHeight` | screen height | 0.044 | 38 | 56 | 40 |
| `tabStripHeight` | screen height | 0.034 | 26 | 40 | 31 |
| `columnWidth` | rowHeight | × 5 | — | — | 195–280 | (overridable via config `column_width` multiplier) |

**Derived dimensions** are ratios of primary dimensions:

| Property | Base | Ratio | Min | Max |
|----------|------|-------|-----|-----|
| `headerHeight` | rowHeight | 0.65 | 25 | 36 |
| `closeBtnSize` | rowHeight | 0.38 | 12 | 20 |
| `tabCloseBtnSize` | tabStripHeight | 0.32 | 8 | 14 |
| `iconSize` | rowHeight | 0.56 | -- | -- |

**Spacing** (ratios, no clamp):

| Property | Base | Ratio |
|----------|------|-------|
| `listInset` | rowHeight | 0.15 |
| `tabGap` | tabStripHeight | 0.18 |
| `tabTopPad` | tabStripHeight | 0.12 |
| `tabPadding` | tabStripHeight | 0.12 |
| `tabLeadingMargin` | tabStripHeight | 0.24 |
| `tabSpacing` | tabStripHeight | 0.09 |
| `tabTrailingMargin` | tabStripHeight | 0.12 |
| `tabHorizontalPad` | tabStripHeight | 0.33 |
| `tabMinWidth` | columnWidth | 0.30 |
| `tabLabelHeight` | tabStripHeight | 0.48 |

**Font sizing** — proportional to primary dimensions:

| Font | Base | Ratio | Usage |
|------|------|-------|-------|
| `rowFont` | rowHeight | 0.31 | Row labels |
| `smallFont` | rowHeight | 0.28 | Headers, tab labels |
| plus button | rowHeight | 0.38 | "+" button in empty columns |

**Row/header content layout** — all inner dimensions derive from the font or layout config, never hardcoded. Label frame height is the font's line height (`ceil(ascender - descender + leading)`). Vertical centering uses `(containerHeight - lineHeight) / 2`. Horizontal margins and icon-to-text gaps are proportional to `rowHeight`.

**maxVisibleRows**: provided by the consumer via config (`max_height_rows`). No hardcoded default — the value always comes from the config file.

**minVisibleRows**: provided by the consumer via config (`min_height_rows`). The panel is always at least this many rows tall, even when every column has fewer windows.

`LayoutConfig` receives `minVisibleRows` and `maxVisibleRows` from the consumer. SpreadsheetKit does not define defaults for these — the consumer must supply them. Column count is not clamped — the panel width is determined by the available screen width (see Panel width below).

**Fixed constants**: `hairlineH = 1`, `tabCornerRadius = 5`.

The `clamp` utility: `clamp(v, lo, hi) = min(max(v, lo), hi)`.

#### Panel dimensions

**Panel height:**
```
effectiveRows = clamp(actualMaxRows, minVisibleRows, maxVisibleRows)
panelContentHeight = headerHeight + hairlineH + listInset * 2 + rowHeight * effectiveRows
panelHeight = panelContentHeight + tabStripHeight + tabGap + tabTopPad
```

Where `actualMaxRows` is the tallest column's row count at show time. The panel is always at least `minVisibleRows` tall (padding with empty space) and at most `maxVisibleRows` tall (vertical scrollbar for overflow).

**Screen clamping:** after computing the panel height and position, if the panel's bottom edge would extend below the screen frame, the effective row count is reduced until the panel fits. This allows `max_height_rows` to be set high — the panel grows as tall as possible for the given `panel_y` position without going off-screen.

**Panel width:**
```
contentWidth = columnWidth * columnCount
panelWidth = min(contentWidth, availableWidth)
```

Where `availableWidth` is the screen width minus symmetric margins (from `panelX`). The panel grows with the number of columns and stops at the margin boundary. When columns overflow, the last column is clipped and a horizontal scrollbar appears. Layout methods read column count from the data source (not state) to avoid stale-state sizing bugs.

#### Horizontal scrolling

The column area is wrapped in a horizontal NSScrollView. When the total column width exceeds the panel width, a horizontal scrollbar appears. The scrollbar uses legacy style with auto-hide and small control size.

The scroll view overrides `tile()` to keep `contentView.frame = bounds` — prevents the scroller from shrinking the content area.

Vertical scroll gestures on columns that are more horizontal than vertical are forwarded to the column scroll view for horizontal scrolling.

When keyboard navigation (left/right) moves the selection to a column that is not fully visible, the column area smooth-scrolls (0.1s animation) to reveal the selected column. Only scrolls enough to bring the column into view — does not center it.

#### Tab strip scrolling

The tab strip has its own horizontal NSScrollView (no scrollbar). When tabs overflow the panel width, chevron indicators (`‹` `›`) appear at the edges. The tab strip scrolls to keep the active tab visible.

#### Structure

Columns are positioned side by side, each `columnWidth` wide.

The panel has a fixed vertical structure:

```
┌─────────────────────────────────────────┐
│ ‹ Tab strip (horizontal ScrollView)   › │  ← chevrons if overflow
│ Hairline separator                      │
├─────────────────────────────────────────┤
│ Column ScrollView (horizontal)          │  ← scrollbar if overflow
├───────────────┬───────────────┬─────────┤
│ Column 0      │ Column 1      │ ...     │
│ ┌───────────┐ │ ┌───────────┐ │         │
│ │ Header    │ │ │ Header    │ │         │
│ │ Hairline  │ │ │ Hairline  │ │         │
│ ├───────────┤ │ ├───────────┤ │         │
│ │ ScrollView│ │ │ ScrollView│ │         │
│ │ ┌───────┐ │ │ │ ┌───────┐ │ │         │
│ │ │ row 0 │ │ │ │ │ row 0 │ │ │         │
│ │ │ row 1 │ │ │ │ │ row 1 │ │ │         │
│ │ └───────┘ │ │ │ └───────┘ │ │         │
│ ├───────────┤ │ ├───────────┤ │         │
│ │ Plus row  │ │ │ Plus row  │ │         │
│ └───────────┘ │ └───────────┘ │         │
└───────────────┴───────────────┴─────────┘
```

Each column has a fixed vertical structure:

```
┌─────────────────────┐
│ Header (fixed)      │
│ Hairline            │
├─────────────────────┤
│ ScrollView (fixed h)│  ← height = maxVisibleRows × rowHeight
│ ┌─────────────────┐ │
│ │ phantom row     │ │  ← only in move mode, target column
│ │ window row 0    │ │
│ │ window row 1    │ │
│ │ ...             │ │
│ └─────────────────┘ │
├─────────────────────┤
│ Plus row (optional) │  ← outside scroll view, always visible
└─────────────────────┘
```

- The scroll view's visible height is `effectiveRows × rowHeight` (see panel dimensions above). When the document content (window rows + phantom) exceeds this, a vertical scrollbar appears.
- The plus row (future) sits below the scroll view. It does not count toward maxVisibleRows and is not affected by scrolling.
- Rows are stacked top-down, each `rowHeight` tall

### Highlight system

Two highlight levels, using named color constants:

- **`focusColor`**: system accent color (`controlAccentColor`) — the item the user is acting on (bright blue)
- **`pathColor`**: `focusColor` at `pathAlpha` (0.35) — shows the hierarchy path to the focused item (dimmed blue)

All colors are system dynamic colors — they adapt to dark mode, light mode, and user accent color preferences automatically. No hardcoded RGB values. Alpha values are named constants (`pathAlpha`, `phantomFillAlpha`, `phantomBorderAlpha`).

#### Focus rules (what gets `focusColor`)

| Mode | Focus target |
|------|-------------|
| browse, selected column has rows | selected row (selection subview with `focusColor` background, corner radius 6) |
| browse, selected column is empty | selected column header (header background with `focusColor` at `pathAlpha`) |
| tabNav | active tab (tab background with `focusColor`) |
| move | phantom row |

Only one element has focus at a time.

#### Path rules (what gets `pathColor`)

| Mode | Path elements |
|------|--------------|
| browse | active tab + selected column header |
| tabNav | nothing (tab is the top level, no path above it) |
| move | active tab + target column header |

#### Text colors

| Element | Condition | Color |
|---------|-----------|-------|
| row label | focused | white |
| row label | not focused | `labelColor` (system default) |
| column header | focused or path-highlighted | white |
| column header | not highlighted | `secondaryLabelColor` |
| tab label | focused | white |
| tab label | path-highlighted | white |
| tab label | not highlighted | `secondaryLabelColor` |

### Phantom row (move mode)

The row at the origin position is hidden during move mode. The phantom always appears at row 0 of the target column, pushing existing rows down.

- Background: `focusColor` at `phantomFillAlpha` (0.15)
- Border: dashed stroke (dash pattern [4, 3], line width 1.5, `focusColor` at `phantomBorderAlpha` (0.8))
- Corner radius: 6
- Contains the label and icon of the row being moved

## Panel

The panel is an NSPanel with non-activating, borderless style. It routes raw input events to state machine actions.

The panel overrides `canBecomeKey` to return `true`. Without this, a borderless non-activating panel cannot receive keyboard events — `sendEvent` never sees keyDown events, and `makeKeyAndOrderFront` has no effect.

### Keyboard routing

Key codes are configurable via `KeyBindings`. Each keyDown event is mapped to an action and routed based on its type:

- **State actions** (navigate, mode switch): applied to the reducer, state updated, view re-rendered. No delegate involvement.
- **Data actions** (confirm, cancel, addColumn, close, moveRow): forwarded to the delegate. The delegate handles domain logic, updates the data source, and calls `refresh()` to re-render.

### Mouse routing

A local event monitor tracks mouse movement and clicks. Mouse position is converted to column/row indices and mapped to `SpreadsheetAction.mouseMove` or confirm actions.

#### Tab hover switching

When `tabSwitchOnHover` is enabled, hovering over a tab switches context after a delay (`tabHoverDelay`). Two cases:

1. **Tab-to-tab**: cursor moves between tabs within the tab strip. Each new tab cancels the previous timer and starts a fresh one. The cursor must dwell on a tab for the full delay to trigger a switch. This natural timer-restart behavior creates stickiness.

2. **Row-to-tab (entry gate)**: cursor enters the tab strip from the row/header area. A gate timer starts for `tabHoverDelay`. During the gate, tab hover processing is suppressed — the cursor's tab position is tracked but no switch timer runs. When the gate timer fires, the tracked tab is applied immediately (the gate *is* the delay). After the gate opens, subsequent tab-to-tab movement within the same visit uses the normal timer mechanism (case 1). Leaving the tab strip resets the gate.

This ensures both trajectories (horizontal between tabs, vertical from rows) feel equally sticky despite different cursor dynamics.

The gate does not apply during drag (move mode handles tab switching separately with no delay).

### Right-click

Right-click on any element selects it (changes highlight) and reports the target to the delegate via `spreadsheetDidRightClick(target: PanelTarget)`. The delegate (consumer) is responsible for building and showing a context menu with domain-specific labels. SpreadsheetKit does not know about menu contents — it only reports what was clicked.

Right-click is blocked during quick sessions (same as data actions) and during rename mode.

`PanelTarget` identifies the clicked element:
- `.row(column:, row:)` — a window row
- `.columnHeader(column:)` — a workspace header
- `.tab(index:)` — a context tab
- `.tabStrip` — empty space in the tab strip (no specific tab)

The same enum is used for rename targeting (except `.tabStrip`).

### Positioning

`show(on:)` computes `LayoutConfig` from the screen's visible frame and positions the panel using `panelX` and `panelY` from the layout config:

- `panelX` (0.0–0.5): symmetric horizontal margin as fraction of screen width. Left edge at `panelX × screenWidth`, right boundary at `(1 - panelX) × screenWidth`. Columns grow right within that range.
- `panelY` (0.0–1.0): anchors the panel's **top edge** on the screen. 0.0 = top, 0.33 = upper third.

**Screen clamping:** after computing panel size and position, if the panel extends beyond the screen edges:
- Vertically: reduce visible rows to fit (scrollbar for overflow).
- Horizontally: panel width capped at available width (scrollbar for overflow).

Panel width and height adjust dynamically on tab switch and column add/remove via `relayout()`. Top edge and left edge stay fixed. Height is clamped to screen bounds.

### Lifecycle

- `show(on: NSScreen, maxColumns: Int)`: sizes the panel, centers it on the screen, renders initial state, makes key and order front, installs mouse monitor. When `centered = true`, centering uses `maxColumns` (the widest tab's column count) instead of the active tab's column count, so the panel opens at the same horizontal position regardless of which tab is active. The actual panel width still matches the active tab.
- `dismiss()`: cancels any active rename (hides editor, removes key monitor, resets mode), removes mouse monitor, orders out
- `apply(action)`: reduces state, notifies delegate if needed, re-renders
- `refresh()`: re-derives state columns from the data source (column count, names, row counts), re-renders. Does not query or reload data — the caller is responsible for updating the data source first. Called by the delegate after mutating the data source.
- `relayout()`: recalculates panel width and height from the data source and repositions (top edge and left edge fixed). Called after column add/remove/tab switch.
- `layoutForState()`: sizes and renders without showing — used for headless testing
