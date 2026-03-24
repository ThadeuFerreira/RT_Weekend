package editor

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "RT_Weekend:core"
import "RT_Weekend:persistence"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:util"

// ── File actions ────────────────────────────────────────────────────────────

cmd_action_file_new :: proc(app: ^App) {
    if !app.finished { return }
    app.include_ground_plane = true
    app_set_ground_texture(app, nil)
    app_clear_image_texture_cache(app)

    rt.free_session(app.r_session)
    app.r_session = nil

    ev := &app.e_edit_view
    initial := [3]core.SceneSphere{
        {center = {-1.5, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = core.ConstantTexture{color={0.8, 0.2, 0.2}}},
        {center = { 0,   0.5, 0}, radius = 0.5, material_kind = .Metallic,   albedo = core.ConstantTexture{color={0.2, 0.2, 0.8}}, fuzz = 0.1},
        {center = { 1.5, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = core.ConstantTexture{color={0.2, 0.8, 0.2}}},
    }
    LoadFromSceneSpheres(ev.scene_mgr, initial[:])
    align_editor_camera_to_render(ev, app.c_camera_params, true)
    ev.selection_kind = .None
    ev.selected_idx   = -1

    delete(app.current_scene_path)
    app.current_scene_path = ""

    ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
    rt.free_world_volumes(app.r_world)
    delete(app.r_world)
    app.r_world = app_build_world_from_scene(app, ev.export_scratch[:])
    AppendQuadsToWorld(ev.scene_mgr, &app.r_world)
    app_append_volumes_to_world(app, &app.r_world)

    app.finished     = false
    app.elapsed_secs = 0

    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    rt.init_camera(app.r_camera)
    _ = app_start_render_session(app)
    app.e_scene_dirty = false
    app_push_log(app, strings.clone("New scene (3 default spheres)"))
}

// Single definition for fallback to text path modal when native dialog is unavailable. All when FILE_MODAL_FALLBACK branches live in this file. If another module needs this flag, move it to a shared build/config module.
FILE_MODAL_FALLBACK :: #config(FILE_MODAL_FALLBACK, false)

cmd_action_file_import :: proc(app: ^App) {
    if app.e_scene_dirty {
        save_changes_modal_open(&app.e_save_changes, .Import)
        return
    }
    default_dir := util.dialog_default_dir(app.current_scene_path)
    path, ok := util.open_file_dialog(default_dir, util.SCENE_FILTER_DESC, util.SCENE_FILTER_EXT)
    delete(default_dir)
    if ok {
        file_import_from_path(app, path)
    } else {
        when FILE_MODAL_FALLBACK {
            file_modal_open(&app.file_modal, .Import, "Import Scene (.json)")
        }
    }
}

// cmd_action_file_save saves to current_scene_path. Returns true on success, false if no path or save failed.
cmd_action_file_save :: proc(app: ^App) -> bool {
    if len(app.current_scene_path) == 0 { return false }
    ev := &app.e_edit_view
    ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
    world := app_build_world_from_scene(app, ev.export_scratch[:])
    AppendQuadsToWorld(ev.scene_mgr, &world)
    defer delete(world)
    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    if persistence.save_scene(app.current_scene_path, app.r_camera, world, app.e_volumes[:]) {
        app.e_scene_dirty = false
        app_push_log(app, fmt.aprintf("Saved: %s", app.current_scene_path))
        return true
    }
    app_push_log(app, fmt.aprintf("Save failed: %s", app.current_scene_path))
    return false
}

// Wrapper for menu binding (Command.action is proc(app: ^App)); discards return.
cmd_action_file_save_menu :: proc(app: ^App) {
    cmd_action_file_save(app)
}

cmd_action_file_save_enabled :: proc(app: ^App) -> bool {
    return len(app.current_scene_path) > 0
}

cmd_action_file_save_as :: proc(app: ^App) {
    default_dir := util.dialog_default_dir(app.current_scene_path)
    path, ok := util.save_file_dialog(default_dir, "scene.json", util.SCENE_FILTER_DESC, util.SCENE_FILTER_EXT)
    delete(default_dir)
    if ok {
        file_save_as_path(app, path)
    } else {
        when FILE_MODAL_FALLBACK {
            file_modal_open(&app.file_modal, .SaveAs, "Save Scene As (.json)")
        }
    }
}

cmd_action_file_exit :: proc(app: ^App) {
    if app.e_scene_dirty {
        save_changes_modal_open(&app.e_save_changes, .Exit)
    } else {
        app.should_exit = true
    }
}

// ── View panel toggle actions ─

toggle_panel :: proc(app: ^App, id: string) {
    if ptr := _imgui_panel_vis_ptr(&app.e_panel_vis, id); ptr != nil {
        ptr^ = !ptr^
    }
}

panel_visible :: proc(app: ^App, id: string) -> bool {
    if ptr := _imgui_panel_vis_ptr(&app.e_panel_vis, id); ptr != nil {
        return ptr^
    }
    return false
}

cmd_action_view_render :: proc(app: ^App) { toggle_panel(app, PANEL_ID_RENDER) }
cmd_action_view_stats  :: proc(app: ^App) { toggle_panel(app, PANEL_ID_STATS) }
cmd_action_view_console :: proc(app: ^App) { toggle_panel(app, PANEL_ID_CONSOLE) }
cmd_action_view_sysinfo:: proc(app: ^App) { toggle_panel(app, PANEL_ID_SYSTEM_INFO) }
cmd_action_view_edit   :: proc(app: ^App) { toggle_panel(app, PANEL_ID_VIEWPORT) }
cmd_action_view_camera :: proc(app: ^App) { toggle_panel(app, PANEL_ID_CAMERA) }
cmd_action_view_props  :: proc(app: ^App) { toggle_panel(app, PANEL_ID_DETAILS) }
cmd_action_view_preview:: proc(app: ^App) { toggle_panel(app, PANEL_ID_CAMERA_PREVIEW) }
cmd_action_view_texture:: proc(app: ^App) { toggle_panel(app, PANEL_ID_TEXTURE_VIEW) }
cmd_action_view_content_browser :: proc(app: ^App) {
    toggle_panel(app, PANEL_ID_CONTENT_BROWSER)
    if panel_visible(app, PANEL_ID_CONTENT_BROWSER) {
        app.e_content_browser.scan_requested = true
    }
}
cmd_action_view_outliner :: proc(app: ^App) { toggle_panel(app, PANEL_ID_OUTLINER) }

cmd_checked_view_render :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_RENDER) }
cmd_checked_view_stats  :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_STATS) }
cmd_checked_view_console :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_CONSOLE) }
cmd_checked_view_sysinfo:: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_SYSTEM_INFO) }
cmd_checked_view_edit   :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_VIEWPORT) }
cmd_checked_view_camera :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_CAMERA) }
cmd_checked_view_props  :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_DETAILS) }
cmd_checked_view_preview:: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_CAMERA_PREVIEW) }
cmd_checked_view_texture:: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_TEXTURE_VIEW) }
cmd_checked_view_content_browser :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_CONTENT_BROWSER) }
cmd_checked_view_outliner :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_OUTLINER) }

// ── View preset actions ──────────────────────────────────────────────────────

cmd_action_save_preset :: proc(app: ^App) {
    // No-op: layout presets are managed by Dear ImGui via imgui.ini.
}

// ── Render actions ───────────────────────────────────────────────────────────

cmd_action_render_restart :: proc(app: ^App) {
    ev := &app.e_edit_view
    ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
    world := app_build_world_from_scene(app, ev.export_scratch[:])
    AppendQuadsToWorld(ev.scene_mgr, &world)
    app_restart_render(app, world)
}

cmd_enabled_render_restart :: proc(app: ^App) -> bool {
    return true
}

trace_output_path :: proc() -> string {
    unix_us := i64(time.duration_microseconds(time.diff(time.Time{}, time.now())))
    trace_file := fmt.tprintf("trace_%d.json", unix_us)
    env_path, ok := os.lookup_env("TRACE_OUTPUT_FILE")
    if !ok || len(env_path) == 0 {
        // Default to logs/ (gitignored) to avoid polluting the repo root.
        os.make_directory("logs")
        return fmt.aprintf("logs/%s", trace_file)
    }
    // TRACE_OUTPUT_FILE can be a full file path or a directory.
    if strings.has_suffix(env_path, ".json") {
        return env_path
    }
    sep := "/"
    if strings.has_suffix(env_path, "/") || strings.has_suffix(env_path, "\\") {
        sep = ""
    }
    out := strings.concatenate({env_path, sep, trace_file})
    delete(env_path)
    return out
}

cmd_action_benchmark_start :: proc(app: ^App) {
    if util.trace_is_capturing() { return }
    util.trace_set_metadata("platform", "odin")
    util.trace_set_metadata("resolution", fmt.tprintf("%dx%d", app.r_camera.image_width, app.r_camera.image_height))
    util.trace_set_metadata("samples_per_pixel", fmt.tprintf("%d", app.r_camera.samples_per_pixel))
    path_mode := "cpu"
    if app.prefer_gpu { path_mode = "gpu" }
    util.trace_set_metadata("render_path", path_mode)
    util.trace_start_capture()
    if util.trace_is_capturing() {
        app_push_log(app, strings.clone("Visual benchmark capture started"))
    }
}

cmd_action_benchmark_stop :: proc(app: ^App) {
    data, ok := util.trace_stop_capture()
    if !ok || len(data) == 0 {
        app_push_log(app, strings.clone("No active visual benchmark capture"))
        return
    }
    defer delete(data)

    path := trace_output_path()
    defer delete(path)
    f, open_err := os.open(path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o644)
    if open_err != os.ERROR_NONE {
        app_push_log(app, fmt.aprintf("Trace write failed: %s", path))
        return
    }
    defer os.close(f)
    _, _ = os.write(f, data)
    app_push_log(app, fmt.aprintf("Trace saved: %s", path))
}

cmd_enabled_benchmark_start :: proc(app: ^App) -> bool {
    when util.TRACE_CAPTURE_ENABLED {
        return !util.trace_is_capturing()
    }
    return false
}

cmd_enabled_benchmark_stop :: proc(app: ^App) -> bool {
    when util.TRACE_CAPTURE_ENABLED {
        return util.trace_is_capturing()
    }
    return false
}

// ── Undo / Redo ──────────────────────────────────────────────────────────────

// apply_edit_action applies an EditAction in the undo (is_undo=true) or redo (is_undo=false) direction.
apply_edit_action :: proc(app: ^App, action: EditAction, is_undo: bool) {
    ev := &app.e_edit_view
    switch a in action {
    case ModifySphereAction:
        sphere := a.before if is_undo else a.after
        SetSceneSphere(ev.scene_mgr, a.idx, sphere)
        if is_undo {
            app_push_log(app, strings.clone("Undo: modify sphere"))
        } else {
            app_push_log(app, strings.clone("Redo: modify sphere"))
        }
    case AddSphereAction:
        if is_undo {
            OrderedRemove(ev.scene_mgr, a.idx)
            ev.selection_kind = .None
            ev.selected_idx   = -1
            app_push_log(app, strings.clone("Undo: add sphere"))
        } else {
            InsertSphereAt(ev.scene_mgr, a.idx, a.sphere)
            ev.selection_kind = .Sphere
            ev.selected_idx   = a.idx
            app_push_log(app, strings.clone("Redo: add sphere"))
        }
    case DeleteSphereAction:
        if is_undo {
            InsertSphereAt(ev.scene_mgr, a.idx, a.sphere)
            ev.selection_kind = .Sphere
            ev.selected_idx   = a.idx
            app_push_log(app, strings.clone("Undo: delete sphere"))
        } else {
            OrderedRemove(ev.scene_mgr, a.idx)
            ev.selection_kind = .None
            ev.selected_idx   = -1
            app_push_log(app, strings.clone("Redo: delete sphere"))
        }
    case AddQuadAction:
        if is_undo {
            OrderedRemove(ev.scene_mgr, a.idx)
            ev.selection_kind = .None
            ev.selected_idx   = -1
            app_push_log(app, strings.clone("Undo: add quad"))
        } else {
            InsertQuadAt(ev.scene_mgr, a.idx, a.quad)
            ev.selection_kind = .Quad
            ev.selected_idx   = a.idx
            app_push_log(app, strings.clone("Redo: add quad"))
        }
    case DeleteQuadAction:
        if is_undo {
            InsertQuadAt(ev.scene_mgr, a.idx, a.quad)
            ev.selection_kind = .Quad
            ev.selected_idx   = a.idx
            app_push_log(app, strings.clone("Undo: delete quad"))
        } else {
            OrderedRemove(ev.scene_mgr, a.idx)
            ev.selection_kind = .None
            ev.selected_idx   = -1
            app_push_log(app, strings.clone("Redo: delete quad"))
        }
    case ModifyQuadAction:
        if is_undo {
            SetSceneQuad(ev.scene_mgr, a.idx, a.before)
            app_push_log(app, strings.clone("Undo: move quad"))
        } else {
            SetSceneQuad(ev.scene_mgr, a.idx, a.after)
            app_push_log(app, strings.clone("Redo: move quad"))
        }
    case ModifyCameraAction:
        if is_undo {
            app.c_camera_params = a.before
            app_push_log(app, strings.clone("Undo: camera"))
        } else {
            app.c_camera_params = a.after
            app_push_log(app, strings.clone("Redo: camera"))
        }
    case ModifyVolumeAction:
        if a.idx >= 0 && a.idx < len(app.e_volumes) {
            if is_undo {
                app.e_volumes[a.idx] = a.before
                app_push_log(app, strings.clone("Undo: volume"))
            } else {
                app.e_volumes[a.idx] = a.after
                app_push_log(app, strings.clone("Redo: volume"))
            }
        }
    case AddVolumeAction:
        if is_undo {
            if a.idx >= 0 && a.idx < len(app.e_volumes) {
                ordered_remove(&app.e_volumes, a.idx)
            }
            ev.selection_kind = .None
            ev.selected_idx   = -1
            app_push_log(app, strings.clone("Undo: add volume"))
        } else {
            insert_idx := clamp(a.idx, 0, len(app.e_volumes))
            inject_at(&app.e_volumes, insert_idx, a.volume)
            ev.selection_kind = .Volume
            ev.selected_idx   = insert_idx
            app_push_log(app, strings.clone("Redo: add volume"))
        }
    case DeleteVolumeAction:
        if is_undo {
            insert_idx := clamp(a.idx, 0, len(app.e_volumes))
            inject_at(&app.e_volumes, insert_idx, a.volume)
            ev.selection_kind = .Volume
            ev.selected_idx   = a.idx
            app_push_log(app, strings.clone("Undo: delete volume"))
        } else {
            if a.idx >= 0 && a.idx < len(app.e_volumes) {
                ordered_remove(&app.e_volumes, a.idx)
            }
            ev.selection_kind = .None
            ev.selected_idx   = -1
            app_push_log(app, strings.clone("Redo: delete volume"))
        }
    }
}

cmd_action_undo :: proc(app: ^App) {
    if action, ok := edit_history_undo(&app.edit_history); ok {
        apply_edit_action(app, action, true)
        mark_scene_dirty(app)
    }
}

cmd_action_redo :: proc(app: ^App) {
    if action, ok := edit_history_redo(&app.edit_history); ok {
        apply_edit_action(app, action, false)
        mark_scene_dirty(app)
    }
}

cmd_enabled_undo :: proc(app: ^App) -> bool { return edit_history_can_undo(&app.edit_history) }
cmd_enabled_redo :: proc(app: ^App) -> bool { return edit_history_can_redo(&app.edit_history) }

// ── Copy / Paste / Duplicate ─────────────────────────────────────────────────

cmd_action_copy :: proc(app: ^App) {
    ev := &app.e_edit_view
    if ev.selection_kind != .Sphere { return }
    if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
        app.e_clipboard_sphere = sphere
        app.e_has_clipboard    = true
        app_push_log(app, strings.clone("Copied sphere"))
    }
}

cmd_enabled_copy :: proc(app: ^App) -> bool {
    return app.e_edit_view.selection_kind == .Sphere
}

cmd_action_paste :: proc(app: ^App) {
    if !app.e_has_clipboard { return }
    ev := &app.e_edit_view
    n := SceneManagerLen(ev.scene_mgr)
    insert_idx := n
    if ev.selection_kind == .Sphere && ev.selected_idx >= 0 {
        insert_idx = ev.selected_idx + 1
    }
    sphere := app.e_clipboard_sphere
    sphere.center[0] += 0.5
    sphere.center[2] += 0.5
    InsertSphereAt(ev.scene_mgr, insert_idx, sphere)
    ev.selection_kind = .Sphere
    ev.selected_idx   = insert_idx
    edit_history_push(&app.edit_history, AddSphereAction{idx = insert_idx, sphere = sphere})
    mark_scene_dirty(app)
    app_push_log(app, strings.clone("Pasted sphere"))
}

cmd_enabled_paste :: proc(app: ^App) -> bool {
    return app.e_has_clipboard
}

cmd_action_duplicate :: proc(app: ^App) {
    ev := &app.e_edit_view
    if ev.selection_kind != .Sphere { return }
    sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx)
    if !ok { return }
    insert_idx := ev.selected_idx + 1
    sphere.center[0] += 0.5
    sphere.center[2] += 0.5
    InsertSphereAt(ev.scene_mgr, insert_idx, sphere)
    ev.selection_kind = .Sphere
    ev.selected_idx   = insert_idx
    edit_history_push(&app.edit_history, AddSphereAction{idx = insert_idx, sphere = sphere})
    mark_scene_dirty(app)
    app_push_log(app, strings.clone("Duplicated sphere"))
}

cmd_enabled_duplicate :: proc(app: ^App) -> bool {
    return app.e_edit_view.selection_kind == .Sphere
}

// ── Edit View context menu actions ───────────────────────────────────────────

cmd_action_edit_view_align_camera :: proc(app: ^App) {
    ev := &app.e_edit_view
    align_editor_camera_to_render(ev, app.c_camera_params, false)
}

cmd_action_edit_view_frame_geometry :: proc(app: ^App) {
    ev := &app.e_edit_view
    if !frame_editor_camera_horizontal(ev) {
        app_push_log(app, strings.clone("Frame all geometry: no valid objects"))
    }
}

cmd_action_edit_view_camera_mode :: proc(app: ^App) {
    ev := &app.e_edit_view
    if ev.camera_mode == .FreeFly {
        ev.camera_mode = .Orbit
    } else {
        ev.camera_mode = .FreeFly
    }
}

cmd_action_edit_view_lock_axis_x :: proc(app: ^App) {
    app.e_edit_view.lock_axis_x = !app.e_edit_view.lock_axis_x
}
cmd_action_edit_view_lock_axis_y :: proc(app: ^App) {
    app.e_edit_view.lock_axis_y = !app.e_edit_view.lock_axis_y
}
cmd_action_edit_view_lock_axis_z :: proc(app: ^App) {
    app.e_edit_view.lock_axis_z = !app.e_edit_view.lock_axis_z
}

cmd_action_edit_view_grid_visible :: proc(app: ^App) {
    app.e_edit_view.grid_visible = !app.e_edit_view.grid_visible
}

cmd_action_edit_view_grid_density_plus :: proc(app: ^App) {
    ev := &app.e_edit_view
    ev.grid_density = clamp(ev.grid_density * 1.25, f32(0.25), f32(8.0))
}
cmd_action_edit_view_grid_density_minus :: proc(app: ^App) {
    ev := &app.e_edit_view
    ev.grid_density = clamp(ev.grid_density / 1.25, f32(0.25), f32(8.0))
}

cmd_action_edit_view_speed_slow :: proc(app: ^App) {
    app.e_edit_view.speed_factor = 0.5
}
cmd_action_edit_view_speed_medium :: proc(app: ^App) {
    app.e_edit_view.speed_factor = 1.0
}
cmd_action_edit_view_speed_fast :: proc(app: ^App) {
    app.e_edit_view.speed_factor = 2.0
}
cmd_action_edit_view_speed_very_fast :: proc(app: ^App) {
    app.e_edit_view.speed_factor = 4.0
}

cmd_checked_edit_view_camera_mode :: proc(app: ^App) -> bool {
    return app.e_edit_view.camera_mode == .FreeFly
}
cmd_checked_edit_view_lock_axis_x :: proc(app: ^App) -> bool {
    return app.e_edit_view.lock_axis_x
}
cmd_checked_edit_view_lock_axis_y :: proc(app: ^App) -> bool {
    return app.e_edit_view.lock_axis_y
}
cmd_checked_edit_view_lock_axis_z :: proc(app: ^App) -> bool {
    return app.e_edit_view.lock_axis_z
}
cmd_checked_edit_view_grid_visible :: proc(app: ^App) -> bool {
    return app.e_edit_view.grid_visible
}

// ── Example scene actions ────────────────────────────────────────────────────

cmd_action_scene_load_example :: proc(app: ^App) {
    // Always show confirm modal ("Load Example?" / "This cannot be undone"); Save & Load only enabled when dirty
    confirm_load_modal_open(&app.e_confirm_load, app.e_confirm_load.scene_idx)
}

// ── register_all_commands ────────────────────────────────────────────────────

// register_all_commands populates app.commands. Call once during app init.
register_all_commands :: proc(app: ^App) {
    cmd_reg := &app.commands

    // File
    cmd_register(cmd_reg, Command{id = CMD_FILE_NEW,     label = "New",      shortcut = "Ctrl+N", action = cmd_action_file_new})
    cmd_register(cmd_reg, Command{id = CMD_FILE_IMPORT,  label = "Import…",  shortcut = "Ctrl+O", action = cmd_action_file_import})
    cmd_register(cmd_reg, Command{id = CMD_FILE_SAVE,    label = "Save",     shortcut = "Ctrl+S", action = cmd_action_file_save_menu, enabled_proc = cmd_action_file_save_enabled})
    cmd_register(cmd_reg, Command{id = CMD_FILE_SAVE_AS, label = "Save As…", shortcut = "",       action = cmd_action_file_save_as})
    cmd_register(cmd_reg, Command{id = CMD_FILE_EXIT,    label = "Exit",     shortcut = "Alt+F4", action = cmd_action_file_exit})

    // View — panels
    cmd_register(cmd_reg, Command{id = CMD_VIEW_RENDER,          label = "Render Preview",  action = cmd_action_view_render,          checked_proc = cmd_checked_view_render})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_STATS,           label = "Stats",           action = cmd_action_view_stats,           checked_proc = cmd_checked_view_stats})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_CONSOLE,         label = "Console",         action = cmd_action_view_console,         checked_proc = cmd_checked_view_console})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_SYSINFO,         label = "System Info",     action = cmd_action_view_sysinfo,         checked_proc = cmd_checked_view_sysinfo})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_EDIT,            label = "Viewport",        action = cmd_action_view_edit,            checked_proc = cmd_checked_view_edit})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_CAMERA,          label = "Camera",          action = cmd_action_view_camera,          checked_proc = cmd_checked_view_camera})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_PROPS,           label = "Details",         action = cmd_action_view_props,           checked_proc = cmd_checked_view_props})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_PREVIEW,         label = "Camera Preview",  action = cmd_action_view_preview,         checked_proc = cmd_checked_view_preview})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_OUTLINER,        label = "World Outliner",  action = cmd_action_view_outliner,        checked_proc = cmd_checked_view_outliner})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_TEXTURE,         label = "Texture View",    action = cmd_action_view_texture,         checked_proc = cmd_checked_view_texture})
    cmd_register(cmd_reg, Command{id = CMD_VIEW_CONTENT_BROWSER, label = "Content Browser", action = cmd_action_view_content_browser, checked_proc = cmd_checked_view_content_browser})

    cmd_register(cmd_reg, Command{id = CMD_VIEW_SAVE_PRESET,    label = "Save Layout As…", action = cmd_action_save_preset})

    // Edit
    cmd_register(cmd_reg, Command{id = CMD_UNDO,             label = "Undo",      shortcut = "Ctrl+Z", action = cmd_action_undo,       enabled_proc = cmd_enabled_undo})
    cmd_register(cmd_reg, Command{id = CMD_REDO,             label = "Redo",      shortcut = "Ctrl+Y", action = cmd_action_redo,       enabled_proc = cmd_enabled_redo})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_COPY,        label = "Copy",      shortcut = "Ctrl+C", action = cmd_action_copy,       enabled_proc = cmd_enabled_copy})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_PASTE,       label = "Paste",     shortcut = "Ctrl+V", action = cmd_action_paste,      enabled_proc = cmd_enabled_paste})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_DUPLICATE,   label = "Duplicate", shortcut = "Ctrl+D", action = cmd_action_duplicate,  enabled_proc = cmd_enabled_duplicate})

    // Render
    cmd_register(cmd_reg, Command{id = CMD_RENDER_RESTART, label = "Restart", shortcut = "F5", action = cmd_action_render_restart, enabled_proc = cmd_enabled_render_restart})
    cmd_register(cmd_reg, Command{id = CMD_BENCHMARK_START, label = "Start Benchmark", action = cmd_action_benchmark_start, enabled_proc = cmd_enabled_benchmark_start})
    cmd_register(cmd_reg, Command{id = CMD_BENCHMARK_STOP,  label = "Stop Benchmark",  action = cmd_action_benchmark_stop,  enabled_proc = cmd_enabled_benchmark_stop})

    // Examples
    cmd_register(cmd_reg, Command{id = CMD_SCENE_LOAD_EXAMPLE, label = "Load Example Scene", action = cmd_action_scene_load_example})

    // Edit View context menu (viewport right-click)
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_ALIGN_CAMERA,   label = "Align editor camera to render camera", action = cmd_action_edit_view_align_camera})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_FRAME_GEOMETRY,  label = "Frame all geometry (horizontal)",       action = cmd_action_edit_view_frame_geometry})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_CAMERA_MODE,     label = "Free-fly / orbit",                       action = cmd_action_edit_view_camera_mode, checked_proc = cmd_checked_edit_view_camera_mode})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_LOCK_AXIS_X,     label = "Lock X axis",                           action = cmd_action_edit_view_lock_axis_x,  checked_proc = cmd_checked_edit_view_lock_axis_x})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_LOCK_AXIS_Y,     label = "Lock Y axis",                           action = cmd_action_edit_view_lock_axis_y,  checked_proc = cmd_checked_edit_view_lock_axis_y})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_LOCK_AXIS_Z,     label = "Lock Z axis",                           action = cmd_action_edit_view_lock_axis_z,  checked_proc = cmd_checked_edit_view_lock_axis_z})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_GRID_VISIBLE,     label = "Grid visible",                          action = cmd_action_edit_view_grid_visible, checked_proc = cmd_checked_edit_view_grid_visible})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_GRID_DENSITY_PLUS,  label = "Grid density +",                    action = cmd_action_edit_view_grid_density_plus})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_GRID_DENSITY_MINUS, label = "Grid density -",                    action = cmd_action_edit_view_grid_density_minus})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_SPEED_SLOW,      label = "Movement speed: Slow",                  action = cmd_action_edit_view_speed_slow})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_SPEED_MEDIUM,   label = "Movement speed: Medium",                 action = cmd_action_edit_view_speed_medium})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_SPEED_FAST,     label = "Movement speed: Fast",                   action = cmd_action_edit_view_speed_fast})
    cmd_register(cmd_reg, Command{id = CMD_EDIT_VIEW_SPEED_VERY_FAST, label = "Movement speed: Very fast",             action = cmd_action_edit_view_speed_very_fast})
}
