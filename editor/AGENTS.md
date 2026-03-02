# editor — Editor application

This package is the **editor**: Raylib window, panels, menus, layout, widgets, fonts. It depends on **core**, **util**, **raytrace**, and **persistence**. The editor is **separate from the renderer** (raytrace); it uses the renderer and does not mix rendering logic with UI.

## File prefix conventions

Files are grouped by prefix to separate responsibilities. This makes the UI-framework boundary explicit — if the project ever switches from Raylib to ImGUI, only the `ui_*` and `panel_*` files need rewriting; `core_*` survives untouched.

| Prefix | Responsibility | Raylib dependency |
|---|---|---|
| `app.odin` | Entry point, main loop, `App` struct, `run_app` | Yes |
| `ui_*` | Raylib display infrastructure: panel chrome, fonts, layout engine, menus, 3D viewport math, gizmos | Yes — replace these when switching UI frameworks |
| `panel_*` | Per-panel draw + update callbacks; mix Raylib calls with editor logic, scoped per feature | Yes |
| `core_*` | Framework-agnostic logic: commands, history, scene state. No Raylib | No — survives a UI framework swap untouched |

## Purpose

- **App & run loop** — `App`, `run_app` in **app.odin**; panel registration, render start/finish, config save on exit.
- **Panels** — Render preview, Stats, Log, System Info, Edit View, Camera, Object Properties, Preview Port; each has `draw_content` (and optionally `update_content`). IDs: `PANEL_ID_RENDER`, `PANEL_ID_STATS`, etc.
- **Menus** — **ui_menu_bar.odin**: `MenuBarState`, `menu_bar_update`, `menu_bar_draw`; commands bound via **core_commands.odin** / **core_cmd_actions.odin**.
- **Layout** — **ui_layout.odin**: `DockLayout`, dock nodes, splits, `layout_update_and_draw`, `layout_build_default`. **ui_layout_presets.odin**: `layout_build_render_focus`, `layout_build_edit_focus`, `layout_save_named_preset`, `layout_apply_named_preset`.
- **Widgets** — **ui_chrome.odin**: `PanelStyle`, `update_panel`, `draw_panel_chrome`, `upload_render_texture`.
- **Fonts** — **ui_font.odin**: SDF font loading; `draw_ui_text` / `measure_ui_text` in app.odin.
- **Commands** — **core_commands.odin**: `Command`, `CommandRegistry`, `cmd_register`, `cmd_execute`, CMD_* constants. **core_cmd_actions.odin**: file new/import/save/save as/exit, view toggles, layout presets, render restart.
- **File modal** — **panel_file_modal.odin**: Import / Save As / Preset Name dialog; uses **persistence** for load_scene/save_scene.
- **Viewport / picking** — **ui_viewport.odin**: `EditorObject`, `compute_viewport_ray`, `ray_hit_plane_y`, `pick_camera`. **core_scene.odin**: `SceneManager`, `LoadFromSceneSpheres`, `ExportToSceneSpheres`, `GetSceneSphere`, `SetSceneSphere`, etc. **core_materials.odin**: `material_name(k: core.MaterialKind)`.

## Panel content files

| File | Panel |
|---|---|
| `panel_render.odin` | Render Preview |
| `panel_stats.odin` | Stats |
| `panel_log.odin` | Log |
| `panel_system_info.odin` | System Info |
| `panel_edit_view.odin` | Edit View |
| `panel_camera.odin` | Camera |
| `panel_preview.odin` | Camera Preview Port |
| `panel_obj_props.odin` | Object Properties |
| `panel_file_modal.odin` | File / Import / Save As dialog |

## Naming / scope

Use idiomatic Odin names for editor types/functions. Use scoped variable/field prefixes: `e_` for editor state (e.g. `e_edit_view`, `e_menu_bar`, `e_object_props`, `e_camera_panel`), `r_` for render state (`app.r_camera`, `app.r_session`, `app.r_world`), and `c_` for core params (`app.c_camera_params`).

## Dependency rule

**editor** imports **core**, **util**, **raytrace**, **persistence**. Layout/types for persistence (e.g. `EditorLayout`, `PanelState`) are defined in **persistence**; editor uses them and calls `persistence.load_config` / `save_config` for I/O.
