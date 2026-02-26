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
    and a DockLayout. Calls update/draw on all of them in order.

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

Any proc matching the respective signature can be assigned at construction time via `PanelDesc`. This replaces type switches and avoids inheritance. Panels that only display (Stats, Log, Render, System_Info) set only `draw_content`. Interactive panels (Edit View, Camera, Object Props) set both.

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
  2. Dock layout panels (layout_update_and_draw)
  3. Menu bar (always on top of panels)
  4. File modal (topmost — always drawn last)

Input order (highest priority → lowest):
  1. Menu bar (priority 1)
  2. File modal (priority 2)
  3. Dock layout panels (effective_lmb_pressed = lmb && !input_consumed)
```

`app.input_consumed` is the mechanism that prevents click bleed through overlapping UI layers. See the **Input Consumption System** section below.

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

`FileModalState` (`ui/file_modal.odin`) is the current concrete modal implementation — see that section below.

---

## File Layout

### `ui/` package

| File | Responsibility |
|---|---|
| `ui/app.odin` | `App` and `FloatingPanel` structs; `PanelDesc` builder; `make_panel` factory; `app_add_panel` / `app_find_panel` / `app_restart_render` / `app_restart_render_with_scene` registry; `run_app` (main event loop); log ring; layout save/load; `draw_ui_text` / `measure_ui_text` (font-agnostic text helpers) |
| `ui/ui.odin` | Shared draw/interaction primitives: `update_panel`, `draw_panel_chrome`, `draw_panel`, `draw_dim_overlay`, `upload_render_texture`, `render_dest_rect`, `screen_to_render_ray`; `PanelStyle` + `DEFAULT_PANEL_STYLE`; color/size constants |
| `ui/rt_render_panel.odin` | `draw_render_content` — renders the live ray-trace preview into a panel content area |
| `ui/stats_panel.odin` | `draw_stats_content` — tile progress, thread count, elapsed time, progress bar |
| `ui/log_panel.odin` | `draw_log_content` — scrolling ring-buffer log display |
| `ui/system_info.odin` | `draw_system_info_content` — OS, CPU, RAM, GPU info display |
| `ui/edit_view_panel.odin` | `EditViewState`, `EditViewSelectionKind`; `draw_edit_view_content` / `update_edit_view_content` — 3D orbit viewport; toolbar (Add Sphere, Delete, From View, Render); drag-float properties strip; camera gizmo; `init_edit_view`, `update_orbit_camera`, `draw_viewport_3d`, `draw_edit_properties`. Calls `ExportToSceneSpheres` + `app_restart_render_with_scene` for re-render |
| `ui/camera_panel.odin` | `CameraPanelState`; `draw_camera_panel_content` / `update_camera_panel_content` — editable render camera params (lookfrom, lookat, vfov, aperture, focus_dist, etc.) with drag-float fields |
| `ui/camera_preview_panel.odin` | `draw_preview_port_content` — rasterized preview rendered from the render camera position using a Raylib `RenderTexture2D` |
| `ui/object_props_panel.odin` | `ObjectPropsPanelState`; `draw_object_props_content` / `update_object_props_content` — per-sphere property editor (material type toggle buttons, drag-float center/radius/albedo fields) |
| `ui/commands.odin` | `Command`, `CommandRegistry` (fixed 64-slot array); CMD_* string constants; `cmd_register`, `cmd_find`, `cmd_execute`, `cmd_is_enabled`, `cmd_is_checked` |
| `ui/command_actions.odin` | All `cmd_action_*` procs, `cmd_checked_*` procs, and `cmd_enabled_*` procs; `toggle_panel`, `panel_visible`; `register_all_commands` (called once at startup in `run_app`) |
| `ui/file_modal.odin` | `FileModalState`, `FileModalMode` enum (.Import / .SaveAs / .PresetName); `file_modal_open`, `file_modal_update` (keyboard + mouse input, sets `input_consumed`), `file_modal_draw` (visual only), `file_modal_confirm` (executes the action on OK/Enter) |
| `ui/menu_bar.odin` | `MenuBarState`, `MenuEntryDyn`, `MenuDyn`; `get_menus_dynamic` (builds menu from command registry + live state each frame using `context.temp_allocator`); `menu_bar_update` (sets `input_consumed`), `menu_bar_draw`; `make_cstring_temp` helper |
| `ui/layout.odin` | `DockLayout`, `DockNode`, `DockPanel` types; `DockNodeType`, `DockSplitAxis`; `layout_init`, `layout_add_panel`, `layout_add_leaf`, `layout_add_split`, `layout_update_and_draw`, `layout_find_panel_index`; `layout_build_default`; center-pane split view logic |
| `ui/layout_presets.odin` | `layout_build_render_focus`, `layout_build_edit_focus` (built-in presets); `layout_save_named_preset`, `layout_apply_named_preset`; built-in preset name constants (`PRESET_NAME_DEFAULT`, `PRESET_NAME_RENDER`, `PRESET_NAME_EDIT`) |
| `ui/font_sdf.odin` | SDF font loading (`load_sdf_font`, `load_font_ex_fallback`), `draw_text_sdf`, `unload_ui_font`; loaded by `run_app` when `USE_SDF_FONT` build flag is set |

### `ui/editor/` sub-package

Viewport ray casting and `SceneManager` were extracted here to avoid a circular import (`ui/edit_view_panel` → `editor` → `scene`, not back to `ui`). This sub-package has no dependency on the `ui` package.

| File | Responsibility |
|---|---|
| `ui/editor/core.odin` | `EditorObject :: union {scene.SceneSphere}` — discriminated union for future polymorphism; `compute_viewport_ray` (perspective ray from mouse + camera params + viewport rect); `ray_hit_plane_y` (ray × horizontal plane intersection); `pick_camera` (ray × camera gizmo sphere) |
| `ui/editor/scene_manager.odin` | `SceneManager` struct (owns `[dynamic]EditorObject`); `new_scene_manager`, `free_scene_manager`; `LoadFromSceneSpheres`, `ExportToSceneSpheres`, `AppendDefaultSphere`, `OrderedRemove`, `SceneManagerLen`, `PickSphereInManager`, `GetSceneSphere`, `SetSceneSphere` |
| `ui/editor/materials.odin` | `material_name(k: scene.MaterialKind) -> cstring` — display name for material enum values |

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
| `app_restart_render(app, new_world)` | Replaces the current world and starts a fresh render session. No-op if `!app.finished`. Frees the old session and world, applies `app.camera_params`, resets `app.session`, `app.finished`, `app.elapsed_secs`, and `app.render_start`. |
| `app_restart_render_with_scene(app, scene_objects: []scene.SceneSphere)` | Builds a raytrace world from a `scene.SceneSphere` slice via `rt.build_world_from_scene`, then calls the restart logic. Used by Edit View and command actions so they do not need to import `raytrace` directly. |

### Panel ID constants

```odin
PANEL_ID_RENDER        :: "render_preview"
PANEL_ID_STATS         :: "stats"
PANEL_ID_LOG           :: "log"
PANEL_ID_SYSTEM_INFO   :: "system_info"
PANEL_ID_EDIT_VIEW     :: "edit_view"
PANEL_ID_CAMERA        :: "camera"
PANEL_ID_OBJECT_PROPS  :: "object_props"
PANEL_ID_PREVIEW_PORT  :: "preview_port"
```

IDs are also the map keys used for config persistence (`util.EditorLayout.panels`).

### `App`

Central mutable state for a running editor session. `panels: [dynamic]^FloatingPanel` is the registry — all panels live here. Iterate with `for p in app.panels`. Lookup by ID with `app_find_panel`.

```odin
App :: struct {
    panels:        [dynamic]^FloatingPanel,
    dock_layout:   DockLayout,

    render_tex:    rl.Texture2D,
    pixel_staging: []rl.Color,

    session:       ^rt.RenderSession,

    num_threads:   int,
    camera:        ^rt.Camera,
    world:         [dynamic]rt.Object,
    camera_params: scene.CameraParams, // shared camera definition; applied before each render

    log_lines:     [LOG_RING_SIZE]string,
    log_count:     int,

    finished:      bool,
    elapsed_secs:  f64,
    render_start:  time.Time,

    // Sub-state for interactive panels
    edit_view:      EditViewState,
    camera_panel:   CameraPanelState,
    menu_bar:       MenuBarState,
    object_props:   ObjectPropsPanelState,

    // Preview Port: rasterized view from render camera (app.camera_params)
    preview_port_tex: rl.RenderTexture2D,
    preview_port_w:   i32,
    preview_port_h:   i32,

    // SDF UI font (optional; fallback to default font if load fails)
    ui_font:        rl.Font,
    ui_font_shader: rl.Shader,
    use_sdf_font:   bool,

    // Input priority: reset to false each frame; set by menu/modal to block panels below
    input_consumed: bool,

    // Exit signal (Raylib vendor has no SetWindowShouldClose binding)
    should_exit: bool,

    // Command registry (registered once at startup via register_all_commands)
    commands: CommandRegistry,

    // File modal (shared across Import, SaveAs, PresetName modes)
    file_modal: FileModalState,

    // Current scene file path (empty = no path; gates File → Save enabled state)
    current_scene_path: string,

    // Named layout presets (loaded from config, persisted on save-config)
    layout_presets: [dynamic]util.LayoutPreset,
}
```

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

The Raylib event loop in `app.odin` follows this order every frame. The loop condition is `!rl.WindowShouldClose() && !app.should_exit` — Raylib's vendor binding has no `SetWindowShouldClose`, so `app.should_exit` is the exit signal.

```
UPDATE PHASE:
  1. Update elapsed time
  2. Sample mouse/keyboard state (mouse, lmb, lmb_pressed)
  3. app.input_consumed = false          (reset each frame)
  4. menu_bar_update (priority 1)        — sets input_consumed on click
  5. file_modal_update (priority 2)      — sets input_consumed when active
  6. Keyboard shortcuts (F5, L, S, E, C, O) — only if !input_consumed

RENDER PROGRESS PHASE:
  7. upload_render_texture (every 4 frames)
  8. Render completion check: if progress >= 1.0, finish_render + upload

DRAW PHASE:
  9. BeginDrawing / ClearBackground
 10. layout_update_and_draw (panels; passes effective_lmb_pressed = lmb && !input_consumed)
 11. menu_bar_draw (drawn after panels — always on top)
 12. file_modal_draw (drawn last — highest Z)
 13. EndDrawing
 14. free_all(context.temp_allocator)
```

New per-frame logic goes in step 6 (after input_consumed is determined by menu/modal). New draw elements go in step 10 (inside layout) or after it. Overlays that must draw on top of everything (except the modal) should draw between steps 10 and 11.

**Note:** The overlay stack concept described in earlier docs is not yet implemented as a data structure. `file_modal` and `menu_bar` serve the "modal/overlay" role for now through their explicit draw-order position.

---

## Input Consumption System

`app.input_consumed: bool` is a per-frame flag that prevents click bleed through overlapping UI layers.

**Frame lifecycle:**
1. Reset to `false` at the start of each frame (step 3 above).
2. `menu_bar_update` (priority 1): sets `input_consumed = true` on any click that lands on the menu bar or an open dropdown.
3. `file_modal_update` (priority 2): unconditionally sets `input_consumed = true` while the modal is active.
4. Keyboard shortcuts (step 6): skip if `input_consumed` is true.
5. `layout_update_and_draw` (step 10): receives `effective_lmb_pressed = lmb_pressed && !input_consumed` — panels never fire a click through the menu or modal.

Panel content procs may also set `g_app.input_consumed = true` (via the global pointer) when they consume a toolbar button click, to prevent the same click from reaching other panels in the same frame.

---

## Command Registry

`CommandRegistry` (`ui/commands.odin`) is a fixed-size array of up to `MAX_COMMANDS` (64) `Command` entries.

```odin
Command :: struct {
    id:           string,
    label:        string,       // display text
    shortcut:     string,       // display only (no auto-binding)
    action:       proc(app: ^App),
    enabled_proc: proc(app: ^App) -> bool, // nil = always enabled
    checked_proc: proc(app: ^App) -> bool, // nil = no checkmark
}
```

**CMD_* constants** are string constants (not an enum) so future plugins can add commands without recompiling:

```odin
CMD_FILE_NEW, CMD_FILE_IMPORT, CMD_FILE_SAVE, CMD_FILE_SAVE_AS, CMD_FILE_EXIT
CMD_VIEW_RENDER, CMD_VIEW_STATS, CMD_VIEW_LOG, CMD_VIEW_SYSINFO, CMD_VIEW_EDIT,
CMD_VIEW_CAMERA, CMD_VIEW_PROPS, CMD_VIEW_PREVIEW
CMD_VIEW_PRESET_DEFAULT, CMD_VIEW_PRESET_RENDER, CMD_VIEW_PRESET_EDIT, CMD_VIEW_SAVE_PRESET
CMD_RENDER_RESTART
```

**Key procs:**
- `cmd_register(reg, cmd)` — appends; no-op if full or id empty.
- `cmd_find(reg, id) -> ^Command` — linear scan; returns nil if not found.
- `cmd_execute(app, id)` — finds + checks enabled_proc + calls action.
- `cmd_is_enabled(app, id) -> bool` — for menu item greying.
- `cmd_is_checked(app, id) -> bool` — for menu item checkmarks.

`register_all_commands(app)` in `ui/command_actions.odin` populates the registry once during `run_app` init.

---

## Dock Layout System

`DockLayout` (`ui/layout.odin`) tiles all panels in the window without floating panels. Each node is either a **leaf** (tabbed group of panels) or a **split** (horizontal or vertical divider with two child nodes).

```odin
DockLayout :: struct {
    nodes:      [MAX_DOCK_NODES]DockNode,   // 64 max
    nodeCount:  int,
    root:       int,
    center_leaf: int,                        // special: can show two panels stacked
    center_split_view:     bool,
    center_split_ratio:    f32,
    center_split_dragging: bool,
    panels:     [MAX_DOCK_PANELS]DockPanel,  // 64 max
    panelCount: int,
}

DockNode :: struct {
    type: DockNodeType,     // .DOCK_NODE_LEAF or .DOCK_NODE_SPLIT
    rect: rl.Rectangle,
    parent: int,
    // Split fields:
    axis:   DockSplitAxis,  // .DOCK_SPLIT_HORIZONTAL (top/bottom) or .DOCK_SPLIT_VERTICAL (left/right)
    childA, childB: int,
    split:  f32,            // 0..1 — fraction of space for childA
    // Leaf fields:
    panelCount:  int,
    panels:      [MAX_PANELS_PER_LEAF]int,  // indices into DockLayout.panels
    activePanel: int,                        // tab index
}
```

**Key procs:**
- `layout_init(layout)` — resets all node/panel counts.
- `layout_add_panel(layout, panel_idx) -> int` — registers an `app.panels` index; returns DockPanel index.
- `layout_add_leaf(layout, panel_indices, active_panel) -> int` — creates a tabbed leaf node.
- `layout_add_split(layout, axis, child_a, child_b, split) -> int` — creates a split node.
- `layout_update_and_draw(app, layout, mouse, lmb, lmb_pressed)` — computes rects from window size, iterates leaf nodes, calls `update_content` then `draw_panel`.
- `layout_find_panel_index(app, id) -> int` — maps panel ID string to `app.panels` index.
- `layout_build_default(app, layout)` — builds the default layout (center: Render+Edit split; right: Stats/SysInfo, Log/Camera/Props, PreviewPort).

**Center-pane split view:** When `layout.center_split_view = true` (the default layout), the center leaf draws both Render and Edit View stacked vertically with a draggable splitter. Toggle with `center_split_view = false` to show only the active tab.

**Three built-in presets** (in `ui/layout_presets.odin`):
- `layout_build_default` — balanced split center with all panels.
- `layout_build_render_focus` — center shows only render; Edit View hidden.
- `layout_build_edit_focus` — center shows only edit view; Render hidden.

---

## `ui/editor/` Sub-package

Imported as `ed "RT_Weekend:ui/editor"` in `ui/edit_view_panel.odin` and `ui/command_actions.odin`.

**Why a sub-package:** Viewport ray casting and `SceneManager` were extracted here to break a potential circular import. The dependency graph is: `ui` → `editor` → `scene`/`raytrace`/`raylib`. Nothing in `editor` imports `ui`.

**`EditorObject`** is the extension point for new scene object types:

```odin
EditorObject :: union { scene.SceneSphere }
```

Adding a new object type only requires extending this union and adding cases to `switch obj in SceneManager.objects` — no new parallel arrays or type tags.

**`SceneManager`** owns the `[dynamic]EditorObject` slice. It is heap-allocated (`new_scene_manager`), freed by `free_scene_manager` (called in `run_app` via defer). The single `SceneManager` instance lives in `App.edit_view.scene_mgr`.

**Viewport utilities in `editor/core.odin`:**
- `compute_viewport_ray(cam3d, tex_w, tex_h, mouse, vp_rect, require_inside) -> (rl.Ray, bool)` — perspective ray cast from mouse coords; `require_inside=false` for active drag continuation outside viewport.
- `ray_hit_plane_y(ray, plane_y) -> (rl.Vector2, bool)` — XZ intersection with a horizontal plane; used for sphere drag movement.
- `pick_camera(ray, lookfrom) -> bool` — hit test against the camera gizmo sphere.

---

## Panel ID and Config Persistence

Each panel has an `id: string` field (e.g. `"render_preview"`, `"stats"`, `"log"`). These IDs are used as keys in `util.EditorLayout.panels: map[string]PanelState` for config file persistence.

- `apply_editor_layout` iterates `app.panels` and applies saved state by panel ID (missing keys are silently ignored — the panel uses its default rect/visibility).
- `build_editor_layout_from_app` iterates `app.panels` and writes each panel's current state into the map by ID.
- Adding a new panel with a new ID automatically participates in persistence without touching any other code.

JSON config format (with layout presets):
```json
{
  "editor": {"panels": {"render_preview": {...}, "stats": {...}, "log": {...}}},
  "presets": [{"name": "My Layout", "layout": {"panels": {...}}}]
}
```

User-saved presets are stored in `app.layout_presets: [dynamic]util.LayoutPreset`. They are loaded from config via `initial_presets` parameter of `run_app`, and saved back to config on exit when `-save-config` is set.

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
| Command action | `cmd_action_<verb>_<noun>` | `cmd_action_file_new`, `cmd_action_view_render` |
| Command predicate | `cmd_<adjective>_<noun>` | `cmd_enabled_render_restart`, `cmd_checked_view_render` |

---

## Edit View Panel (`ui/edit_view_panel.odin`)

The Edit View is a fully interactive panel — it has both `draw_content` and `update_content` set. It provides a live 3D Raylib viewport for constructing the ray-traced scene before committing a render.

### Data types

```odin
// EditSphere is GONE — replaced by scene.SceneSphere + SceneManager (ed.SceneManager)

EditViewSelectionKind :: enum {
    None,
    Sphere,
    Camera,  // render camera gizmo; non-deletable
}

EditViewState :: struct {
    viewport_tex:   rl.RenderTexture2D,
    tex_w, tex_h:   i32,

    cam3d:          rl.Camera3D,        // recomputed each frame from orbit params
    orbit_yaw:      f32,
    orbit_pitch:    f32,
    orbit_distance: f32,
    orbit_target:   rl.Vector3,

    rmb_held:       bool,               // right-drag orbit tracking
    last_mouse:     rl.Vector2,

    scene_mgr:      ^ed.SceneManager,           // owns scene objects
    export_scratch: [dynamic]scene.SceneSphere,  // reused buffer; no per-frame alloc

    selection_kind: EditViewSelectionKind,
    selected_idx:   int,                // -1 = nothing selected

    // Drag-float property fields (sphere only)
    prop_drag_idx:       int,           // -1=none  0=cx  1=cy  2=cz  3=radius
    prop_drag_start_x:   f32,
    prop_drag_start_val: f32,

    // Viewport left-drag to move selected object (sphere only)
    drag_obj_active: bool,
    drag_plane_y:    f32,
    drag_offset_xz:  [2]f32,

    initialized: bool,
}
```

`App.edit_view` holds the single `EditViewState`. `scene_mgr` is freed by `defer ed.free_scene_manager(app.edit_view.scene_mgr)` in `run_app`. The off-screen texture is freed by `defer rl.UnloadRenderTexture(app.edit_view.viewport_tex)`. `export_scratch` is freed by `defer delete(app.edit_view.export_scratch)`.

### Layout

```
┌──────────────────────────────────────────────────────┐
│  Title bar (panel chrome)                            │
├──────────────────────────────────────────────────────┤
│  Toolbar (32px)  [Add Sphere] [Delete]  [From view] [Render] │
├──────────────────────────────────────────────────────┤
│                                                      │
│  3D viewport (off-screen RenderTexture)              │
│  • orbit camera (right-drag)                         │
│  • scroll zoom                                       │
│  • left-click picks spheres or camera gizmo          │
│  • left-drag moves selected sphere on XZ plane       │
│                                                      │
├──────────────────────────────────────────────────────┤
│  Properties strip (90px)                             │
│  selected sphere: X/Y/Z drag-float + R + material    │
└──────────────────────────────────────────────────────┘
```

### Key procs

| Proc | Role |
|---|---|
| `init_edit_view(ev)` | Seeds orbit params, creates `SceneManager`, adds 3 default spheres (red, metallic-blue, green), calls `update_orbit_camera`. |
| `update_orbit_camera(ev)` | Clamps pitch/distance; computes spherical-to-Cartesian position; writes `ev.cam3d`. |
| `draw_viewport_3d(app, vp_rect, objs)` | Reallocates `viewport_tex` on resize; renders scene + grid + camera gizmo to off-screen texture; draws to panel with Y-flip (`src.height = -tex_h`). |
| `draw_edit_properties(app, rect, mouse, objs)` | Shows X/Y/Z/R drag-float fields + material name for selected sphere, or hint text if nothing selected. |
| `get_orbit_camera_pose(ev) -> (lookfrom, lookat)` | Returns current orbit position as path-tracer camera coordinates (used by "From View" button). |

**Picking** is done in `ui/editor/core.odin`: `ed.compute_viewport_ray` + `ed.PickSphereInManager` for spheres, `ed.pick_camera` for the camera gizmo.

### Scene integration

Clicking **Render** in the toolbar (when `app.finished`) calls:
```odin
ed.ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
app_restart_render_with_scene(app, ev.export_scratch[:])
```
This builds a raytrace world from the scene spheres, applies `app.camera_params`, and starts a new render. The Render Preview panel shows the new render as tiles complete.

Clicking **From View** copies the orbit camera pose into `app.camera_params` so the next Render uses the current viewport angle.

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
        // draw spheres, camera gizmo...
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
`ActiveTool :: enum { None, Select, Pan, Inspect, ... }` stored on `App`. Each tool has `update_<tool>_tool(app, mouse, ...)` and optionally `draw_<tool>_overlay(app)`. The active tool's update runs in event loop step 6; its overlay is pushed during draw. `screen_to_render_ray` is the picking primitive for all geometry-aware tools.

### Command Terminal (`ui/terminal_panel.odin`)
`FloatingPanel` toggled by a keyboard shortcut. `draw_terminal_content` renders a command input line + scrollable output using the widget text field. Input dispatches to a command registry (`map[string]proc(app: ^App, args: []string)`). Output via `app_push_log` or a dedicated terminal ring. Set both `draw_content` and `update_content` (Strategy pattern).
