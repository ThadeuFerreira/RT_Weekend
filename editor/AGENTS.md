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
- **File dialogs** — **Import** and **Save As** use native OS dialogs via **util** (`open_file_dialog`, `save_file_dialog`, `dialog_default_dir`). Default directory when no file is open is `<cwd>/scenes`. **panel_file_modal.odin** is used only for **Preset Name** (and for Import/Save As when `FILE_MODAL_FALLBACK` is true). `file_import_from_path` / `file_save_as_path` perform load/save; both reset `e_scene_dirty` and `file_import_from_path` resets edit history.
- **Save Changes modal** — **panel_confirm_modal.odin**: when exiting or importing with unsaved changes, a “Save Changes?” dialog offers **Save** (overwrite), **Save As** (pick path), **Cancel**, **Continue** (discard). Proceeds only if save succeeds (or user chose Continue/Cancel). `cmd_action_file_save` and `file_save_as_path` return `bool` so callers can avoid proceeding on failure.
- **Confirm-load modal** — Same file: “Load Example Scene?” with **Save & Load** (enabled only when `e_scene_dirty`; uses Save As if no path), **Load**, **Cancel**. Always shown when loading an example; load is performed by `_load_example_at`.
- **Unsaved state** — `app.e_scene_dirty` is set by `mark_scene_dirty(app)` on any edit (sphere/camera/material, undo/redo); cleared on save, load, or new. Used to gate Save Changes and to enable “Save & Load” in the example-load dialog.
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
| `panel_file_modal.odin` | File modal (Preset Name; Import/Save As only with FILE_MODAL_FALLBACK). `file_import_from_path`, `file_save_as_path`. |
| `panel_confirm_modal.odin` | Save Changes? (exit/import when dirty); Load Example confirmation. |

## Naming / scope

Use idiomatic Odin names for editor types/functions. Use scoped variable/field prefixes: `e_` for editor state (e.g. `e_edit_view`, `e_menu_bar`, `e_object_props`, `e_camera_panel`), `r_` for render state (`app.r_camera`, `app.r_session`, `app.r_world`), and `c_` for core params (`app.c_camera_params`).

## Dependency rule

**editor** imports **core**, **util**, **raytrace**, **persistence**. Layout/types for persistence (e.g. `EditorLayout`, `PanelState`) are defined in **persistence**; editor uses them and calls `persistence.load_config` / `save_config` for I/O.

---

## Orbit camera and Yaw / Pitch / Roll

The Edit View has two camera concepts:

1. **Orbit camera** — The 3D viewport camera. It **orbits** a target point using spherical coordinates: **yaw**, **pitch**, **orbit_distance**, **orbit_target**. The view direction is computed from these; the viewport always uses world up `(0, 1, 0)` (no roll). Updated by `update_orbit_camera(ev)`; pose for syncing to the renderer by `get_orbit_camera_pose(ev)` (returns only lookfrom/lookat; vup is left unchanged to preserve roll).

2. **Render camera** — The path-tracer camera (`app.c_camera_params`: lookfrom, lookat, **vup**, vfov, …). **Roll** is stored only here, as **vup** (up vector). Yaw/pitch/distance are implicit in lookfrom/lookat. The property strip (when the camera is selected) edits this camera; roll is edited via the Roll field and is independent of yaw/pitch (each gimbal is independent).

**Yaw** — Horizontal angle (radians) around world Y; 0 = -Z, increasing toward +X.  
**Pitch** — Vertical angle (radians); clamped to ±π×0.45 to avoid gimbal lock at straight up/down.  
**Roll** — Tilt of the camera around the view axis (radians); only affects the render camera’s **vup**. Allowed in full range ±π (no gimbal lock).  
**Orbit** — Editor camera: **orbit_target** (point in world) and **orbit_distance** (distance from target). Camera position = target + spherical offset from yaw/pitch/distance.

**From View** copies the orbit camera’s lookfrom/lookat into `c_camera_params` and does **not** overwrite vup, so the current roll is preserved.

---

## Edit View data structures

**EditViewSelectionKind** — What is selected in the viewport:

- `None` — Nothing selected.
- `Sphere` — A scene sphere; `selected_idx` is the index into the scene objects.
- `Camera` — The render camera (gizmo); not deletable.

**EditViewState** — State for the Edit View panel (lives in `app.e_edit_view`):

| Field | Purpose |
|-------|--------|
| `viewport_tex`, `tex_w`, `tex_h` | Off-screen 3D viewport texture and size. |
| `cam3d` | Raylib 3D camera; recomputed each frame from orbit params (no roll). |
| `camera_yaw`, `camera_pitch` | Orbit angles (radians). |
| `orbit_distance`, `orbit_target` | Distance from and world position of orbit target. |
| `rmb_held`, `last_mouse`, `rmb_press_pos`, `rmb_drag_dist` | Right-drag orbit and disambiguation for context menu. |
| `ctx_menu_open`, `ctx_menu_pos`, `ctx_menu_hit_idx` | Context menu state. |
| `scene_mgr`, `export_scratch` | Scene manager and scratch buffer for export. |
| `selection_kind`, `selected_idx` | Current selection (see EditViewSelectionKind). |
| `prop_drag_idx`, `prop_drag_start_x`, `prop_drag_start_val` | Sphere property strip drag (cx, cy, cz, radius). |
| `drag_obj_active`, `drag_plane_y`, `drag_offset_xz`, `drag_before` | Viewport drag to move selected sphere. |
| `nudge_active`, `nudge_before` | Keyboard nudge state. |
| `cam_prop_drag_idx`, `cam_prop_drag_start_x`, `cam_prop_drag_start_val` | Camera property strip drag (Pos X/Y/Z, Yaw, Pitch, Dst, Roll). |
| `cam_drag_active`, `cam_drag_plane_y`, `cam_drag_start_hit_xz`, `cam_drag_start_lookfrom`, `cam_drag_start_lookat`, `cam_drag_before_params` | Camera body drag in viewport; full camera params at drag start for undo. |
| `cam_rot_drag_axis`, `cam_rot_drag_start_x`, `cam_rot_drag_start_y` | Camera rotation ring drag (world-axis rings). |
| `show_frustum_gizmo`, `show_focal_indicator` | Toolbar toggles for gizmos. |
| `initialized` | One-time init done. |

Key procedures: `init_edit_view`, `update_orbit_camera`, `get_orbit_camera_pose`, `draw_viewport_3d`, `draw_edit_properties`, `update_edit_view_content`. Camera basis/roll helpers: `_compute_camera_basis`, `compute_vup_from_forward_and_roll`, `roll_from_vup`, `lookat_from_angles`, `lookat_from_forward`, `cam_forward_angles`, `cam_orbit_prop_rects`.
