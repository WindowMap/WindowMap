# App Lifecycle

The app runs as a background daemon with multiple global hotkeys for the picker, quick picker, and switcher.

## Daemon mode

The app sets activation policy to `.accessory` — no dock icon, no menu bar. It stays alive after panels are dismissed, waiting for the next hotkey press.

## Hotkeys

### Event tap architecture

Each trigger gets its own `EventTapHandle` — a CGEvent tap (`cgSessionEventTap`, `headInsertEventTap`, `.defaultTap`). Events monitored: `keyDown` and `flagsChanged`.

- Matching `keyDown` events are **swallowed** (return nil — the keypress never reaches other apps)
- Non-matching events pass through
- Auto-recovers from timeout/user-input disabling

### Event tap disable/enable

`disable()` sets `isEnabled = false`. The callback checks `isEnabled` only for `keyDown` matching:
- **Disabled**: keyDown events pass through (not swallowed), but the callback still fires. `flagsChanged` events continue to be handled — this preserves modifier-up tracking for confirm-on-release.
- **Enabled**: keyDown events are matched and swallowed normally.

### Multiple hotkey coordination

Opening any panel disables all other taps. Closing re-enables all. Only one panel can be active at a time.

| Event | Action |
|-------|--------|
| Browse trigger fires | Disable quick tap, switcher tap |
| Quick trigger fires | Disable browse tap, quick tap, switcher tap |
| Switcher trigger fires | Disable browse tap, quick tap |
| Any panel hides | Re-enable all taps |

### Requirements

CGEvent taps require accessibility permissions. The app checks on launch and shows the system dialog if not granted.

## Browse trigger

The main hotkey (e.g. `opt+o`). Opens the picker in browse mode.

| Panel state | Hotkey pressed | Result |
|-------------|---------------|--------|
| hidden | trigger | show picker with fresh window list |
| visible | trigger | dismiss picker |

## Quick trigger

A second hotkey (e.g. `opt+tab`). Opens the picker in quick mode — cycle through windows, confirm on modifier release.

### Quick mode flow

1. **First press** (`opt+tab`): picker opens with the focused window selected. When `mru_order = true`, auto-advances to the next window (skip focused, select previous). When `mru_order = false`, stays on the focused window. The event tap is disabled (keyDown passes through but callback still fires).
2. **Subsequent presses** (holding opt, press tab again): when `mru_order = true`, cycles selection to the next window. When `mru_order = false`, no cycle (repeat presses are no-ops).
3. **Modifier release** (release opt): `flagsChanged` detects the modifier is no longer held → confirms the selected window (focus + dismiss).
4. **Race condition guard**: after `show()` completes, immediately check if the modifier is still held. If the user tapped and released faster than `flagsChanged` could fire, confirm immediately.

### Quick mode navigation

Navigation in quick mode is identical to browse mode — arrow keys move between rows, columns, and tabs. The only differences from browse mode are: confirm-on-release, no data actions (rename, move, close, new).

## Switcher trigger

A third hotkey (e.g. `opt+s`). Opens the switcher — a flat list of ALL windows sorted by MRU. Always operates in quick mode.

### Switcher flow

1. **First press**: switcher opens showing all windows in z-order (MRU). Skips focused window, selects next.
2. **Subsequent presses**: cycles to next window.
3. **Modifier release**: confirms.
4. **Race condition guard**: same as quick mode.
5. **No windows**: don't show the switcher at all.

### Switcher UI

- Standalone NSPanel (not SpreadsheetKit) — single column flat list
- Each row: app icon + window title (bold for custom titles, regular for native)
- No tabs, no workspace headers, no context navigation
- No actions (rename, move, close, new)
- Navigation: up/down, mouse hover selects, click confirms
- `visible_rows` config controls max visible rows before scrolling
- Shares preview/wallpaper panels with the picker

### Switcher config

```toml
[switcher]
trigger = "opt+s"
visible_rows = 8
width = 0.22
```

## Show flow (all modes)

1. Invalidate the window cache
2. Call `listWindows()` for fresh results
3. Cache the window list for the session
4. Capture focused window (async, before panel appears — like browse mode)
5. Update Store, build state, set initial selection to the focused window's position, show panel
6. Show wallpaper + preview
7. Pre-warm remaining window captures

## Dismiss flow

Dismiss happens on:
- Hotkey press while panel is visible (browse trigger only)
- Escape key
- Confirm action (focus selected window)
- Modifier release (quick mode / switcher)
- Dismiss gesture (trackpad)
- Panel loses key window status (unless suppressed during drag, close-window, or launcher modal)
- Launcher confirm or click outside (dismisses picker from suspended state)

On dismiss: panel orders out, preview dismissed (50ms delay), wallpaper hidden, all taps re-enabled.

### Launcher modal

The app launcher opens as a modal overlay on the picker. The picker stays visible behind it (preview/wallpaper intact). During the launcher session:

- Picker's mouse monitor is stopped (`suspendForLauncher`)
- `launcherActive` flag suppresses the picker's resign-key handler
- Event taps stay disabled

Exit paths:
- **Escape**: launcher hides, picker resumes (`resumeFromLauncher` — makeKey, reinstall mouse monitor, clear flag)
- **Confirm**: launcher hides, picker dismisses (`dismissFromLauncher` — full cleanup)
- **Click outside**: launcher's `windowDidResignKey` fires → same as confirm (dismiss all). Guarded by `panel.isVisible` to prevent spurious dismiss when escape hides the launcher first.

## Trackpad gestures

Two configurable gestures: one to open the picker, one to dismiss it.

### Config

```toml
[picker]
gesture = "3-finger-up"
dismiss_gesture = "3-finger-down"
```

Format: `{N}-finger-{direction}` where N is 3 or 4, direction is `up` or `down`. Set to `""` to disable.

### Implementation

Gesture taps use `cghidEventTap` (HID level) with `.listenOnly` (never swallows events — gestures pass through to macOS). They run on a dedicated background thread with their own run loop.

The tap monitors `.gesture` events (CGEvent type 29). For each event:
1. Count active touches matching the configured finger count
2. Track starting positions per touch
3. Compute average vertical distance from start
4. If distance exceeds threshold (`0.04`) in the configured direction, and horizontal drift is below threshold (`0.1`), trigger fires
5. Reset on touch end (finger count drops to 0)
6. Ignore if more fingers than configured touch down (prevents 3-finger gesture from firing during 4-finger swipe)

### Open gesture

When the open gesture fires:
1. Disable all taps (same as hotkey triggers)
2. Show the picker in browse mode
3. Warp the mouse cursor to the center of the selected row (initial selection only — subsequent keyboard navigation does not move the cursor)

### Dismiss gesture

When the dismiss gesture fires:
- Dismiss the picker if visible
- Does NOT disable other taps

### EventTapHandle

Gesture taps reuse `EventTapHandle` with an additional `runLoop` property for the background thread. `destroy()` stops the background run loop. `disable()`/`enable()` work the same — the gesture callback checks `isEnabled`.

### Resilience

HID-level event taps can silently stop receiving events after sleep/wake on ad-hoc signed apps (macOS re-evaluates trust). The tap's `CFMachPort` may still appear valid, the run loop keeps running, but no events are delivered. Recreating taps in the same process doesn't help after unclean power events (battery death) — macOS blocks HID trust for the entire process.

Two recovery mechanisms:

1. **Wake restart**: on `NSWorkspace.didWakeNotification`, the process exits immediately. Launchd's `KeepAlive` restarts it (~100ms) with fresh HID trust. This is the primary recovery — it handles all wake scenarios including unclean power events (battery death). Recreating taps in the same process is insufficient: macOS blocks HID trust at the process level after certain power events, so only a fresh process recovers. All state is persisted to JSON, so nothing is lost across the restart.

2. **Keyboard-triggered refresh**: every keyboard trigger (browse, quick, switcher) unconditionally destroys and recreates gesture taps via `ensureGestureTaps()`. This covers cases where taps die between wakes (secondary recovery layer).

## Custom titles

Windows with custom titles (set via rename) are displayed with **bold font** in both the picker and switcher. Native titles use regular font. Custom titles are queried from the Store via `titleLookup` closure — always from the source of truth.

## URL handler

The app registers as a handler for `http`/`https` URL schemes (`CFBundleURLTypes`) and `public.html` document types (`CFBundleDocumentTypes`) in Info.plist. This makes WindowMap appear in the macOS default browser picker.

### Web URLs

When macOS sends a web URL (e.g., the user clicks a link while WindowMap is the default browser):

1. Copy the URL to the system clipboard
2. Show the picker with a URL bar displaying the URL

The user selects a window and pastes manually. WindowMap does not open the URL itself — it's a routing mechanism, not a browser.

### Local files

When macOS sends a local file (e.g., VPN SAML auth opening `/tmp/file.html`), it is handled the same as a web URL: the file URL is copied to clipboard and the picker shows with a URL bar.

### URL bar

When the picker is opened via URL handler, a thin bar appears above the tab strip showing the URL or file path. It is not shown on normal hotkey/gesture opens. Cleared on dismiss.

## Lifecycle summary

```
App launch → flock single-instance guard → check AX permission → register hotkeys + gestures + focus tracker + URL handler → wait
  ↓ browse trigger / URL received
show picker (browse mode) → data actions → confirm/cancel → dismiss → wait
  ↓ quick trigger
show picker (quick mode) → cycle on repeat press → confirm on modifier release → dismiss → wait
  ↓ switcher trigger
show switcher (quick mode) → cycle → confirm on release → dismiss → wait
  ↓ new window action (n key)
suspend picker → show launcher (modal) → escape (resume) / confirm (dismiss) / click outside (dismiss) → wait
  ↓ system wake (didWakeNotification)
exit(0) → launchd restarts (~100ms) → App launch (fresh HID trust)
```
