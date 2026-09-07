# Store

Persists window-to-workspace assignments across sessions. Manages the workspace hierarchy and resolves live windows to their assigned workspaces.

## Data model

```
Store
└── [Context]
    ├── id: UUID
    ├── name: String
    └── [Workspace]
        ├── id: UUID
        ├── name: String
        ├── windowIds: [UInt32]   (ordered list of CGWindowIDs)
        └── isAutoNamed: Bool     (computed: name matches Workspace\d+)
```

One context is active at a time. The active context determines which workspaces are visible as columns in the panel.

`Workspace.isAutoNamed` is the single source of truth for whether a workspace has a default name (`Workspace0`, `Workspace1`, etc.). Auto-named workspaces carry no user data beyond their windows — they are disposable when empty.

A context is **deletable** when it is not the last context AND all its workspaces are empty (no windowIds).

A `WindowEntry` tracks metadata for each known window:
- `windowId: UInt32`
- `title: String`
- `bundleId: String?`
- `customTitle: String?` (user-assigned, preserved across ID changes)
- `frame: [Int]?` (last known screen position and size: [x, y, w, h])
- `lastSeenAt: Date?`

## Default state

When no persisted data exists, the Store starts with one Context named "Context0" containing one Workspace named "Workspace0". All live windows are assigned to this workspace. This context is the active context.

## Window ingestion

`update(windows: [Window])` reconciles live windows with persisted entries. This is the core algorithm that preserves workspace assignments even when CGWindowIDs change (which happens on app restart, window recreation, etc.).

### 4-step ID remap

1. **Direct match**: a live window's ID matches an existing entry's ID, and bundleIds agree. Update the entry's title, frame, and lastSeenAt.

2. **Title + bundleId match**: for orphaned entries (not matched in step 1, not on other spaces) and unmatched live windows, match by (title, bundleId) key. Only when both sides have exactly one candidate — ambiguous matches are skipped.

3. **BundleId-only match**: for remaining orphans and unmatched windows, match by bundleId alone. Only 1:1 unique matches.

4. **Frame match**: for remaining orphans and unmatched windows, match by exact screen frame (position + size) and bundleId. Only 1:1 unique matches. Helps when multiple windows of the same app share the same title but have different positions (e.g. tiled windows). No effect when all windows are maximized (same frame).

### After remapping

- Remap windowIds in all workspaces: keep live or remapped IDs, drop stale ones.
- Create fresh entries for still-unmatched live windows.
- Prune entries not seen in 30 days (custom titles are pruned with their entries — no separate clearing step).
- Append unassigned live windows to the **active workspace**.

## Update and group

`updateAndGroup(windows: [Window]) -> [(Workspace, [Window])]`

Updates stored state with live windows (ingestion + ID remap), then returns one pair per workspace in the **active context**. Each workspace's windows are filtered to only those currently live, in z-order (matching the input array order). Workspaces from other contexts are not included in the result.

### MRU ordering

Workspaces are ordered by recency: the workspace containing the frontmost window (first in the input array) comes first. This means the most recently used workspace is always the leftmost column.

## Workspace operations

All workspace operations act on the **active context**.

- `addWorkspace(name:) -> UUID` — insert a new empty workspace in the active context
- `removeWorkspace(id:)` — remove a workspace from the active context. Cannot remove the last one.
- `renameWorkspace(id:, name:)` — rename a workspace in the active context

## Context operations

- `contexts() -> [Context]` — returns all contexts in the active space
- `activeContextIndex() -> Int` — index of the active context in `contexts()`
- `setActiveContext(index:)` — switch which context is active. The active context determines which workspaces are returned by `workspaces()` and `updateAndGroup()`.
- `addContext(name:)` — create a new context with one default empty workspace. Auto-generated names follow the pattern "Context0", "Context1", etc., skipping names already in use.
- `deleteContext(index:)` — delete a context. Guard: cannot delete the last context. Unassigns all windows in the context's workspaces before deleting. If the deleted context was active, the store activates an adjacent context (next, or previous if deleting the last).
- `renameContext(index:, name:)` — rename a context

## Window operations

- `moveWindow(_: UInt32, toWorkspace: UUID)` — remove window from its current workspace and append to the target workspace. Takes a workspace ID (not index) to avoid coupling with visual ordering.
- `removeWindow(_: UInt32)` — remove a window ID from all workspace lists in the current space. Used when a window is closed via the picker.
- `title(for: UInt32) -> String?` — get custom title if set
- `setTitle(_: String?, for: UInt32)` — set or clear a custom title for a window. Nil removes the custom title.

## Focus tracking

- `setActiveFocus(windowId:)` — find the context and workspace containing the given window and set both as active. No-op if already focused on that context/workspace. Called by the AX focus tracker when the user switches windows outside the picker.
- `setSpace(_: Int)` — switch the active macOS Space. Each Space has its own set of contexts. Called on focus change and at picker show time to ensure the correct Space is active.

## Persistence

Two file types in `~/.config/windowmap/`:

- `windows.json` — all WindowEntry records (global, shared across spaces)
- `space-{id}.json` — per-macOS-Space: contexts, active context/workspace IDs, lastSeenAt

Saves are debounced by 0.5 seconds. Spaces not seen in 30 days are pruned on save.

