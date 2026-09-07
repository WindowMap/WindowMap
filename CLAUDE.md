# WindowMap

A macOS window picker triggered by global hotkey or trackpad gesture. Three-layer architecture: generic spreadsheet UI component, domain logic, thin app glue.

## Architecture

```
SpreadsheetKit (generic, no domain knowledge)
├── State machine: SpreadsheetState + SpreadsheetReducer (pure function)
├── Data protocol: SpreadsheetDataSource (consumer provides content)
├── Action output: SpreadsheetDelegate (consumer handles confirm/cancel/close/move)
├── Renderer: SpreadsheetView (state + data source → NSView hierarchy)
└── Panel: SpreadsheetPanel (NSPanel shell, keyboard/mouse → actions → state → render)

WindowMapCore (domain logic, no UI)
├── Store: context/workspace/window persistence
├── Window: CGWindowID, AX element, title normalization
├── Config: TOML parsing, load/reload, all values mandatory
├── HotkeyParsing: "opt+space" → key code + modifier mask
├── Log: per-module named loggers with level filtering
└── AppLauncher: listApps (directory scan), AppMRU (JSON persistence)

WindowMapApp (app logic, testable library)
├── WindowMapDataSource: maps Store → SpreadsheetDataSource (workspaces→columns, windows→rows)
├── PanelController: manages toggle, delegates data actions to Store, reloads data source
├── KeybindingTranslator: Config (domain) → KeyBindings (UI) with auto modifier pattern
├── KeyComboParsing: "shift+n" → SpreadsheetKit KeyCombo
└── Callbacks: onConfirm (focusWindow), onCloseWindow (AX close), onBeforeShow (invalidateCache)

WindowMap (executable, thin glue)
├── main.swift: config-driven startup, hotkey from config, ConfigWatcher
├── Windows.swift: listWindows, focusWindow, closeWindow, capture (system APIs)
├── Hotkey.swift: CGEvent tap registration (EventTapHandle for hotkeys + gestures)
├── TrackpadGesture.swift: trackpad gesture detection (cghidEventTap, background thread)
├── ConfigWatcher.swift: kqueue file watcher, hot-reload on save
├── PreviewPanel.swift: window preview with async capture + NSCache
├── WallpaperPanel.swift: desktop wallpaper capture
├── LauncherPanel.swift: app search + launch panel
├── WindowFocusTracker.swift: per-app AXObserver for focus tracking
└── URLHandler.swift: receives URLs from macOS, copies to clipboard, shows picker
```

## Data flow

```
State actions (navigation):
  keyDown → reduce(state, action) → new state → render(state, dataSource) → pixels

Data actions (add/delete/move):
  keyDown → delegate → mutate data source directly → update Store for persistence → refresh() → render
```

## Key design rules

- **State machine is pure.** No UI, no side effects. Takes state + action, returns new state. All behavior lives here.
- **Renderer is data-driven.** Given a state and a data source, it builds the entire view hierarchy from scratch. No incremental mutations.
- **SpreadsheetKit knows nothing about windows.** It sees tabs, columns, rows. The consumer provides meaning via the data source protocol.
- **Two action types.** State actions (navigate, select) go through the reducer. Data actions (add/delete column, move row) go through the delegate. The reducer never sees data actions.
- **Windows listed once per session.** `listWindows()` is called at show time, cached, and reused for all data actions during the session. Order stays stable.
- **Actions are input-agnostic.** An action (switch context, confirm, move) has one implementation. Keyboard and mouse both translate to the same action — the reducer/delegate doesn't know or care about the input source.
- **The app must always know where the user's focus is** — which context, workspace, and window. Actions follow the focus.

## Vocabulary

Each layer uses its own vocabulary. Never mix them in code:

- **WindowMapCore / WindowMapApp**: window, workspace, context, close, move, new
- **SpreadsheetKit**: row, column, tab, selection, phantom
- **macOS / System**: CGWindowID, AXUIElement, NSPanel

The translation happens in WindowMapApp (KeybindingTranslator, WindowMapDataSource, PanelController). SpreadsheetKit never imports WindowMapCore. WindowMapCore never references UI concepts.

| Domain | SpreadsheetKit | macOS |
|--------|----------------|-------|
| window | row | CGWindowID, AXUIElement |
| workspace | column | — |
| context | tab | — |
| close window | closeRow | AX close button |
| close workspace | deleteColumn | — |
| close context | deleteTab | — |
| new workspace | addColumn | — |
| new context | addTab | — |
| move window | moveRow | — |
| focus window | confirm | AX raise + activate |
| dismiss | cancel | — |

When naming variables, methods, comments, and log messages:
- In SpreadsheetKit: use `column`, `row`, `tab` — never `workspace`, `window`, `context`
- In WindowMapCore: use `workspace`, `window`, `context` — never `column`, `row`, `tab`
- In WindowMapApp: domain vocabulary in public API, UI vocabulary only when talking to SpreadsheetKit

## Testing layers

| Layer | What | How |
|-------|------|-----|
| State machine | All mode transitions, navigation, selection | Unit tests: action → assert state |
| Renderer | Visual output for every state | Universal invariant tests via Mode.allCases + mode-specific tests |
| Integration | Panel + state + view wiring | Panel tests: apply action → assert state + view |
| Data source | Store → data source mapping | Unit tests: workspace columns → assert labels/icons |
| Toggle | PanelController lifecycle | Unit tests: show/dismiss/data actions |

## SPM targets

| Target | Type | Dependencies |
|--------|------|-------------|
| `SpreadsheetKit` | library | none |
| `WindowMapCore` | library | none |
| `WindowMapApp` | library | SpreadsheetKit, WindowMapCore |
| `WindowMap` | executable | SpreadsheetKit, WindowMapCore, WindowMapApp |
| `SpreadsheetKitTests` | executable | SpreadsheetKit |
| `WindowMapTests` | executable | SpreadsheetKit, WindowMapCore, WindowMapApp |

## Development modes

### Dev mode (daily development)

Runs the debug binary directly. Config and state in `.dev/`, logs to `.dev/windowmap.log`.

```sh
make test          # run all tests
make build         # debug build
make start         # start daemon (WINDOWMAP_HOME=.dev)
make stop          # stop daemon
make restart       # stop + start
make status        # check if running
make clean         # clean build artifacts
```

Permissions (Accessibility, Screen Recording) are granted to the debug binary at `.build/debug/WindowMap` and persist across rebuilds.

### Prod mode (install as app)

Builds a release `.app` bundle, installs to `/Applications/`, starts via launchd. Config at `~/.config/windowmap/`, logs to `~/Library/Logs/windowmap.log`.

```sh
make install       # build, sign, install .app, start LaunchAgent
make uninstall     # stop, remove .app and LaunchAgent
make state-to-prod # copy .dev/*.json → ~/.config/windowmap/
make state-to-dev  # copy ~/.config/windowmap/*.json → .dev/
make status        # show both dev and prod status
```

Every install replaces the binary with a new ad-hoc signature, which **invalidates macOS permissions**. The user must re-grant Accessibility and Screen Recording after each install. Only use for final testing — not during active development.

**Single-instance guard**: `flock` on a shared lock file ensures only one instance runs at a time — dev or prod. A second instance logs an error and exits immediately. No manual stop/start needed when switching modes; `make install` and `make start` will fail if another instance holds the lock.

### What can't be tested in dev mode

- **URL handler** (default browser) — requires a `.app` bundle with Info.plist registered by macOS. Use `make install` to test.
- **LaunchAgent** (auto-start, crash recovery) — only active in prod mode.

### Debugging

Logs go to stderr, redirected by the environment:
- Dev: `.dev/windowmap.log` (`tail -f .dev/windowmap.log`)
- Prod: `~/Library/Logs/windowmap.log`

Debug with logs, not blind changes. **Never attempt a fix without first confirming the root cause via logs.** The only exception is when the bug and fix are 100% obvious from reading the code. When in doubt, log first.

Flow: add logging → `make restart` → confirm "running" → ask user to trigger → read logs → understand root cause → fix.

Always verify the binary was rebuilt (check build output shows compilation, not just `0.08s`). Default log level is `info`, overridden by config `log_level`. Set to `debug` for verbose output.

**Never report a fix or feature as done without verification.** At minimum: `make build` (zero errors, zero warnings) + `make test` (all pass). For UI changes, `make restart` and visually confirm. Never ask the user to test something that doesn't compile.

All commands require running outside the Claude Code sandbox (`dangerouslyDisableSandbox: true`).

Always use `make` targets — never run `swift build`, `swift package`, or test binaries directly. The Makefile handles environment setup, log redirection, and process management.

Zero warnings policy: fix all compiler warnings before committing — in all targets, including tests. Warnings are treated as bugs.

Always use the `Log` framework (`import Logging`) for output — never `print`, `fputs`, `NSLog`, or `debugPrint`. Logger convention: always name the logger `log` (`private let log = Log(module: "...")` or instance property). The only exception is `main.swift` which uses `appLog` to avoid global namespace collision.

## Instructions

Always implement exactly what the user asks and nothing more.

Do not add `Co-Authored-By` lines to commit messages.

### Spec-driven development

Follow this strictly for every change — features, bug fixes, improvements, refactors:

1. **Spec first**: update or create the relevant spec in `Docs/Specs/`. If a spec change is not needed (pure implementation detail), explicitly decide to skip it — do not silently skip.
2. **Test second**: write tests that verify the spec before writing implementation code.
3. **Implement third**: write code to pass the tests.
4. **Verify**: run tests, build the app, verify visually if needed.

**This flow is non-negotiable.** The only exception is a conscious, explicit decision to skip (e.g., a one-character typo fix) — stated out loud before proceeding.

### Discuss before implementing

For features and design changes: present the proposal, ask questions, wait for confirmation before writing code. The pattern is "grill me with docs" — lay out the design, flag open questions, get answers, then implement. Never skip the discussion and jump to implementation. Ask one question at a time, interview style — not a batch of questions.

### Config rules

- Never cache config values at init — always read from the live `Config` object so hot-reload takes effect.
- `Resources/config.toml.example` and `.dev/config.toml` must stay in sync (same comments, same structure). Values may differ (dev vs prod defaults).
- Config comments must be self-documenting: clear what each value does, what values it accepts, with examples where helpful.

### Code style

- **Split long functions**: when a function grows beyond ~30 lines or has clearly separable phases, extract each phase into a well-named sub-function. The high-level function should read as a pipeline where each step's purpose is obvious from the name. Low-level details live in each sub-function.
- **Fix structurally, not individually**: when finding and fixing bugs, look for the general pattern and make the whole category impossible — don't just patch the specific case. Before writing a fix, ask: "Can another code path hit the same bug?" If yes, find the choke point where the invariant can be enforced once.

## Lessons

Patterns that caused bugs:

- **Weak data source deallocated in tests**: `weak var dataSource` was released when tests discarded the reference. Always keep a strong reference alive in test scope.
- **Quick tap swallows navigation keys**: CGEvent tap for quick trigger consumed the key even when the picker was open. Fix: disable() skips keyDown matching but preserves modifier tracking for confirm-on-release.
- **Layout reads stale state after data mutation**: `setColumns` updates the data source but `state.columns` isn't synced until `panel.refresh()`. Layout methods (`relayout`, `layoutForState`) must read from the data source, never `state.columns`, for sizing calculations.
- **hitTest must check region before computing index**: hitTest used a single formula for header and row areas, relying on the sign of a float division to distinguish them. `Int()` truncation toward zero collapsed small negatives into row 0. Fix: explicitly check which region the point is in (`guard point.y < contentTop`) before computing the row index.
- **CGWindowID reuse causes stale custom titles**: macOS reuses window IDs. Persisted custom titles keyed by windowId were inherited by new windows. The `remapIds` bundleId mismatch check handles cross-app reuse (removes the entry). Same-app reuse is rare and self-corrects when the old entry is pruned after 30 days. No separate custom title clearing step — over-eager clearing caused data loss.
- **Data source holds struct copies**: workspace/window objects in the data source are value types — updating the Store doesn't update the data source copies. Rename must update both the Store and the data source in-place. Never reload from Store mid-session just to update a name — that rebuilds MRU order and disrupts the display.
- **Empty window list corrupts state**: during macOS space transitions, `listWindows()` may return 0 windows. If `update()` runs with empty `liveIds`, `applyRemap` strips all window assignments from workspaces. Fix: skip `update()` entirely when no windows are reported. Additionally, `applyRemap` never drops windowIds — only remaps them. Stale IDs are kept in workspaces harmlessly and filtered by `groupCurrentWorkspaces` when displaying.
- **HID event taps silently die after sleep/wake**: on ad-hoc signed apps, macOS re-evaluates trust for `cghidEventTap` after wake. The `CFMachPort` stays valid, the run loop keeps running, but events stop. `CFMachPortIsValid` cannot detect this. Recreating taps in the same process doesn't help after unclean power events (battery death) — macOS blocks HID trust at the process level. Fix: process exits immediately on wake (`didWakeNotification`), launchd `KeepAlive` restarts it (~100ms) with fresh HID trust. Keyboard triggers also unconditionally recreate gesture taps (`ensureGestureTaps`) as a secondary recovery layer for non-wake failures.
- **Gesture tap callback fires during destruction**: when `ensureGestureTaps` destroys an old tap, macOS sends `tapDisabledByUserInput` to the dying callback. Re-enabling a dying tap causes macOS to throttle HID input, producing system-wide lag. Fix: check `destroyed` flag at the top of the gesture callback — if set, return immediately without re-enabling.

## Current status

Packaged as `WindowMap.app` (LSUIElement — no dock icon). Installed to `/Applications/` with a LaunchAgent (`org.windowmap`) for auto-start. `ProcessType: Interactive` prevents launchd throttling. `KeepAlive` restarts on crash. Ad-hoc codesigned. Requires Accessibility permission (hotkeys) and Screen Recording (window previews, optional). `WINDOWMAP_HOME` defaults to `~/.config/windowmap` when not set. Logs to `~/Library/Logs/windowmap.log` (prod) or `.dev/windowmap.log` (dev).

URL handler: registered for `http`/`https` schemes via `CFBundleURLTypes` and `public.html` document types via `CFBundleDocumentTypes`. When macOS sends a URL (e.g., clicking a link while WindowMap is the default browser), the URL is copied to clipboard and the picker shows with a URL bar above the tab strip. The user selects a window and pastes manually. Local file opens (e.g., VPN SAML pages) are handled the same way — file URL copied to clipboard, picker shown. `NSApplicationDelegate.application(_:open:)` intercepts file events; `kAEGetURL` handles URL events.

All keybindings from `$WINDOWMAP_HOME/config.toml` — no hardcoded values. Config hot-reloads on save.

Panel shows real windows grouped by workspace (Store), with app icons. Window assignments persist across sessions via JSON files. Initial selection targets the focused window's actual position in the data source.

Data actions: action letter + modifier pattern (plain=window, shift=workspace, cmd=context). Default: n=new, c=close, m=move, r=rename. State/data action split: navigation is pure (reducer), data actions mutate data source directly and update Store for persistence. Store is not re-queried mid-session — column order locked from show time.

Screen-adaptive sizing via LayoutConfig: row height, header height, tab strip height, icon size, font sizes, and column width all derived from screen dimensions at show time. `column_width` (multiplier of row height, e.g. 5) controls column width — adapts to any screen automatically. Font sizes are proportional to row height (row labels ×0.31, headers/tabs ×0.28, plus button ×0.38). LayoutConfig.forScreen() computes all proportional values.

Panel sizing from config: `min_height_rows`/`max_height_rows` control vertical size (scrollbar on overflow). Panel width = `min(columns × columnWidth, availableWidth)` — grows with content, fills exact margin bounds when columns overflow (last column clipped). `panel_opacity` sets picker transparency. `mru_order` controls ordering of contexts, workspaces, and windows — true for z-order (MRU), false for creation/insertion order. Switcher is always MRU regardless. All config values mandatory, no hardcoded defaults.

Panel position from config: `centered` (bool) centers picker on screen at show time using the widest context's column count (max across all tabs), then locks left edge — position is stable regardless of which context is active. When false, left edge starts at `panel_x` margin. `panel_x` (float, 0.0–0.5) is a symmetric horizontal margin — the picker never extends into this margin on either side. `panel_y` anchors the top edge (0.33 = upper third). Panel extends downward from anchor point. Both axes clamp to screen bounds.

Panel width and height adjust dynamically on tab switch and column add/remove via `relayout()` (top edge and left edge stay fixed). Horizontal scrolling: columns inside OverlaidScrollView with legacy scroller + auto-hide; keyboard navigation scrolls selected column into view. Tab strip in its own scroll view with chevron indicators (‹ ›) for overflow. Smart tab sizing: dynamic widths based on label text, shrink-to-fit for widest tabs first, min width 52pt.

Rename mode: inline NSTextField editor overlaid on target item. `r` = rename window (custom title), `shift+r` = rename workspace, `r` in tabNav = rename context. Enter commits, escape cancels. Standard editing shortcuts (Cmd+A/C/V/X/Z) via local key monitor. `sendEvent` bypasses action routing in rename mode. Custom window titles queried from Store via `titleLookup` closure — always from the source of truth.

Panel dismisses on focus loss (`NSWindow.didResignKeyNotification`), guarded by `suppressResignUntil` during close-window AX calls. `click_outside` config: `"confirm"` (focus selected window then dismiss) or `"cancel"` (dismiss without action). Always dismisses — no window selected falls back to cancel.

Tab switching: `tab_switch` config — `"click"` switches context on click, `"hover"` (default) switches on mouse hover with configurable `tab_hover_delay` (ms, default 100). Hover uses a timer with stickiness — cursor must stay on the tab for the delay duration before switching. Cancels if cursor leaves.

Window preview: on picker show, focused window captured BEFORE panel appears (async capture via `toggleAsync`). Picker, wallpaper, and preview all appear simultaneously — no flash. Always uses the async path — `CGPreflightScreenCaptureAccess()` can return false even when captures work, so we skip the check. Remaining windows pre-warmed in priority order. Preview panel shows at window's actual screen position. Wallpaper panel shows desktop behind preview. Cache (NSCache, configurable `cache_limit`, one capture per session) cleared on dismiss. Configurable border: `[preview] border` (points), `border_radius` (points), `border_curve` (`"circular"` or `"continuous"`). Color is macOS system accent, read fresh at show time.

App launcher: `n` (plain) opens search panel for launching apps. Scans `[launcher] paths` from config, cached 60s. MRU history (max 20, persisted to `app-mru.json`) drives empty-search display and search ranking. Running apps get "New Window" via AX menu press; new apps launched via `/usr/bin/open`. Picker stays visible when launcher opens as modal overlay — preview/wallpaper stay intact. `launcherActive` flag suppresses picker's resign-key handler. Escape re-shows picker (resume). Click outside or confirm dismisses picker (full cleanup). `windowDidResignKey` handles click-outside dismiss, guarded by `panel.isVisible` to prevent spurious dismiss when escape hides the launcher first. Selection follows mouse hover.

Move workspace: `shift+m` moves entire workspace (with windows) to another context. Enters moveTabNav directly, phantom column shows at position 0 (MRU: move counts as use). Confirm moves workspace, cancel restores. Click on tab switches context (no hover). Mouse drag moves windows between columns (same action path as keyboard move).

Cross-context drag: drag a row over a tab to move a window to another context; drag a column header over a tab to move the workspace. Context switches immediately on tab hover (no delay). Reuses existing delegate methods (`switchMoveTab`, `descendFromMoveTabNav`, `confirmMoveTab`). Cancel (escape) during drag restores original context. mouseUp after cancelled drag is a no-op (`mouseDownActive` flag).

Quick mode: `quick_trigger` (e.g. `opt+tab,opt+k`) opens picker, auto-advances to next window (MRU only — no advance when `mru_order = false`), confirm on modifier release. Navigation identical to browse mode (arrow keys, tab switching between contexts). `quickSession` flag is the sole discriminator — no separate Mode.quick; quick sessions use `.browse` mode throughout. Modifiers stripped for key matching. Data actions blocked. Supports comma-separated multiple trigger combos. Event tap disable/enable preserves modifier tracking for confirm-on-release.

Switcher: `[switcher] trigger` (e.g. `cmd+tab`) opens flat MRU window list. Always quick mode — cycle on trigger repeat, confirm on modifier release. Standalone panel (not SpreadsheetKit), shared preview/wallpaper panels, configured navigation keys, bold custom titles. `width` (fraction of screen width) controls panel width. Font size proportional to row height (×0.38).

Multiple hotkey support: browse, quick, and switcher taps coexist. Opening any panel disables all taps (trigger keys still swallowed to prevent system shortcuts). Dismiss re-enables all. Each trigger hot-reloadable.

Trackpad gestures: `gesture` (e.g. `"3-finger-up"`) opens picker, `dismiss_gesture` (e.g. `"3-finger-down"`) dismisses. Uses `cghidEventTap` (HID level, `.listenOnly`) on a dedicated background thread. Monitors multi-finger swipes (3 or 4 fingers, up or down). Open gesture self-gates (no-op when picker is visible) and warps the mouse cursor to the selected row. Dismiss gesture stays active while picker is open. Both hot-reloadable. Three recovery layers: (1) run-loop exit recovery — background thread retries `CGEvent.tapCreate` every 2s, (2) wake restart — process exits immediately on `didWakeNotification`, launchd restarts (~100ms) with fresh HID trust, (3) keyboard-triggered refresh — every keyboard trigger unconditionally recreates gesture taps via `ensureGestureTaps()`.

Right-click context menu: right-click selects element and shows domain-specific NSMenu. SpreadsheetKit reports target via `spreadsheetDidRightClick(target:)`, PanelController builds menu. Menu items per target: window row (close/rename/new), workspace header (close if empty, rename, new workspace, new window), context tab (close if deletable, rename, new), empty tab strip (new context). Blocked during quick sessions and rename mode. Menu actions reuse existing delegate methods — no separate logic.

Window focus tracking: per-app `AXObserver` for `kAXFocusedWindowChangedNotification` keeps active context/workspace in sync with the focused window while the picker is hidden. Debounced 100ms. Also updates current macOS space on focus change. `Store.setActiveFocus(windowId:)` finds context+workspace atomically. Observers added/removed as apps launch/terminate. Exits on Accessibility permission revocation to prevent broken event taps.

Specs organized in `Docs/Specs/` with Component/Behavior grouping (spreadsheet-kit, store, config, app-lifecycle, window-picker). 247 tests passing.

Right-click context menu: right-click selects element and shows domain-specific NSMenu. SpreadsheetKit reports target via `spreadsheetDidRightClick(target:)`, PanelController builds menu. Menu items per target: window row (close/rename/new), workspace header (close if empty, rename, new workspace, new window), context tab (close if deletable, rename, new). Blocked during quick sessions and rename mode. Menu actions reuse existing delegate methods — no separate logic.

### Release

Published as `WindowMap/WindowMap` on GitHub. Homebrew cask in `WindowMap/homebrew-windowmap`. Git identity: `WindowMap <281489377+WindowMap@users.noreply.github.com>`. Dev branch (`dev`) has full history; `master` has a single squashed commit per release. Only `master` is pushed to GitHub.

Release flow: update `master` from `dev` (orphan commit), tag `v1.0.0`, push. GitHub Actions (`.github/workflows/release.yml`) builds a universal binary (arm64 + x86_64), packages `.app` bundle, ad-hoc signs, uploads tarball. Update cask SHA256 in `homebrew-windowmap`.

Install: `brew tap WindowMap/windowmap && brew trust windowmap/windowmap && brew install --cask windowmap`.

### TODO

See `Docs/TODO.md`.
