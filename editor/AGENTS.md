# editor — Editor application

This package is the **editor**: Raylib window, panels, menus, layout, widgets, fonts. It depends on **core**, **util**, **raytrace**, and **persistence**. The editor is **separate from the renderer** (raytrace); it uses the renderer and does not mix rendering logic with UI.

## File prefix conventions

Files are grouped by prefix to separate responsibilities. This makes the UI-framework boundary explicit — if the project ever switches from Raylib to ImGUI, only the `ui_*` and `panel_*` files need rewriting; `core_*` survives untouched.

| Prefix | Responsibility | Raylib dependency |
|---|---|---|
| `app.odin` | Entry point, main loop, `App` struct, `run_app` | Yes |
| `ui_*` | Raylib display infrastructure: panel chrome, fonts, layout engine, menus, 3D viewport math, gizmos | Yes — replace these when switching UI frameworks |
| `panel_*` | Per-panel draw + update callbacks; mix Raylib calls with editor logic, scoped per feature | Yes |
| `core_*` | Framework-agnostic logic: commands, history, scene state, **outliner** (row count, row→selection, labels, scroll). No Raylib | No — survives a UI framework swap untouched |

## Purpose

- **App & run loop** — `App`, `run_app` in **app.odin**; panel registration, render start/finish, config save on exit.
- **Panels** — Render Preview, Stats, Console, System Info, Viewport, Camera, Details, Camera Preview, Texture View, Content Browser, World Outliner; each has `draw_content` (and optionally `update_content`). IDs: `PANEL_ID_RENDER`, `PANEL_ID_STATS`, `PANEL_ID_CONSOLE`, `PANEL_ID_VIEWPORT`, `PANEL_ID_DETAILS`, `PANEL_ID_CAMERA_PREVIEW`, `PANEL_ID_TEXTURE_VIEW`, `PANEL_ID_CONTENT_BROWSER`, `PANEL_ID_OUTLINER`, etc.
- **Menus** — **ui_menu_bar.odin**: `MenuBarState`, `menu_bar_update`, `menu_bar_draw`; commands bound via **core_commands.odin** / **core_cmd_actions.odin**.
- **Layout** — **ui_layout.odin**: `DockLayout`, dock nodes, splits, `layout_update_and_draw`, `layout_build_default`. **ui_layout_presets.odin**: `layout_build_render_focus`, `layout_build_edit_focus`, `layout_save_named_preset`, `layout_apply_named_preset`.
- **Widgets** — **ui_chrome.odin**: `PanelStyle`, `update_panel`, `draw_panel_chrome`, `upload_render_texture`. **ui_components.odin**: reusable Button, Toggle, Dropdown (structs + draw/hit procs); styles: `DEFAULT_BUTTON_STYLE`, `BUTTON_STYLE_DANGER`, `BUTTON_STYLE_SUCCESS`, `BUTTON_STYLE_NEUTRAL`, `DEFAULT_TOGGLE_STYLE`, `TOGGLE_STYLE_ON_RED`; compose toolbars and panels from these.
- **Keyboard** — **input_keyboard.odin**: singleton-style `KeyboardState`; `keyboard_update(&app.keyboard)` called once per frame in the main loop. Use `app.keyboard` instead of `rl.IsKeyDown` in features (nudge, etc.) so key handling is centralized.
- **Fonts** — **ui_font.odin**: SDF font loading; `draw_ui_text` / `measure_ui_text` in app.odin.
- **Commands** — **core_commands.odin**: `Command`, `CommandRegistry`, `cmd_register`, `cmd_execute`, CMD_* constants. **core_cmd_actions.odin**: file new/import/save/save as/exit, view toggles, layout presets, render restart.
- **File dialogs** — **Import** and **Save As** use native OS dialogs via **util** (`open_file_dialog`, `save_file_dialog`, `dialog_default_dir`). Default directory when no file is open is `<cwd>/scenes`. **panel_file_modal.odin** is used only for **Preset Name** (and for Import/Save As when `FILE_MODAL_FALLBACK` is true). `file_import_from_path` / `file_save_as_path` perform load/save; both reset `e_scene_dirty` and `file_import_from_path` resets edit history.
- **Save Changes modal** — **panel_confirm_modal.odin**: when exiting or importing with unsaved changes, a "Save Changes?" dialog offers **Save** (overwrite), **Save As** (pick path), **Cancel**, **Continue** (discard). Proceeds only if save succeeds (or user chose Continue/Cancel). `cmd_action_file_save` and `file_save_as_path` return `bool` so callers can avoid proceeding on failure.
- **Confirm-load modal** — Same file: "Load Example Scene?" with **Save & Load** (enabled only when `e_scene_dirty`; uses Save As if no path), **Load**, **Cancel**. Always shown when loading an example; load is performed by `_load_example_at`.
- **Unsaved state** — `app.e_scene_dirty` is set by `mark_scene_dirty(app)` on any edit (sphere/camera/material, undo/redo); cleared on save, load, or new. Used to gate Save Changes and to enable "Save & Load" in the example-load dialog.
- **Viewport / picking** — **ui_viewport.odin**: `EditorObject`, `compute_viewport_ray`, `ray_hit_plane_y`, `pick_camera`. **core_scene.odin**: `SceneManager`, `LoadFromSceneSpheres`, `ExportToSceneSpheres`, `GetSceneSphere`, `SetSceneSphere`, etc. **core_materials.odin**: `material_name(k: core.MaterialKind)`.

## Panel content files

| File | Panel |
|---|---|
| `panel_render.odin` | Render Preview; also `get_render_aspect(app)`, `get_aspect_ratio(idx)`, `calculate_render_dimensions(app)`, resolution bounds. |
| `panel_stats.odin` | Stats |
| `panel_console.odin` | Console (was: Log) |
| `panel_system_info.odin` | System Info |
| `panel_viewport.odin` | Viewport (was: Edit View) — viewport draw/update, toolbar draw, render button; delegates to edit_view_* and ui_viewport_scene. |
| `panel_camera.odin` | Camera (includes **shutter open/close** for motion blur). |
| `panel_camera_preview.odin` | Camera Preview (was: Preview Port) — uses `get_render_aspect`, shared scene drawing (no interactions). |
| `panel_details.odin` | Details (was: Object Properties) (camera: shutter; sphere: **MOTION** section with **dX/dY/dZ** = center1 − center, undo/dirty on edit). |
| `panel_content_browser.odin` | Content Browser — scans `assets/textures` and `scenes`, supports filter/search, texture assignment, scene open, and texture preview. |
| `panel_outliner.odin` | World Outliner — scrollable list of all scene objects (spheres, quads, volumes); click to select. Thin view glue: input/draw only; logic in **core_outliner.odin**. |
| `panel_file_modal.odin` | File modal (Preset Name; Import/Save As only with FILE_MODAL_FALLBACK). `file_import_from_path`, `file_save_as_path`. |
| `panel_confirm_modal.odin` | Save Changes? (exit/import when dirty); Load Example confirmation. |

## Panel ID rename map (for reference / legacy config migration)

| Old ID | New ID | Old name | New name |
|---|---|---|---|
| `"edit_view"` | `PANEL_ID_VIEWPORT = "viewport"` | Edit View | Viewport |
| `"object_props"` | `PANEL_ID_DETAILS = "details"` | Object Properties | Details |
| `"log"` | `PANEL_ID_CONSOLE = "console"` | Log | Console |
| `"preview_port"` | `PANEL_ID_CAMERA_PREVIEW = "camera_preview"` | Preview Port | Camera Preview |
| *(new)* | `PANEL_ID_OUTLINER = "outliner"` | — | World Outliner |

Old configs using the legacy IDs load correctly via `_panel_id_translate` in `apply_editor_layout` (app.odin).

## How to add a new panel

Panels are declared once in `PANEL_REGISTRY` (`panel_registry.odin`). `run_app`, `register_all_commands`, and `get_menus_dynamic` all drive off that table automatically.

1. Create `panel_<name>.odin` with `draw_<name>_content` and optionally `update_<name>_content` procs.
2. Define `PANEL_ID_<NAME> :: "<name>"` in `app.odin`.
3. Optionally add `<Name>PanelState` to `App` struct (field prefix `e_`).
4. Define `CMD_VIEW_<NAME>` in `core_commands.odin`; add `cmd_action_view_<name>` / `cmd_checked_view_<name>` stubs in `core_cmd_actions.odin`.
5. Add one `PanelDescriptor` entry to `PANEL_REGISTRY` in `panel_registry.odin` — that's it.

**Edit View split (shared / state / UI):**

| File | Responsibility |
|---|---|
| `edit_view_state.odin` | `EditViewState`, `ViewportSphereCacheEntry`, `init_edit_view`, `update_orbit_camera`, `get_orbit_camera_pose`. |
| `edit_view_camera_math.odin` | Camera basis, roll, yaw/pitch: `_compute_camera_basis`, `compute_vup_from_forward_and_roll`, `cam_forward_angles`, `roll_from_vup`, `lookat_from_angles`, `lookat_from_forward`. |
| `edit_view_properties.odin` | Property strip: `EDIT_PROPS_H`, `PROP_*`, `cam_orbit_prop_rects`, `prop_field_rects`, `draw_drag_field`, `draw_edit_properties`. |
| `edit_view_context_menu.odin` | Context menu: `ctx_menu_build_items`, `ctx_menu_screen_rect`, `draw_edit_view_context_menu`. |
| `edit_view_toolbar.odin` | Toolbar layout: `EDIT_TOOLBAR_H`, `edit_view_aabb_toolbar_rects`, `edit_view_add_dropdown_rects`, `ADD_DROPDOWN_*`. |
| `edit_view_nudge.odin` | Keyboard nudge for selected sphere: `update_sphere_nudge(app, ev)`; uses `app.keyboard` (move/radius, undo on release). Reusable from any code with App + EditViewState. |
| `edit_view_input.odin` | Edit View input phase enum (`EditViewInputPhase`), `EditViewRects`, `get_edit_view_input_phase`, and handlers: context menu, cam rot/body/prop drag, sphere prop drag, viewport object drag, toolbar, prop-field start, viewport orbit/pick. `update_viewport_content` switches on phase and calls the appropriate handler. |
| `ui_viewport_scene.odin` | Shared 3D scene drawing and viewport cache: `draw_quad_3d`, `sphere_solid_color_from_albedo`, `draw_sphere_solid`, `draw_quad_with_material_color`, `flip_image_vertical_rgba`, `free_viewport_sphere_cache_entry`, `viewport_texture_from_albedo`, `ensure_viewport_sphere_cache_filled`, `draw_viewport_scene_objects`, `draw_viewport_camera_gizmos` (used by Viewport and Camera Preview). |

**Selection kind:** `EditViewSelectionKind` lives in **core_scene.odin** (used by picking and panels).

## UI event logging and tracing (`ui_event_log.odin`)

Centralized debug-only logging for UI mouse events, drag transitions, handler scopes, and lifecycle events.

**Build-time flag:** `UI_EVENT_LOG_ENABLED :: #config(UI_EVENT_LOG_ENABLED, ODIN_DEBUG)` — compiled out entirely in release builds (`#force_inline` + `when`).

**Runtime toggle:** `app.ui_event_log_enabled` (default `false`) — enables Console-panel and stderr output without rebuilding. Chrome trace output is controlled independently by `TRACE_CAPTURE_ENABLED` + the benchmark capture toggle (Render menu).

**Three output channels:**
| Channel | Content | When active |
|---------|---------|-------------|
| Chrome trace instant (`ui.mouse`) | Hover, Click, DragStart, DragEnd | While benchmark capture is running |
| Chrome trace duration (`ui.handler`) | Handler function scopes | While benchmark capture is running |
| Chrome trace instant (`ui.lifecycle`) | Create/Destroy | While benchmark capture is running |
| Console panel (`[ui] …`) | Click, DragStart/End, Lifecycle | `app.ui_event_log_enabled = true` |
| stderr | Hover per-frame (component + position) | `app.ui_event_log_enabled = true` |

**Grep prefixes:** `UI.Mouse.*`, `UI.Drag.*`, `UI.Lifecycle.*`; Chrome cat filters: `ui.mouse`, `ui.handler`, `ui.lifecycle`.

**Call sites:** `draw_button`, `draw_toggle`, `draw_dropdown_item` emit hover traces. All `handle_*` procs in `edit_view_input.odin` are wrapped with `ui_trace_handler_begin/end`. Drag start/end are logged at transition points in `edit_view_input.odin`, `edit_view_nudge.odin`.

## Naming / scope

Use idiomatic Odin names for editor types/functions. Use scoped variable/field prefixes: `e_` for editor state (e.g. `e_edit_view`, `e_menu_bar`, `e_details`, `e_camera_panel`, `e_outliner`), `r_` for render state (`app.r_camera`, `app.r_session`, `app.r_world`), and `c_` for core params (`app.c_camera_params`).

## Dependency rule

**editor** imports **core**, **util**, **raytrace**, **persistence**. Layout/types for persistence (e.g. `EditorLayout`, `PanelState`) are defined in **persistence**; editor uses them and calls `persistence.load_config` / `save_config` for I/O.

## Allocation preference

Prefer stack allocation; don't pass pointers unless strictly necessary. Example scenes return ground texture by value; app stores `custom_ground_texture: rt.Texture` and uses optional/flag for "no custom ground".

---

## Orbit camera and Yaw / Pitch / Roll

The Viewport has two camera concepts:

1. **Orbit camera** — The 3D viewport camera. It **orbits** a target point using spherical coordinates: **yaw**, **pitch**, **orbit_distance**, **orbit_target**. The view direction is computed from these; the viewport always uses world up `(0, 1, 0)` (no roll). Updated by `update_orbit_camera(ev)`; pose for syncing to the renderer by `get_orbit_camera_pose(ev)` (returns only lookfrom/lookat; vup is left unchanged to preserve roll).

2. **Render camera** — The path-tracer camera (`app.c_camera_params`: lookfrom, lookat, **vup**, vfov, **shutter_open**, **shutter_close**, …). **Roll** is stored only here, as **vup** (up vector). Yaw/pitch/distance are implicit in lookfrom/lookat. The property strip (when the camera is selected) edits this camera, including shutter; roll is edited via the Roll field and is independent of yaw/pitch (each gimbal is independent).

**Yaw** — Horizontal angle (radians) around world Y; 0 = -Z, increasing toward +X.
**Pitch** — Vertical angle (radians); clamped to ±π×0.45 to avoid gimbal lock at straight up/down.
**Roll** — Tilt of the camera around the view axis (radians); only affects the render camera's **vup**. Allowed in full range ±π (no gimbal lock).
**Orbit** — Editor camera: **orbit_target** (point in world) and **orbit_distance** (distance from target). Camera position = target + spherical offset from yaw/pitch/distance.

**From View** copies the orbit camera's lookfrom/lookat into `c_camera_params` and does **not** overwrite vup, so the current roll is preserved.

---

## Edit View data structures

**EditViewSelectionKind** — Defined in **core_scene.odin**. What is selected in the viewport:

- `None` — Nothing selected.
- `Sphere` — A scene sphere; `selected_idx` is the index into the scene objects.
- `Camera` — The render camera (gizmo); not deletable.

**EditViewState** — Defined in **edit_view_state.odin**; lives in `app.e_edit_view`.

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

Key procedures: `init_edit_view`, `update_orbit_camera`, `get_orbit_camera_pose` (edit_view_state); `draw_viewport_3d`, `draw_viewport_content`, `update_viewport_content` (panel_viewport); `draw_edit_properties` (edit_view_properties). Camera basis/roll: edit_view_camera_math. Property strip rects: edit_view_properties.
