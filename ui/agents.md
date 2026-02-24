# ui — Package Agent Notes

## Purpose

The `ui` package owns every visual and interactive element of the editor: windows, floating panels, options menus, tools, and command terminals. It is the only package that imports a rendering backend (`vendor:raylib`). All other packages (`raytrace`, `util`) are pure data/compute and must never import `ui` or any GUI library.

---

## Rendering Backend & Modularity

The current backend is **Raylib** (`vendor:raylib`, aliased as `rl`). The package is written so that swapping backends in the future requires changes only inside `ui/` — no other package will need to change.

### Rules to preserve backend independence

1. **Never expose Raylib types across the `ui/` boundary.** The public API of `run_app` takes only `^rt.Camera`, `[dynamic]rt.Object`, `int`, and `util` types. `rl.Rectangle`, `rl.Vector2`, etc. stay internal.
2. **Name abstractions after their UI concept, not their Raylib call.** Draw a "panel border", not a "DrawRectangleLinesEx". If a proc name is just a thin wrapper around one Raylib call today, that is acceptable — the naming still signals intent.
3. **Keep all Raylib calls in `ui/*.odin` files.** If a future backend is added (e.g. Dear ImGui, a custom renderer), the swap is done by replacing or gating the draw calls in those files, not by hunting through other packages.
4. **Backend-specific constants live in `ui/ui.odin`** (colors, sizes). Keep them there; do not scatter magic color literals into panel files.

---

## Composition Model

Everything in the UI is composed from the same building blocks at every nesting level. A panel inside another panel follows the same rules as a top-level panel. A dropdown inside a toolbar follows the same rules as a dropdown inside a panel.

### The three composition levels

```
Level 0 — Window (App)
    Owns the event loop. Holds a [dynamic]^FloatingPanel registry
    and an overlay stack. Calls update/draw on all of them in order.

Level 1 — Panel (FloatingPanel)
    Has chrome (title bar, border, buttons) + a content area.
    draw_content proc-variable is the seam for what goes inside.
    update_content proc-variable handles custom per-frame input.
    A panel content proc may create and manage child panels at this same level.

Level 2 — Widget
    Leaf elements (button, slider, dropdown, text field, label, progress bar).
    Each widget is a proc pair: draw_<widget> + update_<widget>.
    Widgets do not own child widgets — they return interaction results
    that the caller acts on.
```

### Strategy pattern — `draw_content` + `update_content`

`FloatingPanel` has two strategy proc-variables:

- **`draw_content: proc(app: ^App, content: rl.Rectangle)`** — called during the draw phase to render the panel body.
- **`update_content: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool)`** — called during the update phase for panels with custom input handling. Nil = no custom input.

Any proc matching the respective signature can be assigned at construction time via `PanelDesc`. This replaces type switches and avoids inheritance. Panels that only display (Stats, Log, Render, System_Info) set only `draw_content`. Interactive panels (terminal, tool options) set both.

### Proc-variable seam (`draw_content`)

`FloatingPanel.draw_content` is `proc(app: ^App, content: rl.Rectangle)`. Any proc matching this signature can be slotted in at construction time. This is the primary composition mechanism — it replaces switch/if chains on panel type.

A content proc may:
- Draw widgets directly into `content`
- Call `draw_panel_chrome` + its own `draw_content` to embed a child panel
- Push overlays onto `App.overlay_stack` for later drawing (see below)

A content proc must NOT:
- Call `rl.BeginDrawing` / `rl.EndDrawing`
- Modify panel geometry (rect, visible) of other panels directly — route through `App` signals instead

### Nested panels

A panel can host child panels. The child's `rect` is expressed in screen coordinates and may be constrained to stay within the parent's content area. The parent's `draw_content` proc owns the child `FloatingPanel` values (stored on `App` or in a dedicated struct) and calls `update_panel` + `draw_panel` on them.

Pattern:

```odin
// In App (or a dedicated sub-struct):
inspector_panel: FloatingPanel
property_panel:  FloatingPanel

// In the parent draw_content proc:
draw_some_parent_content :: proc(app: ^App, content: rl.Rectangle) {
    // constrain children to parent content area
    clamp_panel_to_rect(&app.inspector_panel, content)
    draw_panel(&app.inspector_panel, app)
}

// In the event loop (update phase), before drawing:
update_panel(&app.inspector_panel, mouse, lmb, lmb_pressed)
```

Input for child panels must be consumed before the parent processes its own input. Update child panels first in the update pass.

### Z-order and the overlay stack

Elements are drawn in strict Z-order. Items drawn later appear on top. The event loop processes input in reverse Z-order (topmost element gets first pick).

```
Draw order (bottom → top):
  1. Background (ClearBackground)
  2. Base panels (FloatingPanel list, in index order)
  3. Overlays (overlay stack, in push order — last pushed = topmost)

Input order (highest priority → lowest):
  1. Overlays (reverse stack order)
  2. Base panels (reverse index order)
  3. Background / global shortcuts
```

`App` holds an overlay stack:

```odin
// Conceptual — add to App when implementing overlays:
overlay_stack: [dynamic]Overlay
```

An `Overlay` is any transient surface drawn on top of everything (dropdown list, context menu, tooltip, modal dialog). It is pushed by a widget during the draw phase and consumed (drawn + updated) at the end of the same frame.

### Widget pattern

Every widget is a stateless proc pair:

```
draw_<widget>(rect, state, ...) — draws the widget; returns nothing
update_<widget>(rect, state, mouse, lmb, lmb_pressed) -> <InteractionResult>
```

`state` is a small struct owned by the enclosing panel or `App`. The widget proc does not store state itself. The caller decides what to do with the interaction result.

Example interaction result types:

```odin
ButtonResult  :: enum { None, Clicked }
SliderResult  :: struct { changed: bool, value: f32 }
DropdownResult :: struct { opened: bool, closed: bool, selected: int }
```

The update proc is called in the update phase (before drawing). The draw proc is called in the draw phase. Never mix them.

### Dropdown menus

A dropdown has two visual states: collapsed (a button) and expanded (an overlay list). The collapsed state is drawn inline as a widget. When opened, the expanded list is pushed to `App.overlay_stack` so it draws above all panels.

```odin
Dropdown :: struct {
    open:     bool,
    items:    []cstring,
    selected: int,
    rect:     rl.Rectangle,  // screen rect of the collapsed button
}

// In draw phase:
draw_dropdown_collapsed(rect, &state.my_dropdown)
if state.my_dropdown.open {
    push_overlay(&app.overlay_stack, make_dropdown_overlay(&state.my_dropdown))
}

// In update phase:
result := update_dropdown(rect, &state.my_dropdown, mouse, lmb, lmb_pressed)
if result.selected >= 0 { ... }
```

The overlay is responsible for closing itself (setting `open = false`) when the user clicks outside it or selects an item. The overlay stack is cleared each frame after drawing.

### Context menus

Same pattern as dropdowns, but triggered by right-click anywhere inside a rect. Push a `ContextMenu` overlay with an item list and a screen position. Context menus always draw at the click position, clamped to screen bounds.

### Modal dialogs

A `FloatingPanel` with `closeable = false`, `dragging = false`, paired with a `draw_dim_overlay()` call immediately before it. Modals are pushed to the overlay stack as the topmost item and consume all input below them (click-through blocking). Only one modal may be active at a time — enforce with a bool on `App`.

---

## File Layout

| File | Responsibility |
|---|---|
| `ui/app.odin` | `App` and `FloatingPanel` structs; `PanelDesc` builder; `make_panel` factory; `app_add_panel` / `app_find_panel` / `app_restart_render` registry; `run_app` (main event loop); log ring; layout save/load |
| `ui/ui.odin` | Shared draw/interaction primitives: `update_panel`, `draw_panel_chrome`, `draw_panel`, `draw_dim_overlay`, `upload_render_texture`, `render_dest_rect`, `screen_to_render_ray`; `PanelStyle` + `DEFAULT_PANEL_STYLE`; color/size constants |
| `ui/rt_render_panel.odin` | `draw_render_content` — renders the live ray-trace preview into a panel content area |
| `ui/stats_panel.odin` | `draw_stats_content` — tile progress, thread count, elapsed time, progress bar |
| `ui/log_panel.odin` | `draw_log_content` — scrolling ring-buffer log display |
| `ui/system_info.odin` | `draw_system_info_content` — OS, CPU, RAM, GPU info display |
| `ui/edit_view_panel.odin` | `EditViewState`, `EditSphere`; `draw_edit_view_content` / `update_edit_view_content` — 3D orbit viewport with sphere editing; `build_world_from_edit_view` — converts edit spheres to raytrace objects for re-rendering |

New files to add as the UI grows:

| File | Future responsibility |
|---|---|
| `ui/widgets.odin` | `draw_button`, `draw_slider`, `draw_text_field`, `draw_dropdown`, `draw_progress_bar`, etc. |
| `ui/overlays.odin` | `Overlay` type, overlay stack management, `push_overlay`, `draw_overlay_stack` |
| `ui/options_panel.odin` | `draw_options_content` — editable render settings (samples, resolution, max depth) |
| `ui/tools.odin` | Tool enum, active tool state, per-tool update/draw procs |
| `ui/terminal_panel.odin` | `draw_terminal_content` / `update_terminal_content` — command input + output; follows the same Strategy pattern as Edit View |

### Adding a new panel

Create `ui/<name>_panel.odin`. Define `draw_<name>_content :: proc(app: ^App, content: rl.Rectangle)`. For interactive panels also define `update_<name>_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool)`. Add a panel ID constant in `app.odin` (`PANEL_ID_<NAME> :: "<name>"`). In `run_app`, call `app_add_panel(&app, make_panel(PanelDesc{ id = PANEL_ID_<NAME>, ..., draw_content = draw_<name>_content, update_content = update_<name>_content }))`. No other files need to change. See `ui/edit_view_panel.odin` as the reference implementation for a panel with both draw and update content procs.

### Adding a new widget

Add it to `ui/widgets.odin` as a `draw_<name>` + `update_<name>` pair. Widget state struct goes in `App` or in the panel state struct that owns it. No global widget state.

### Adding a new shared primitive

Add it to `ui/ui.odin`. If it is only used by one panel, keep it in that panel's file instead.

---

## Core Types

### `FloatingPanel`

```odin
FloatingPanel :: struct {
    id:                 string,          // unique key for lookup and persistence
    title:              cstring,
    rect:               rl.Rectangle,    // position + size on screen
    min_size:           rl.Vector2,
    dragging:           bool,
    resizing:           bool,
    drag_offset:        rl.Vector2,
    visible:            bool,
    closeable:          bool,            // shows [X] button; sets visible=false on click
    detachable:         bool,            // shows maximize/restore button
    maximized:          bool,
    saved_rect:         rl.Rectangle,    // rect before maximization
    dim_when_maximized: bool,            // draw a dim overlay when this panel is maximized
    style:              ^PanelStyle,     // nil = DEFAULT_PANEL_STYLE

    // Strategy pattern — behavior swapped per panel via proc pointer.
    draw_content:   proc(app: ^App, content: rl.Rectangle),
    update_content: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool),
}
```

### `PanelDesc` (builder)

```odin
PanelDesc :: struct {
    id:                 string,
    title:              cstring,
    rect:               rl.Rectangle,
    min_size:           rl.Vector2,
    visible:            bool,
    closeable:          bool,
    detachable:         bool,
    dim_when_maximized: bool,
    style:              ^PanelStyle,
    draw_content:       proc(app: ^App, content: rl.Rectangle),
    update_content:     proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool),
}
```

### Factory and registry procs

| Proc | Purpose |
|---|---|
| `make_panel(desc: PanelDesc) -> ^FloatingPanel` | Allocates and initialises a panel from a builder struct. |
| `app_add_panel(app, panel)` | Appends a heap-allocated panel to `app.panels`; app takes ownership. |
| `app_find_panel(app, id) -> ^FloatingPanel` | Returns the first panel whose `id` matches, or nil. |
| `app_restart_render(app, new_world)` | Replaces the current world and starts a fresh render session. No-op if `!app.finished`. Frees the old session and world, resets `app.session`, `app.finished`, `app.elapsed_secs`, and `app.render_start`. |

### Panel ID constants

```odin
PANEL_ID_RENDER      :: "render_preview"
PANEL_ID_STATS       :: "stats"
PANEL_ID_LOG         :: "log"
PANEL_ID_SYSTEM_INFO :: "system_info"
PANEL_ID_EDIT_VIEW   :: "edit_view"
```

IDs are also the map keys used for config persistence (`util.EditorLayout.panels`).

### `App`

Central mutable state for a running editor session. `panels: [dynamic]^FloatingPanel` is the registry — all panels live here. Iterate with `for p in app.panels`. Lookup by ID with `app_find_panel`.

Three fields support re-rendering from the Edit View:

- `num_threads: int` — stored once at startup; reused by `app_restart_render`.
- `camera: ^rt.Camera` — pointer to the single camera; reused across renders (same dimensions).
- `world: [dynamic]rt.Object` — currently active world; owned by `App`. Replaced (and freed) by `app_restart_render`. Freed by a defer in `run_app` on exit.

`g_app` is a package-level pointer used only by the Raylib trace log callback (which requires a C calling convention and cannot close over Odin state). Treat it as internal plumbing — do not read or write it from panel content procs.

### Log Ring

`app.log_lines` is a fixed-size ring buffer of `LOG_RING_SIZE` (64) heap-allocated strings. Use `app_push_log` to append; it takes ownership and frees the oldest entry when the buffer wraps. Always pass a freshly allocated string (e.g. `fmt.aprintf`, `strings.clone`) — never a string literal address or a string borrowed from another owner.

### `PanelStyle` (Flyweight)

```odin
PanelStyle :: struct {
    bg_color:           rl.Color,
    title_bg_color:     rl.Color,
    title_text_color:   rl.Color,
    border_color:       rl.Color,
    content_text_color: rl.Color,
    accent_color:       rl.Color,
    done_color:         rl.Color,
    title_bar_height:   f32,
    resize_grip_size:   f32,
}
```

**Flyweight pattern**: `PanelStyle` separates intrinsic immutable style data (shared across many panels with the same theme) from per-instance state (rect, visible, etc. in `FloatingPanel`). `DEFAULT_PANEL_STYLE` is the single source of truth for the default theme. `FloatingPanel.style = nil` means "use default". Custom themes are heap-allocated `PanelStyle` values shared by reference.

`draw_panel_chrome` resolves the style: `style := DEFAULT_PANEL_STYLE; if panel.style != nil { style = panel.style^ }`. Content procs currently read the package-level constants (`CONTENT_TEXT_COLOR`, etc.) — migration to `PanelStyle` is deferred.

---

## Shared Primitives (`ui/ui.odin`)

| Proc | Purpose |
|---|---|
| `update_panel(panel, mouse, lmb, lmb_pressed)` | Drag, resize, close, maximize. Call once per frame per panel before drawing. |
| `clamp_panel_to_screen(panel, sw, sh)` | Keeps panel inside window bounds after resize. Call after `update_panel`. |
| `clamp_panel_to_rect(panel, rect)` | Constrains panel to a parent content rectangle (for nested panels). |
| `draw_panel_chrome(panel) -> rl.Rectangle` | Draws background, title bar, buttons, resize grip using resolved `PanelStyle`. Returns content area. |
| `draw_panel(panel, app)` | Calls chrome then `panel.draw_content`. Single call per panel per frame. |
| `draw_dim_overlay()` | Full-screen semi-transparent black rectangle (modal backdrop). |
| `upload_render_texture(app)` | Converts float pixel buffer → gamma-corrected RGBA → GPU texture. |
| `render_dest_rect(app, content) -> rl.Rectangle` | Letterboxed destination rectangle for the render image inside a content area. |
| `screen_to_render_ray(app, pos) -> (rl.Ray, bool)` | Maps screen position to a world-space ray for mouse picking. Uses `app_find_panel`. |

### Color / Size Constants

All UI colors and metric constants live at the top of `ui/ui.odin`. The package-level constants remain for content procs that have not yet been migrated to `PanelStyle`. `draw_panel_chrome` uses `PanelStyle` exclusively.

```
PANEL_BG_COLOR        background fill of panel body
TITLE_BG_COLOR        title bar background
TITLE_TEXT_COLOR      title bar text and button icons
BORDER_COLOR          panel outline and resize grip lines
CONTENT_TEXT_COLOR    default text color inside panel body
ACCENT_COLOR          in-progress highlight (blue-white)
DONE_COLOR            completion highlight (green)

TITLE_BAR_HEIGHT      height of the title bar strip (24 px)
RESIZE_GRIP_SIZE      size of the bottom-right resize handle (14 px)
```

When adding new UI elements, reuse these constants rather than introducing new magic colors.

### Deferred: `update_panel` title-bar hit testing

`update_panel` still uses the `TITLE_BAR_HEIGHT` package constant for title-bar hit testing. If a panel has a custom `style.title_bar_height`, drag hit detection will diverge from the drawn bar height (e.g. a 32px title bar drawn with only 24px hit area). Same applies to `RESIZE_GRIP_SIZE` vs `style.resize_grip_size`, and to `app.odin` / `screen_to_render_ray` which compute content rects with `TITLE_BAR_HEIGHT`. Fix: resolve `PanelStyle` in `update_panel` and use `style.title_bar_height` / `style.resize_grip_size`; propagate style-aware content rects where needed.

---

## Event Loop (`run_app`)

The Raylib event loop in `app.odin` follows this order every frame:

```
UPDATE PHASE (input → state):
  1. Update elapsed time
  2. Sample mouse/keyboard state
  3. Consume overlay input (reverse stack order — topmost first)
  4. For each panel in app.panels:
       update_panel + clamp_panel_to_screen
       if panel.update_content != nil && panel.visible: call update_content
  5. Per-frame logic: tool input, keyboard shortcuts (L = reopen log, S = reopen system info, E = reopen edit view), render progress check

DRAW PHASE (state → screen):
  6. upload_render_texture (every 4 frames and on completion)
  7. BeginDrawing / ClearBackground
  8. For each panel: if dim_when_maximized && maximized: draw_dim_overlay(); draw_panel
  9. Draw overlay stack in push order (topmost last = on top)
  10. EndDrawing
  11. free_all(context.temp_allocator)
```

New per-frame logic goes in step 5 (after panel geometry is settled, before drawing). New overlays are pushed during the draw phase (step 8) by widget procs; the stack is flushed in step 9 and cleared after.

---

## Panel ID and Config Persistence

Each panel has an `id: string` field (e.g. `"render_preview"`, `"stats"`, `"log"`). These IDs are used as keys in `util.EditorLayout.panels: map[string]PanelState` for config file persistence.

- `apply_editor_layout` iterates `app.panels` and applies saved state by panel ID (missing keys are silently ignored — the panel uses its default rect/visibility).
- `build_editor_layout_from_app` iterates `app.panels` and writes each panel's current state into the map by ID.
- Adding a new panel with a new ID automatically participates in persistence without touching any other code.

JSON config format:
```json
{"editor": {"panels": {"render_preview": {...}, "stats": {...}, "log": {...}}}}
```

---

## Naming Conventions

| Category | Convention | Example |
|---|---|---|
| Panel content proc | `draw_<name>_content` | `draw_stats_content` |
| Panel input proc | `update_<name>_content` | `update_edit_view_content` |
| Widget draw proc | `draw_<widget>` | `draw_button`, `draw_dropdown` |
| Widget update proc | `update_<widget>` | `update_button`, `update_dropdown` |
| Widget result type | `<Widget>Result` | `ButtonResult`, `DropdownResult` |
| Widget state type | `<Widget>State` | `DropdownState`, `SliderState` |
| Shared draw primitive | `draw_<concept>` | `draw_dim_overlay` |
| Shared compute helper | `<concept>_<noun>` | `render_dest_rect`, `screen_to_render_ray` |
| Panel update proc | `update_<concept>` | `update_panel` |
| App state mutators | `app_<verb>_<noun>` | `app_push_log`, `app_add_panel`, `app_find_panel` |
| Overlay push | `push_<overlay_type>` | `push_dropdown_overlay`, `push_context_menu` |
| Layout helpers | `apply_<source>_layout`, `build_<dest>_layout_from_<source>` | `apply_editor_layout` |
| Constants | `SCREAMING_SNAKE_CASE` | `TITLE_BAR_HEIGHT`, `ACCENT_COLOR`, `PANEL_ID_RENDER` |

---

## Edit View Panel (`ui/edit_view_panel.odin`)

The Edit View is the first fully interactive panel — it has both `draw_content` and `update_content` set. It provides a live 3D Raylib viewport for constructing the ray-traced scene before committing a render.

### Data types

```odin
EditSphere :: struct {
    center:   [3]f32,   // world position
    radius:   f32,
    mat_type: int,      // 0=lambertian  1=metallic  2=dielectric
    color:    [3]f32,   // albedo / base color
}

EditViewState :: struct {
    viewport_tex:   rl.RenderTexture2D, // off-screen 3D render target
    tex_w, tex_h:   i32,

    cam3d:          rl.Camera3D,        // recomputed each frame from orbit params
    orbit_yaw:      f32,
    orbit_pitch:    f32,
    orbit_distance: f32,
    orbit_target:   rl.Vector3,

    rmb_held:       bool,               // right-drag orbit tracking
    last_mouse:     rl.Vector2,

    objects:        [dynamic]EditSphere,
    selected_idx:   int,                // -1 = none selected
    initialized:    bool,
}
```

`App.edit_view` holds the single `EditViewState`. The dynamic `objects` slice is cleaned up by `defer delete(app.edit_view.objects)` in `run_app`. The off-screen texture is cleaned up by `defer rl.UnloadRenderTexture(app.edit_view.viewport_tex)`.

### Layout

```
┌──────────────────────────────────────────┐
│  Title bar (panel chrome)                │
├──────────────────────────────────────────┤
│  Toolbar (32px)  [Add Sphere] [Delete] [Render] │
├──────────────────────────────────────────┤
│                                          │
│  3D viewport (off-screen RenderTexture)  │
│  • orbit camera (right-drag)             │
│  • scroll zoom                           │
│  • left-click picks spheres              │
│                                          │
├──────────────────────────────────────────┤
│  Properties strip (70px)                 │
│  selected sphere: pos / radius / mat     │
└──────────────────────────────────────────┘
```

### Key procs

| Proc | Role |
|---|---|
| `init_edit_view(ev)` | Seeds orbit params, adds 3 default spheres (red, blue, green), calls `update_orbit_camera`. |
| `update_orbit_camera(ev)` | Clamps pitch/distance; computes spherical-to-Cartesian position; writes `ev.cam3d`. |
| `draw_viewport_3d(ev, vp_rect)` | Reallocates `viewport_tex` on resize; renders scene + grid to off-screen texture; draws to panel with Y-flip (`src.height = -tex_h`). |
| `compute_viewport_ray(ev, mouse, vp_rect) -> (rl.Ray, bool)` | Perspective ray from mouse position using camera basis vectors + `fovy`. Returns `false` outside viewport. |
| `pick_sphere(ev, ray) -> int` | `rl.GetRayCollisionSphere` loop; returns closest hit index or `-1`. |
| `draw_edit_properties(ev, rect)` | Shows pos/radius/material of selected sphere, or "No object selected". |
| `build_world_from_edit_view(ev) -> [dynamic]rt.Object` | Converts `EditSphere` list to raytrace `Object` slice. Prepends a grey ground sphere at `{0, -1000, 0}`. Caller owns the result. |

### Scene integration

Clicking **Render** in the toolbar (when `app.finished`) calls:
```odin
app_restart_render(app, build_world_from_edit_view(ev))
```
This replaces `app.world`, calls `rt.free_session` on the old session, and starts a new `rt.start_render`. The Render Preview panel then shows the new render as tiles complete.

### Keyboard controls (when Edit View panel is focused with a sphere selected)

| Key | Action |
|---|---|
| W / Up | Move sphere −Z |
| S / Down | Move sphere +Z |
| A / Left | Move sphere −X |
| D / Right | Move sphere +X |
| Q | Move sphere −Y |
| E | Move sphere +Y |
| + / KP+ | Increase radius |
| − / KP− | Decrease radius (min 0.05) |

**Note:** `D` and `S` are also used by the "right-mouse orbit" for XZ movement, and `E` is the global shortcut to re-show the Edit View panel. These only conflict if the panel is closed and re-opened — when the panel is visible, the per-sphere key handling takes priority.

### Off-screen rendering pattern

`draw_viewport_3d` uses a `rl.RenderTexture2D` to render the 3D scene without interfering with the main `BeginDrawing / EndDrawing` pair. The texture is resized whenever `vp_rect` dimensions change. The Y-flip (`src.height = -tex_h`) corrects the OpenGL bottom-left origin.

```odin
rl.BeginTextureMode(ev.viewport_tex)
    rl.ClearBackground(...)
    rl.BeginMode3D(ev.cam3d)
        rl.DrawGrid(...)
        // draw spheres ...
    rl.EndMode3D()
rl.EndTextureMode()

src := rl.Rectangle{0, 0, f32(ev.tex_w), -f32(ev.tex_h)}  // negative height = Y-flip
rl.DrawTexturePro(ev.viewport_tex.texture, src, vp_rect, {}, 0, rl.WHITE)
```

---

## Planned Extensions

When implementing the items below, follow the composition model described above.

### Widget Library (`ui/widgets.odin`)
Stateless draw+update pairs for: `button`, `toggle`, `slider`, `text_field`, `dropdown`, `color_swatch`, `progress_bar`, `separator`, `label`. Each widget takes its rect, its state struct, and mouse state. Returns an interaction result. No global state.

### Overlay Stack (`ui/overlays.odin`)
`Overlay` union (dropdown list, context menu, tooltip, modal). `push_overlay(stack, overlay)` during draw. `draw_overlay_stack(stack, app)` at end of draw phase. `update_overlay_stack(stack, mouse, lmb, lmb_pressed)` at start of update phase. Stack is a `[dynamic]Overlay` on `App`, cleared each frame after drawing.

### Options Menu (`ui/options_panel.odin`)
`FloatingPanel` with `draw_options_content`. Uses widget library for inputs. Persists via `util.save_config`. Triggered by a menu bar button or keyboard shortcut.

### Tool System (`ui/tools.odin`)
`ActiveTool :: enum { None, Select, Pan, Inspect, ... }` stored on `App`. Each tool has `update_<tool>_tool(app, mouse, ...)` and optionally `draw_<tool>_overlay(app)`. The active tool's update runs in event loop step 5; its overlay is pushed in step 8. `screen_to_render_ray` is the picking primitive for all geometry-aware tools.

### Command Terminal (`ui/terminal_panel.odin`)
`FloatingPanel` toggled by a keyboard shortcut. `draw_terminal_content` renders a command input line + scrollable output using the widget text field. Input dispatches to a command registry (`map[string]proc(app: ^App, args: []string)`). Output via `app_push_log` or a dedicated terminal ring. Set both `draw_content` and `update_content` (Strategy pattern).

### Menu Bar
A fixed strip at the top of the window (not a `FloatingPanel`). Renders menu titles (File, Edit, View, Render, …); clicking a title pushes a `DropdownOverlay` with that menu's items. Implemented as a single `draw_menu_bar(app, rect)` + `update_menu_bar(app, rect, mouse, ...)` pair, not as a panel.
