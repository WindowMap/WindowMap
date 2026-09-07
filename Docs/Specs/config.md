# Config

Loads user configuration from a TOML file. All values are mandatory — the app exits on startup if any value is missing or invalid. Hot-reloads on file save without restart.

## File location

`$WINDOWMAP_HOME/config.toml`. A default config file with all values and comments is provided.

## Sections

### Global

| Key | Type | Description |
|-----|------|-------------|
| `log_level` | string | debug, info, warn, error |

### [picker]

| Key | Type | Description |
|-----|------|-------------|
| `trigger` | hotkey string | Global hotkey to open picker (e.g. "opt+space") |
| `quick_trigger` | hotkey string | Quick-cycle hotkey, "" to disable |
| `gesture` | string | Trackpad gesture to open picker: `"3-finger-up"`, `"3-finger-down"`, `"4-finger-up"`, `"4-finger-down"`. `""` to disable |
| `dismiss_gesture` | string | Trackpad gesture to dismiss picker. Same format. `""` to disable |
| `panel_opacity` | float | Picker panel opacity (0.0–1.0). Applies only to the picker panel, not other panels. |
| `show_plus_buttons` | bool | Show + buttons for new context/workspace/window |
| `centered` | bool | Center picker on screen at show time, then lock left edge. Columns grow right during session. When false, left edge starts at `panel_x` margin. |
| `panel_x` | float | Horizontal margin as fraction of screen width (0.0–0.5). The picker never extends into this margin on either side. |
| `panel_y` | float | Vertical position (0.0 = top, 0.5 = center, 1.0 = bottom). Anchors the panel's top edge. |
| `column_width` | float | Column width as multiple of row height. Row height adapts to screen size, so this works on any display. Default 5. |
| `min_height_rows` | int | Minimum visible rows — panel is always at least this tall even with fewer windows (default 3) |
| `max_height_rows` | int | Maximum visible rows — vertical scrollbar appears when a workspace has more windows (default 10) |
| `mru_order` | bool | true: contexts, workspaces, and windows ordered by most recently used (z-order). false: all three levels use Store insertion/creation order. |
| `click_outside` | string | Behavior when clicking outside the picker: `"confirm"` (focus selected window) or `"cancel"` (dismiss without action). Picker only. |

### [actions]

Action keys are single letters. Modifiers are applied automatically by the app based on context:
The default modifier→entity mapping is:
- Plain letter → acts on **window**
- Shift + letter → acts on **workspace**
- Cmd + letter → acts on **context**

This mapping is configurable via `[modifiers]` section (see below).

Convenience shortcuts (no modifier needed when intent is clear from context):
- Focus on tab strip → plain letter acts on context
- Focus on empty workspace → plain letter acts on workspace

| Key | Type | Description |
|-----|------|-------------|
| `rename` | key string | Rename action (default: "r") |
| `move` | key string | Move action (default: "m") |
| `new` | key string | New/create action (default: "n") |
| `close` | key string | Close action (default: "c") |
| `confirm` | key string | Confirm selection (default: "return,space") |
| `cancel` | key string | Cancel/dismiss (default: "escape") |

Comma-separated for multiple bindings: `confirm = "return,space"`

**Explicit overrides** — to override the automatic modifier pattern for a specific entity:

```toml
close = "c"              # c=close window, shift+c=close workspace, cmd+c=close context
close.workspace = "x"    # override: x=close workspace instead of shift+c
```

### [modifiers]

Configures which modifier key maps to which entity level. Default:

| Key | Type | Description |
|-----|------|-------------|
| `workspace` | modifier string | Modifier for workspace-level actions (default: "shift") |
| `context` | modifier string | Modifier for context-level actions (default: "cmd") |

Valid modifier values: `shift`, `cmd`, `ctrl`, `opt`.

### [navigation]

| Key | Type | Description |
|-----|------|-------------|
| `up` | key string | Navigate up |
| `down` | key string | Navigate down |
| `left` | key string | Navigate left |
| `right` | key string | Navigate right |

Comma-separated for multiple bindings: `up = "up,i"`

### [switcher]

| Key | Type | Description |
|-----|------|-------------|
| `trigger` | hotkey string | Switcher hotkey, "" to disable |
| `visible_rows` | int | Max visible rows before scrolling |
| `width` | float | Switcher panel width as fraction of screen width (e.g. 0.22 = 22%). |

### [launcher]

| Key | Type | Description |
|-----|------|-------------|
| `paths` | string | Comma-separated directories to scan for .app bundles |

### [preview]

| Key | Type | Description |
|-----|------|-------------|
| `cache_limit` | int | Max window captures held in memory per session. Cache clears on dismiss. |
| `border` | number | Border thickness in points. 0 = no border |
| `border_radius` | number | Corner rounding in points. 0 = sharp corners |
| `border_curve` | string | `"circular"` (standard arc) or `"continuous"` (macOS squircle) |

Border color is always the macOS system accent color (System Settings → Appearance → Color).

## Hotkey string format

Modifiers: `opt`, `cmd`, `ctrl`, `shift`. Keys: `a-z`, `0-9`, `space`, `return`, `tab`, `escape`, `up`, `down`, `left`, `right`.

Examples: `"opt+space"`, `"cmd+tab"`, `"ctrl+shift+k"`

## Parsing

Simple line-by-line TOML parser (no dependency). Supports:
- `[section]` headers
- `key = "value"` string values
- `key = 123` integer values
- `key = true/false` boolean values
- `# comments` (inline and full-line)

## Error handling

**Startup**: missing file or any missing/invalid value → log clear error message → exit.
**Hot-reload**: missing/invalid value → log warning with details → keep previous config.

## Hot-reload

Uses kqueue (`DispatchSource.makeFileSystemObjectSource`) to watch the config file. On file change:
1. Debounce 100ms (editors write in stages)
2. Parse the file
3. If valid: apply new config, log "config reloaded"
4. If invalid: log warnings, keep previous config

On file delete/rename: watch the directory, re-watch the file when it reappears.

## Translation to SpreadsheetKit

The app layer translates domain config to SpreadsheetKit's KeyBindings:

| Config (domain) | SpreadsheetKit (UI) |
|-----------------|---------------------|
| close (window) | closeRow |
| close (workspace) | deleteColumn |
| close (context) | deleteTab |
| new (workspace) | addColumn |
| new (context) | addTab |
| move (window) | moveRow |
| navigation.up | up |
| navigation.down | down |
| navigation.left | left |
| navigation.right | right |
| confirm | confirm |
| cancel | cancel |
