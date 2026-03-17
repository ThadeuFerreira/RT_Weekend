# editor — Editor application

This package is the **editor**: Raylib window, Dear ImGui panels, menus, layout, scene editing.
It depends on **core**, **util**, **raytrace**, and **persistence**.
The editor is **separate from the renderer** (raytrace); it uses the renderer and does not mix rendering logic with UI.

## UI framework: Dear ImGui (migration in progress)

The editor is being migrated from a hand-rolled Raylib panel system to **Dear ImGui v1.91.7-docking** (Issue #136, branch `136-migrate-ui-elements-to-dear-imgui`).

### Current state

| Layer | File(s) | Status |
|---|---|---|
| ImGui bridge | `imgui_rl.odin` | ✅ Done — feeds Raylib input to ImGui IO |
| Panel visibility | `imgui_panel_vis.odin` | ✅ Done — `ImguiPanelVis` struct |
| DockSpace + menu bar + stubs | `imgui_panels_stub.odin` | ✅ Done — all panels open; content is placeholder |
| Console, Stats, System Info | `panel_console.odin` etc. | 🔲 Track A |
| Outliner, Camera | `panel_outliner.odin` etc. | 🔲 Track B |
| Render Preview, Viewport | `panel_render.odin` etc. | 🔲 Track C |
| Details | `panel_details.odin` | 🔲 Track D |
| Modals + menu bar | `panel_confirm_modal.odin` etc. | 🔲 Track E |
| Delete legacy Raylib files | `ui_*.odin`, `panel_registry.odin` | 🔲 Track F |

The **old Raylib panel chrome** (`ui_chrome.odin`, `ui_layout.odin`, `panel_registry.odin`) is still compiled but no longer driven from the main loop. Each migration track replaces the body of a panel stub in `imgui_panels_stub.odin` with real ImGui widgets.

### ImGui submodule

```
vendor/odin-imgui/          ← https://gitlab.com/L-4/odin-imgui
    imgui_linux_x64.a       ← build once: make imgui
    imgui.odin              ← Odin foreign bindings (patched: "system:stdc++" for GCC)
    imgui_impl_opengl3/     ← OpenGL3 renderer backend
```

Import in editor files:
```odin
import imgui               "RT_Weekend:vendor/odin-imgui"
import imgui_impl_opengl3  "RT_Weekend:vendor/odin-imgui/imgui_impl_opengl3"
```

---

## File prefix conventions

| Prefix | Responsibility | Framework dependency |
|---|---|---|
| `app.odin` | Entry point, main loop, `App` struct, `run_app` | Raylib (window) + ImGui |
| `imgui_*.odin` | Dear ImGui bridge and panel windows | ImGui — these are the new UI layer |
| `ui_*` | **Legacy** Raylib display infrastructure: panel chrome, fonts, layout engine, menus | Raylib — will be deleted in Track F |
| `panel_*` | Per-panel draw + update callbacks; being migrated one-by-one to ImGui | Mixed during migration |
| `core_*` | Framework-agnostic logic: commands, history, scene state, outliner. No Raylib/ImGui | None — survives any UI framework swap |
| `edit_view_*.odin` | 3D viewport: orbit camera, picking, drag, nudge, toolbar, input state machine | Raylib (3D draw calls, stays in Raylib) |

---

## App & run loop

`App` struct and `run_app` live in **app.odin**.

**Frame loop (draw phase):**
```
rl.BeginDrawing()
  rl.ClearBackground(...)
  imgui_rl_new_frame()          ← feed Raylib input to ImGui IO
  imgui_draw_all_panels(app)    ← DockSpace + menu bar + all panel windows
  imgui_rl_render()             ← submit ImGui draw data to OpenGL
  file_modal_draw(app)          ← legacy Raylib modal overlay (Track E: replace with BeginPopupModal)
  save_changes_modal_draw(app)  ← legacy Raylib modal overlay
  confirm_load_modal_draw(app)  ← legacy Raylib modal overlay
rl.EndDrawing()
```

**`imgui_draw_all_panels`** (in `imgui_panels_stub.odin`) is the single call-site for all ImGui UI:
1. `imgui.DockSpaceOverViewport` — full-screen dockspace with `PassthruCentralNode`
2. `imgui_draw_main_menu_bar` — File / Edit / View / Examples / Render menus
3. `imgui_draw_*_panel` — one proc per panel; skips if `app.e_panel_vis.<panel>` is false

---

## Panel visibility

`ImguiPanelVis` (in `imgui_panel_vis.odin`) holds one `bool` per panel.
Each bool is passed as `p_open` to `imgui.Begin` so ImGui's X button closes the panel directly.

```odin
App :: struct {
    e_panel_vis: ImguiPanelVis,
    // ...
}
```

`toggle_panel(app, PANEL_ID_*)` and `panel_visible(app, PANEL_ID_*)` route through
`_imgui_panel_vis_ptr` so all existing commands and keyboard shortcuts continue to work.

**Keyboard shortcuts (in `run_app`):**

| Key | Panel opened |
|---|---|
| `L` | Console |
| `S` | System Info |
| `E` | Viewport |
| `C` | Camera |
| `O` | Details |
| `T` | Texture View |
| `B` | Content Browser (also sets `scan_requested`) |

---

## Panels

| File | Panel | Migration track |
|---|---|---|
| `panel_render.odin` | Render Preview | Track C |
| `panel_stats.odin` | Stats | Track A |
| `panel_console.odin` | Console | Track A |
| `panel_system_info.odin` | System Info | Track A |
| `panel_viewport.odin` | Viewport | Track C |
| `panel_camera.odin` | Camera | Track B |
| `panel_details.odin` | Details | Track D |
| `panel_camera_preview.odin` | Camera Preview | Track C |
| `panel_texture_view.odin` | Texture View | Track A |
| `panel_content_browser.odin` | Content Browser | Track A |
| `panel_outliner.odin` | World Outliner | Track B |
| `panel_file_modal.odin` | File modal (Preset Name; Import/Save As fallback) | Track E |
| `panel_confirm_modal.odin` | Save Changes? + Load Example modals | Track E |

---

## How to migrate a panel (Tracks A–E)

1. Find the stub in `imgui_panels_stub.odin` (e.g. `imgui_draw_stats_panel`).
2. Replace the `imgui.Text("(... pending)")` body with real ImGui widgets (`imgui.Text`, `imgui.ProgressBar`, `imgui.PlotLines`, etc.).
3. The panel's old `draw_*_content` proc in `panel_*.odin` can be left in place until Track F deletes it.
4. For modals (Track E): add `imgui.OpenPopup` / `imgui.BeginPopupModal` logic; remove the corresponding `*_draw` and `*_update` calls from the main loop in `app.odin`.

**Viewport panels** (Track C) render to an off-screen `rl.RenderTexture2D` first:
```odin
rl.BeginTextureMode(app.e_edit_view.viewport_tex)
  // Raylib 3D drawing
rl.EndTextureMode()
// Then in imgui_draw_viewport_panel:
imgui.Image(...)  // display with UV flip ({0,1}→{1,0}) — Raylib textures are Y-flipped
```

---

## Commands

**core_commands.odin**: `Command`, `CommandRegistry`, `cmd_register`, `cmd_execute`, `CMD_*` constants.
**core_cmd_actions.odin**: all action procs; `toggle_panel` / `panel_visible` use `ImguiPanelVis`.

Layout preset commands (`CMD_VIEW_PRESET_*`) are no-ops — Dear ImGui persists layout in `imgui.ini`.

---

## File dialogs and unsaved state

- **Import** and **Save As** use native OS dialogs via `util` (`open_file_dialog`, `save_file_dialog`, `dialog_default_dir`).
- **Save Changes?** appears when exiting or importing with unsaved changes (rendered as Raylib overlay until Track E).
- **Load Example Scene?** always shows a confirmation (same).
- `app.e_scene_dirty` tracks unsaved edits; `mark_scene_dirty(app)` sets it.
- `file_import_from_path` / `file_save_as_path` perform load/save and reset dirty state.

---

## Keyboard state

**input_keyboard.odin**: `KeyboardState`, `keyboard_update(&app.keyboard)` called once per frame.
Keyboard shortcuts in `run_app` are gated by `!app.input_consumed && !imgui_rl_want_capture_keyboard()`
so they don't fire while ImGui has a text widget focused or while a modal is active.

---

## Naming / scope prefixes

| Prefix | Used for |
|---|---|
| `e_` | Editor state fields in `App` (e.g. `e_edit_view`, `e_panel_vis`, `e_details`) |
| `r_` | Render state (`app.r_camera`, `app.r_session`, `app.r_world`) |
| `c_` | Core params (`app.c_camera_params`) |

---

## Dependency rule

**editor** imports **core**, **util**, **raytrace**, **persistence**.
Layout/types for persistence (`EditorLayout`, `PanelState`) are defined in **persistence**.
Dear ImGui is imported as a local vendor submodule (`RT_Weekend:vendor/odin-imgui`).

---

## Orbit camera and viewport (unchanged from before migration)

The viewport uses two camera concepts:

1. **Orbit camera** (`EditViewState`) — the 3D editor viewport camera; orbits a target point via yaw/pitch/distance. Rendered to `app.e_edit_view.viewport_tex` with Raylib `BeginMode3D`.
2. **Render camera** (`app.c_camera_params`) — the path-tracer camera with lookfrom/lookat/vup/vfov/shutter.

Key files: `edit_view_state.odin`, `edit_view_camera_math.odin`, `edit_view_input.odin`, `edit_view_nudge.odin`, `ui_viewport_scene.odin`.

**From View** copies orbit lookfrom/lookat into `c_camera_params` without overwriting vup (preserves roll).

---

## UI event logging (`ui_event_log.odin`)

Build-time flag: `UI_EVENT_LOG_ENABLED :: #config(UI_EVENT_LOG_ENABLED, ODIN_DEBUG)` — compiled out in release.
Runtime toggle: `app.ui_event_log_enabled` (default `false`).
Chrome trace output controlled independently by `TRACE_CAPTURE_ENABLED` + Render menu.
