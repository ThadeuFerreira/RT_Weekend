# editor — Editor application

This package is the **editor**: Raylib window, panels, menus, layout, widgets, fonts. It depends on **core**, **util**, **raytrace**, and **persistence**. The editor is **separate from the renderer** (raytrace); it uses the renderer and does not mix rendering logic with UI.

## Purpose

- **App & run loop** — `App`, `run_app` in **app.odin**; panel registration, render start/finish, config save on exit.
- **Panels** — Render preview, Stats, Log, System Info, Edit View, Camera, Object Properties, Preview Port; each has `draw_content` (and optionally `update_content`). IDs: `PANEL_ID_RENDER`, `PANEL_ID_STATS`, etc.
- **Menus** — **menu_bar.odin**: `MenuBarState`, `menu_bar_update`, `menu_bar_draw`; commands bound via **commands.odin** / **command_actions.odin**.
- **Layout** — **layout.odin**: `DockLayout`, dock nodes, splits, `layout_update_and_draw`, `layout_build_default`. **layout_presets.odin**: `layout_build_render_focus`, `layout_build_edit_focus`, `layout_save_named_preset`, `layout_apply_named_preset`.
- **Widgets** — **ui.odin**: `PanelStyle`, `update_panel`, `draw_panel_chrome`, `upload_render_texture`.
- **Fonts** — **font_sdf.odin**: SDF font loading; `draw_ui_text` / `measure_ui_text` in app.odin.
- **Commands** — **commands.odin**: `Command`, `CommandRegistry`, `cmd_register`, `cmd_execute`, CMD_* constants. **command_actions.odin**: file new/import/save/save as/exit, view toggles, layout presets, render restart.
- **File modal** — **file_modal.odin**: Import / Save As / Preset Name dialog; uses **persistence** for load_scene/save_scene.
- **Viewport / picking** — **viewport.odin**: `EditorObject`, `compute_viewport_ray`, `ray_hit_plane_y`, `pick_camera`. **scene_manager.odin**: `SceneManager`, `LoadFromSceneSpheres`, `ExportToSceneSpheres`, `GetSceneSphere`, `SetSceneSphere`, etc. **materials.odin**: `material_name(k: core.MaterialKind)`.

## Naming / scope

Use idiomatic Odin names for editor types/functions. Use scoped variable/field prefixes: `e_` for editor state (e.g. `e_edit_view`, `e_menu_bar`, `e_object_props`, `e_camera_panel`), `r_` for render state (`app.r_camera`, `app.r_session`, `app.r_world`), and `c_` for core params (`app.c_camera_params`).

Panel content procs live in: **rt_render_panel.odin**, **stats_panel.odin**, **log_panel.odin**, **system_info.odin**, **edit_view_panel.odin**, **camera_panel.odin**, **camera_preview_panel.odin**, **object_props_panel.odin**.

## Dependency rule

**editor** imports **core**, **util**, **raytrace**, **persistence**. Layout/types for persistence (e.g. `EditorLayout`, `PanelState`) are defined in **persistence**; editor uses them and calls `persistence.load_config` / `save_config` for I/O.
