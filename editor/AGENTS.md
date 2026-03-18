# editor — Editor application

This package is the **editor**: Raylib window, Dear ImGui panels, menus, layout, scene editing.
It depends on **core**, **util**, **raytrace**, and **persistence**.
The editor is **separate from the renderer** (raytrace); it uses the renderer and does not mix rendering logic with UI.

## UI framework: Dear ImGui (migration complete)

The editor has been fully migrated from a hand-rolled Raylib panel system to **Dear ImGui v1.91.7-docking** (Issue #136, branch `136-migrate-ui-elements-to-dear-imgui`).

### Migration status

| Layer | File(s) | Status |
|---|---|---|
| ImGui bridge | `imgui_rl.odin` | ✅ Done |
| Panel visibility | `imgui_panel_vis.odin` | ✅ Done |
| DockSpace + menu bar + all panels | `imgui_panels_stub.odin` | ✅ Done |
| Console, Stats, System Info | `panel_console.odin` etc. | ✅ Track A |
| Outliner, Camera | `panel_outliner.odin` etc. | ✅ Track B |
| Render Preview, Viewport | `panel_render.odin` etc. | ✅ Track C |
| Details | `panel_details.odin` | ✅ Track D |
| Modals + menu bar | `panel_confirm_modal.odin` etc. | ✅ Track E |
| Delete legacy Raylib files | `ui_*.odin`, `panel_registry.odin` | ✅ Track F |

All legacy Raylib UI infrastructure files have been deleted:
- `ui_chrome.odin` — panel chrome, color constants → constants moved to `app.odin`
- `ui_layout.odin` — DockLayout tree → replaced by `imgui.DockSpaceOverViewport`
- `ui_layout_presets.odin` — layout presets → ImGui persists layout in `imgui.ini`
- `ui_menu_bar.odin` — Raylib menus → `imgui.BeginMainMenuBar` in `imgui_panels_stub.odin`
- `ui_components.odin` — Raylib widgets → ImGui widgets
- `panel_registry.odin` — panel registration → explicit `cmd_register` calls in `core_cmd_actions.odin`
- `edit_view_properties.odin` — inline property widgets → ImGui panels handle this

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
| `imgui_*.odin` | Dear ImGui bridge and panel windows | ImGui — the UI layer |
| `panel_*` | Per-panel state, logic, and ImGui draw procs | ImGui |
| `core_*` | Framework-agnostic logic: commands, history, scene state. No Raylib/ImGui | None |
| `edit_view_*.odin` | 3D viewport: orbit camera, picking, drag, nudge, toolbar, input state machine | Raylib (3D draw calls) |
| `ui_font.odin` | SDF font loading (optional) | Raylib |
| `ui_viewport_scene.odin` | 3D scene object drawing (spheres, quads, gizmos) | Raylib |

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
rl.EndDrawing()
```

**`imgui_draw_all_panels`** (in `imgui_panels_stub.odin`) is the single call-site for all ImGui UI:
1. `imgui.DockSpaceOverViewport` — full-screen dockspace with `PassthruCentralNode`
2. `imgui_draw_main_menu_bar` — File / Edit / View / Examples / Render menus
3. `imgui_draw_*_panel` — one proc per panel; skips if `app.e_panel_vis.<panel>` is false
4. `imgui_draw_file_modal` — file/preset name popup
5. `imgui_draw_save_changes_modal` — unsaved-changes popup
6. `imgui_draw_confirm_load_modal` — confirm example-load popup

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

| File | Panel |
|---|---|
| `panel_render.odin` | Render Preview |
| `panel_stats.odin` | Stats |
| `panel_console.odin` | Console |
| `panel_system_info.odin` | System Info |
| `panel_viewport.odin` | Viewport |
| `panel_camera.odin` | Camera |
| `panel_details.odin` | Details |
| `panel_camera_preview.odin` | Camera Preview |
| `panel_texture_view.odin` | Texture View |
| `panel_content_browser.odin` | Content Browser |
| `panel_outliner.odin` | World Outliner |
| `panel_file_modal.odin` | File modal (Import/Save As fallback) |
| `panel_confirm_modal.odin` | Save Changes? + Load Example modals |

---

## 3D Viewport

The viewport renders to an off-screen `rl.RenderTexture2D` each frame, then displays it as an ImGui image:

```odin
// In imgui_draw_viewport_panel (imgui_panels_stub.odin):
render_viewport_to_texture(&app, width, height)   // Raylib 3D drawing
imgui.Image(...)                                   // UV-flipped (Raylib Y-flip)
// ImGui input rect from GetItemRectMin/Max → feeds existing Raylib input handlers
```

Key files: `panel_viewport.odin` (render + grid), `edit_view_state.odin`, `edit_view_camera_math.odin`,
`edit_view_input.odin`, `edit_view_nudge.odin`, `ui_viewport_scene.odin`.

**From View** copies orbit lookfrom/lookat into `c_camera_params` without overwriting vup (preserves roll).

---

## Commands

**core_commands.odin**: `Command`, `CommandRegistry`, `cmd_register`, `cmd_execute`, `CMD_*` constants.
**core_cmd_actions.odin**: all action procs; `toggle_panel` / `panel_visible` use `ImguiPanelVis`.

Layout preset commands (`CMD_VIEW_PRESET_*`) are no-ops — Dear ImGui persists layout in `imgui.ini`.

---

## File dialogs and unsaved state

- **Import** and **Save As** use native OS dialogs via `util` (`open_file_dialog`, `save_file_dialog`, `dialog_default_dir`).
- **Save Changes?** appears when exiting or importing with unsaved changes (ImGui popup modal).
- **Load Example Scene?** always shows a confirmation (ImGui popup modal).
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
Dear ImGui is imported as a local vendor submodule (`RT_Weekend:vendor/odin-imgui`).

---

## UI event logging (`ui_event_log.odin`)

Build-time flag: `UI_EVENT_LOG_ENABLED :: #config(UI_EVENT_LOG_ENABLED, ODIN_DEBUG)` — compiled out in release.
Runtime toggle: `app.ui_event_log_enabled` (default `false`).
Chrome trace output controlled independently by `TRACE_CAPTURE_ENABLED` + Render menu.
