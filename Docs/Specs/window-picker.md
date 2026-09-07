# Window Picker

The app shows a panel with real macOS windows, grouped by workspace. The user navigates and selects a window to focus.

## Window type

A window has: an id (CGWindowID), a reference to its owning app (NSRunningApplication), a title (string), an accessibility element (AXUIElement), a bundle identifier (optional string), and an app name (optional string). Titles are normalized: newlines replaced by spaces, leading/trailing whitespace trimmed, empty lines removed.

## Window enumeration

`listWindows()` returns all visible standard windows on the current space, excluding the app's own windows.

For each running application with `.regular` activation policy (excludes background-only apps and the app itself):
1. Get the app's AX windows via `kAXWindowsAttribute`
2. For each AX window, resolve its CGWindowID via `_AXUIElementGetWindow`
3. Skip windows with layer > 0 (menubar items, overlays)
4. Skip windows with subrole other than `AXStandardWindow` or `AXDialog`
5. Skip windows smaller than 100×50 points
6. Title comes from AX first; falls back to CGWindowList title if AX title is empty

Results are sorted by z-order (front-to-back), derived from `CGWindowListCopyWindowInfo`. This matches most-recently-used order. Results are cached for 1 second.

## Window focus tracking

While the picker is hidden, an AX observer tracks which window has focus. On each focus change, the Store updates the active context and workspace to match the focused window's assignment. The current macOS space is also updated.

This ensures that when the picker opens, it shows the correct context — even if the user switched windows via Cmd+\` or clicking, without ever opening the picker.

### Observer lifecycle

One `AXObserver` per running app with `.regular` activation policy, listening for `kAXFocusedWindowChangedNotification`. Observers are managed based on app lifecycle:

- **App launch** (`NSWorkspace.didLaunchApplicationNotification`): add an observer for the new app. Without this, windows from apps launched after WindowMap starts would not be tracked.
- **App terminate** (`NSWorkspace.didTerminateApplicationNotification`): remove the observer and its run loop source. Without this, observers for dead processes leak.
- **Startup**: iterate all running `.regular` apps and add observers.

### Focus callback

Focus callbacks are debounced (100ms) to coalesce rapid focus changes (e.g., Cmd+Tab cycling). The callback resolves the focused `CGWindowID` and calls `store.setSpace(currentSpaceId())` then `store.setActiveFocus(windowId:)`, which finds the context and workspace containing that window and sets both as active. No-op if already focused on that context/workspace.

## Contexts

Contexts map to SpreadsheetKit tabs. Each context in the active space becomes one tab. Tab names are context names.

### Tab ordering (MRU)

At show time, tab order is derived from the cached window list (z-order). Iterate windows front-to-back; the first context that contains a window becomes the first tab. Subsequent contexts appear in the order they are first encountered. Contexts with no live windows are appended at the end in their original store order. Tab order is locked for the session (same as column order).

### Switching tabs

Left/right arrows in tabNav mode switch the active context **immediately** — the columns below update in real time as the user navigates tabs. The workspaces reload for the new context using the cached window list. Column order is re-derived (MRU) for the new context.

The PanelController maintains a mapping from MRU tab indices to Store context indices (since tab order is MRU, not Store insertion order). It also tracks the last selected workspace (column) per context. When returning to a previously visited context, the column selection is restored. Row selection is not remembered — it resets based on how the user exits tabNav (down/confirm → row 0, up → last row).

### Context CRUD

| Key | Mode | Domain behavior |
|-----|------|-----------------|
| shift+n | tabNav | Create a new context with auto-generated name ("Context1", "Context2", ...). Insert as first tab. Switch to the new context. Stay in tabNav mode. |
| shift+c | tabNav | Delete the focused context. Only allowed if: not the last context AND all workspaces are empty and auto-named (see `Workspace.isAutoNamed`). Focus moves to the next tab, or previous if last. |

After each context action, the delegate mutates the data source and Store, then calls `panel.refresh()`.

### Cross-context window move

While in move mode (phantom visible, navigating columns with left/right):

1. **Up** → enters `moveTabNav` — the phantom disappears from the grid. Tab strip gets focus. The current target column is remembered for this context.
2. **Left/right in moveTabNav** → navigates tabs, previewing different contexts. The grid below updates to show the target context's workspaces.
3. **Down from moveTabNav** → descends into the selected context's grid. The phantom appears at row 0 of the remembered column (or column 0 if first visit). The window is removed from any column in this context (if it was already here). Left/right resumes normal column navigation.
4. **Confirm** → commits the move. The window moves to the target workspace in the target context via `store.moveWindow`. Selection goes to (targetColumn, 0).
5. **Cancel in moveTabNav** → cancels the entire move. Window stays in its original context and workspace. Mode returns to browse.
6. **Up from move mode again** → re-enters moveTabNav. The target column for each previously visited context is remembered.

State tracked during cross-context move:
- `moveOriginContextId` — the context where the move started (for cancel/restore)
- `moveTargetContextId` — the context currently being targeted (nil = origin context)
- `moveTargetColumnPerContext` — remembered target column per context (for re-entry)

## Data source mapping

Windows are grouped by workspace (see [Store](store.md)). Each workspace in the **active context** becomes one column. Switching tabs changes which context is active, so column count and names change accordingly.

- **Column count**: number of workspaces in the active context
- **Column name**: workspace name
- **Row count**: number of live windows in that workspace
- **Row label**: window title
- **Row icon**: the owning app's icon (`app.icon`)

## Dismiss

The picker dismisses when it loses key window status (`NSWindow.didResignKeyNotification`). The resign handler is guarded by:

- `panel.isVisible` — ignore resign if the panel is already hidden
- `launcherActive` — ignore resign while the launcher is open as a modal overlay
- `suppressResignUntil` — time-based suppress (0.3s) during close-window AX calls that temporarily shift focus
- `isDragging` — ignore resign during mouse drag operations

When the resign handler fires, the `click_outside` config determines behavior:
- `"confirm"` — focus the currently selected window, then dismiss
- `"cancel"` — dismiss without focusing any window

If no window is selected (empty workspace), confirm falls back to cancel behavior.

## Actions

### Navigation

Handled by SpreadsheetKit's state machine — arrow keys, mouse hover. No domain logic.

### Action routing

Actions are determined by two inputs: **letter** (what to do) and **modifier** (to what entity). The modifier→entity mapping is configurable via `[modifiers]` in config. Default: none=window, shift=workspace, cmd=context.

**Convenience rule**: when focus makes the intent unambiguous, the modifier is redundant. Focus provides the floor — you can't target below the current focus level.

| Focus + key | n (new) | c (close) | r (rename) | m (move) |
|-------------|---------|-----------|------------|----------|
| window + plain | launcher | close window | rename window | move window |
| window + shift | new workspace | — | rename workspace | move workspace |
| window + cmd | new context | — | rename context | move context* |
| empty ws + plain | launcher | close workspace | rename workspace | move workspace |
| empty ws + shift | new workspace | close workspace | rename workspace | move workspace |
| empty ws + cmd | new context | close context† | rename context | move context* |
| context + plain | new context | close context† | rename context | move context* |
| context + shift | new context | close context† | rename context | move context* |
| context + cmd | new context | close context† | rename context | move context* |

\* only if mru_order=false
† only if deletable (all workspaces empty, not the last context)
`—` = no-op (close not meaningful at this level)

Additional fixed bindings:
- **return / click**: focus the selected window (AX raise + activate), dismiss panel
- **escape**: dismiss panel

### Right-click context menu

Right-click on a picker element selects it and shows a context menu with domain-specific actions. Blocked during quick sessions and rename mode.

| Right-click target | Menu items |
|---|---|
| Window row | Close Window, Rename Window, New Window (launcher) |
| Workspace header (non-empty) | Rename Workspace, New Workspace, New Window (launcher) |
| Workspace header (empty) | Close Workspace, Rename Workspace, New Workspace, New Window (launcher) |
| Context tab (deletable: all workspaces empty, not last) | Close Context, Rename Context, New Context |
| Context tab (last context) | Rename Context, New Context |
| Empty tab strip space | New Context |

Menu actions map to the same delegate methods as keyboard actions — no separate logic. SpreadsheetKit reports the right-click target via `spreadsheetDidRightClick(target:)`, PanelController builds the NSMenu.

### Close

Close window: AX close button press (see Close Window below).
Close workspace: only if empty. Remove from data source and Store.
Close context: only if all workspaces are empty and not the last context.

### Rename

Inline NSTextField editor overlaid on the target item's label. Enter commits, escape cancels. All standard editing shortcuts work (Cmd+A/C/V/X/Z, arrow keys, option+arrows).

- Rename window: `store.setTitle(value, for: windowId)`. Empty value removes custom title (reverts to AX title).
- Rename workspace: `store.renameWorkspace(id:, name:)`. Empty value ignored.
- Rename context: `store.renameContext(index:, name:)`. Empty value ignored.

After commit, panel refreshes. Mode returns to browse (or tabNav for context rename). Rename never reorders columns, rows, or changes selection — the data source is updated in-place, not reloaded from the Store.

### Move workspace to another context

`shift+m` (or `m` on an empty workspace) moves the entire workspace — with all its windows — to another context. Requires more than one context.

**When `mru_order = true` (default):**

1. **Trigger**: `shift+m` in browse mode → workspace column disappears from the grid. A phantom column (accent fill + thin border, same phantom styling as window move) appears appended to the grid as a preview. Mode enters `moveTabNav` directly (no intermediate move mode).
2. **Navigate**: left/right navigates tabs. The grid updates to show the target context's workspaces, with the phantom workspace column appended.
3. **Confirm**: workspace moves to the target context via `store.moveWorkspace`. Selection follows the moved workspace — it becomes the first column in the target context. Mode returns to browse.
4. **Cancel**: workspace returns to the original context. Mode returns to browse.
5. **Down**: no-op (position in target context is determined by MRU order).

State tracked:
- `movingWorkspaceId` — the workspace being moved
- `moveOriginContextId` — the context where the move started (for cancel/restore)

## App Launcher

The launcher opens a search panel for creating new windows. It scans configured directories for `.app` bundles and presents a filterable list sorted by MRU (most recently used) history.

### Trigger

`n` (plain, no modifier) in browse mode opens the launcher — regardless of whether the selected column is empty or has windows. The picker hides while the launcher is open.

### UI

- **Panel**: NSPanel (non-activating, borderless, popover material, 12pt corner radius). Width 500pt, dynamic height based on visible results (max 8 rows).
- **Search field**: NSTextField at top, placeholder "New window…", 14pt font. Receives focus on show.
- **App list**: table view below search field. Each row shows a 20×20 app icon and app name. Row height 36pt.
- **Position**: centered horizontally on screen, upper portion vertically (22% from top of visible frame).
- **Opacity**: uses the picker's `panel_opacity` config value.

### Filtering and sorting

- **Empty search**: shows up to 8 apps from MRU history.
- **With search text**: filters by case-insensitive substring match on app name. Results sorted by MRU rank first, then alphabetically.

### Selection

- **Keyboard**: up/down arrows navigate (wrapping), return/space confirms, escape cancels.
- **Mouse**: single click confirms.
- First result auto-selected when list changes.

### App launch

- **Already running**: activate the app, then try to press its "New Window" menu item via AX. If no such menu item exists, just activates.
- **Not running**: launch via `/usr/bin/open`.
- New windows are assigned to the active workspace implicitly — they appear on the current Space and get picked up by `listWindows()` on next picker show.

### MRU history

- Persists to `$WINDOWMAP_HOME/app-mru.json` as a JSON array of bundle IDs.
- Max 20 entries. On app selection, the bundle ID moves to position 0.
- Used for empty-search display and search result ranking.

### Lifecycle

The launcher opens as a modal overlay on the picker. The picker stays visible behind it with preview/wallpaper intact. The picker's mouse monitor is stopped and a `launcherActive` flag suppresses the resign-key handler (the launcher steals key window status). Event taps stay disabled.

- **Open**: stop picker mouse monitor, set `launcherActive`, launcher shows on top.
- **Cancel (escape)**: launcher hides, picker resumes (makeKey, reinstall mouse monitor, clear flag).
- **Confirm (app selected)**: launcher hides, picker dismisses (full cleanup — preview/wallpaper hidden, taps re-enabled). App launches.
- **Click outside**: launcher hides, picker dismisses (full cleanup).

### Config

```toml
[launcher]
paths = "/Applications,~/Applications,/System/Applications"
```

Comma-separated directories to scan for `.app` bundles. Scanned one level deep. App list cached for 60 seconds.

### Architecture

- `WindowMapCore/AppLauncher.swift`: `listApps(paths:)` scans directories, `AppMRU` manages history. No UI.
- `WindowMap/LauncherPanel.swift`: NSPanel with search field and table view. Thin UI shell.
- `WindowMapApp/PanelController.swift`: `onStartLauncher` callback, manages picker hide/re-show flow.

## Window Preview

When the picker is open, a preview panel shows a screenshot of the currently selected window. A wallpaper panel shows the desktop wallpaper behind the preview.

### Capture

Window screenshots use ScreenCaptureKit (`SCScreenshotManager.captureImage` with `SCContentFilter(desktopIndependentWindow:)`). The wallpaper is captured by finding the Dock's "Wallpaper-*" window via `SCShareableContent`.

Fallback for wallpaper: `NSWorkspace.desktopImageURL` loads the static desktop image when ScreenCaptureKit capture fails.

### Preview panel

An `NSPanel` (non-activating, borderless, floating) positioned at the window's actual screen location and size. Shows the captured screenshot. Ignores mouse events.

The border is configurable via `[preview]` in config:
- `border`: thickness in points (0 = no border)
- `border_radius`: corner rounding in points (0 = sharp)
- `border_curve`: `"circular"` or `"continuous"`

Color is always the macOS system accent color.

When the selection changes (keyboard or mouse), the preview updates:
- **Cache hit**: show immediately (no flicker)
- **Cache miss**: hide the preview, capture async, show when ready

The cache uses `NSCache` with a limit of 50 entries, keyed by `CGWindowID`. The limit is set high to avoid evictions during pre-warming — NSCache evicts under memory pressure anyway, and background re-captures add memory pressure that compounds with a low limit.

### Wallpaper panel

An `NSPanel` (non-activating, borderless, floating) covering the full screen. Shows the desktop wallpaper behind all preview content. Ignores mouse events.

The wallpaper is shown immediately from cache on picker show, then refreshed asynchronously. The cached image has a 30-second cooldown — refresh is skipped if less than 30 seconds since last capture.

When a context (tab) is focused in tabNav mode, only the wallpaper is shown (no window preview).

### Priority capture order

To feel fast, captures happen in priority order — the user is most likely to look at windows near their current focus:

1. **Focused window** — captured synchronously before the picker panel appears. This ensures the initial preview is instant.
2. **Current workspace** — windows in the same workspace as the focused window, in z-order.
3. **Other workspaces** — windows in other workspaces of the current context, in z-order.
4. **Other contexts** — windows in other contexts, in z-order.

Pre-warming runs asynchronously after the picker is visible, with a concurrency limit of 4 simultaneous captures. Pre-warming is cancelled when the picker is dismissed.

### Lifecycle

- **On show**: capture focused window → show wallpaper (cached) → show picker → refresh wallpaper async → pre-warm remaining windows in priority order
- **On selection change**: show preview (from cache or async capture)
- **On tab focus (tabNav)**: hide preview, show wallpaper only
- **On dismiss**: cancel pre-warming, hide preview, hide wallpaper
- **On full dismiss (toggle off)**: also clear the image cache

### Move

#### Window move (keyboard)

Move window: interactive phantom mode. Left/right picks target workspace. Enter confirms, escape cancels. Selection follows moved window to (target, 0). When there is only one workspace (column) and more than one context, `m` falls through to cross-context move (same as `shift+m`).

#### Window drag (mouse, within context)

Drag a **row** to move a window between workspaces in the same context. On drag start, the window enters move mode with a phantom at the target column. Drop confirms, escape cancels.

#### Window drag (mouse, cross-context)

Drag a **row** over a **tab** to move a window to another context. The context switches immediately on tab hover (no pause). The dragged window shows as a phantom in the new context at column 0. The user can move left/right to choose the target workspace. Drop confirms, escape or dragging back to the origin tab cancels (restores original context and position).

#### Workspace move (keyboard)

`shift+m` — see "Move workspace to another context" section.

#### Workspace drag (mouse, cross-context)

Drag a **column header** over a **tab** to move the entire workspace to another context. The context switches immediately. The workspace shows as a phantom column at position 0. Drop on the tab confirms. Moving left/right has no effect (position is determined by MRU order). Escape or dragging back to the origin tab cancels.

After each data action, the delegate mutates the data source directly and calls `panel.refresh()`. The Store is updated for persistence but not re-queried — column order stays locked from show time.

### Close window

When the delegate receives `closeRow(column, row)`:

1. **Remove from data source**: remove the window from `allWindows` and from the column's row list. Remove the window ID from Store. Call `panel.refresh()`.
2. **Update selection**: selection moves to `min(row, rowCount - 1)` — stays at the same index, or moves up one if the last row was deleted. If no rows remain, the column is now empty (no special behavior — the user can press the close key again to delete the empty workspace).
3. **Close the real window**: call `closeWindow(w)` which presses the AX close button (`kAXCloseButtonAttribute` press action) on the real window.
4. **Suppress panel resign**: set a suppress-resign flag for 0.3 seconds to prevent the panel from hiding when the AX close action temporarily steals focus.
5. **Post-close verification** (after 0.25 second delay): invalidate the window cache and re-check if the window still exists.
   - If the window is gone: bring the picker panel back to front.
   - If the window still exists (app rejected or showed a save dialog): hide the picker and focus the surviving window instead.
