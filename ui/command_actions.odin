package ui

import "core:fmt"
import "core:strings"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:scene"

// ── File actions ────────────────────────────────────────────────────────────

cmd_action_file_new :: proc(app: ^App) {
    if !app.finished { return }

    rt.free_session(app.session)
    app.session = nil

    delete(app.edit_view.objects)
    app.edit_view.objects = make([dynamic]scene.SceneSphere)
    append(&app.edit_view.objects, scene.SceneSphere{center = {-1.5, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = {0.8, 0.2, 0.2}})
    append(&app.edit_view.objects, scene.SceneSphere{center = { 0,   0.5, 0}, radius = 0.5, material_kind = .Metallic,   albedo = {0.2, 0.2, 0.8}, fuzz = 0.1})
    append(&app.edit_view.objects, scene.SceneSphere{center = { 1.5, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = {0.2, 0.8, 0.2}})
    app.edit_view.selection_kind = .None
    app.edit_view.selected_idx   = -1

    app.current_scene_path = ""

    delete(app.world)
    app.world = rt.build_world_from_scene(app.edit_view.objects[:])

    app.finished      = false
    app.elapsed_secs  = 0

    rt.apply_scene_camera(app.camera, &app.camera_params)
    rt.init_camera(app.camera)
    app.session = rt.start_render(app.camera, app.world, app.num_threads)
    app_push_log(app, strings.clone("New scene (3 default spheres)"))
}

cmd_action_file_import :: proc(app: ^App) {
    file_modal_open(&app.file_modal, .Import, "Import Scene (.json)")
}

cmd_action_file_save :: proc(app: ^App) {
    if len(app.current_scene_path) == 0 { return }
    // Build world from edit view objects for saving
    world := rt.build_world_from_scene(app.edit_view.objects[:])
    defer delete(world)
    rt.apply_scene_camera(app.camera, &app.camera_params)
    if rt.save_scene(app.current_scene_path, app.camera, world) {
        app_push_log(app, fmt.aprintf("Saved: %s", app.current_scene_path))
    } else {
        app_push_log(app, fmt.aprintf("Save failed: %s", app.current_scene_path))
    }
}

cmd_action_file_save_enabled :: proc(app: ^App) -> bool {
    return len(app.current_scene_path) > 0
}

cmd_action_file_save_as :: proc(app: ^App) {
    file_modal_open(&app.file_modal, .SaveAs, "Save Scene As (.json)")
}

cmd_action_file_exit :: proc(app: ^App) {
    app.should_exit = true
}

// ── View panel toggle actions (concrete named procs — avoids loop-closure pitfall) ─

toggle_panel :: proc(app: ^App, id: string) {
    p := app_find_panel(app, id)
    if p != nil { p.visible = !p.visible }
}

panel_visible :: proc(app: ^App, id: string) -> bool {
    p := app_find_panel(app, id)
    return p != nil && p.visible
}

cmd_action_view_render :: proc(app: ^App) { toggle_panel(app, PANEL_ID_RENDER) }
cmd_action_view_stats  :: proc(app: ^App) { toggle_panel(app, PANEL_ID_STATS) }
cmd_action_view_log    :: proc(app: ^App) { toggle_panel(app, PANEL_ID_LOG) }
cmd_action_view_sysinfo:: proc(app: ^App) { toggle_panel(app, PANEL_ID_SYSTEM_INFO) }
cmd_action_view_edit   :: proc(app: ^App) { toggle_panel(app, PANEL_ID_EDIT_VIEW) }
cmd_action_view_camera :: proc(app: ^App) { toggle_panel(app, PANEL_ID_CAMERA) }
cmd_action_view_props  :: proc(app: ^App) { toggle_panel(app, PANEL_ID_OBJECT_PROPS) }
cmd_action_view_preview:: proc(app: ^App) { toggle_panel(app, PANEL_ID_PREVIEW_PORT) }

cmd_checked_view_render :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_RENDER) }
cmd_checked_view_stats  :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_STATS) }
cmd_checked_view_log    :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_LOG) }
cmd_checked_view_sysinfo:: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_SYSTEM_INFO) }
cmd_checked_view_edit   :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_EDIT_VIEW) }
cmd_checked_view_camera :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_CAMERA) }
cmd_checked_view_props  :: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_OBJECT_PROPS) }
cmd_checked_view_preview:: proc(app: ^App) -> bool { return panel_visible(app, PANEL_ID_PREVIEW_PORT) }

// ── View preset actions ──────────────────────────────────────────────────────

cmd_action_preset_default :: proc(app: ^App) {
    layout_build_default(app, &app.dock_layout)
    app_push_log(app, strings.clone("Layout: Default"))
}

cmd_action_preset_render :: proc(app: ^App) {
    layout_build_render_focus(app, &app.dock_layout)
    app_push_log(app, strings.clone("Layout: Rendering Focus"))
}

cmd_action_preset_edit :: proc(app: ^App) {
    layout_build_edit_focus(app, &app.dock_layout)
    app_push_log(app, strings.clone("Layout: Editing Focus"))
}

cmd_action_save_preset :: proc(app: ^App) {
    file_modal_open(&app.file_modal, .PresetName, "Save Layout As Preset")
}

// ── Render actions ───────────────────────────────────────────────────────────

cmd_action_render_restart :: proc(app: ^App) {
    app_restart_render_with_scene(app, app.edit_view.objects[:])
}

cmd_enabled_render_restart :: proc(app: ^App) -> bool {
    return app.finished
}

// ── register_all_commands ────────────────────────────────────────────────────

// register_all_commands populates app.commands. Call once during app init.
register_all_commands :: proc(app: ^App) {
    r := &app.commands

    // File
    cmd_register(r, Command{id = CMD_FILE_NEW,     label = "New",          shortcut = "Ctrl+N", action = cmd_action_file_new})
    cmd_register(r, Command{id = CMD_FILE_IMPORT,  label = "Import…",      shortcut = "Ctrl+O", action = cmd_action_file_import})
    cmd_register(r, Command{id = CMD_FILE_SAVE,    label = "Save",         shortcut = "Ctrl+S", action = cmd_action_file_save, enabled_proc = cmd_action_file_save_enabled})
    cmd_register(r, Command{id = CMD_FILE_SAVE_AS, label = "Save As…",     shortcut = "",       action = cmd_action_file_save_as})
    cmd_register(r, Command{id = CMD_FILE_EXIT,    label = "Exit",         shortcut = "Alt+F4", action = cmd_action_file_exit})

    // View — panels
    cmd_register(r, Command{id = CMD_VIEW_RENDER,  label = "Render Preview", action = cmd_action_view_render,  checked_proc = cmd_checked_view_render})
    cmd_register(r, Command{id = CMD_VIEW_STATS,   label = "Stats",          action = cmd_action_view_stats,   checked_proc = cmd_checked_view_stats})
    cmd_register(r, Command{id = CMD_VIEW_LOG,     label = "Log",            action = cmd_action_view_log,     checked_proc = cmd_checked_view_log})
    cmd_register(r, Command{id = CMD_VIEW_SYSINFO, label = "System Info",    action = cmd_action_view_sysinfo, checked_proc = cmd_checked_view_sysinfo})
    cmd_register(r, Command{id = CMD_VIEW_EDIT,    label = "Edit View",      action = cmd_action_view_edit,    checked_proc = cmd_checked_view_edit})
    cmd_register(r, Command{id = CMD_VIEW_CAMERA,  label = "Camera",         action = cmd_action_view_camera,  checked_proc = cmd_checked_view_camera})
    cmd_register(r, Command{id = CMD_VIEW_PROPS,   label = "Object Props",   action = cmd_action_view_props,   checked_proc = cmd_checked_view_props})
    cmd_register(r, Command{id = CMD_VIEW_PREVIEW, label = "Preview Port",   action = cmd_action_view_preview, checked_proc = cmd_checked_view_preview})

    // View — presets
    cmd_register(r, Command{id = CMD_VIEW_PRESET_DEFAULT, label = "Default",          action = cmd_action_preset_default})
    cmd_register(r, Command{id = CMD_VIEW_PRESET_RENDER,  label = "Rendering Focus",  action = cmd_action_preset_render})
    cmd_register(r, Command{id = CMD_VIEW_PRESET_EDIT,    label = "Editing Focus",    action = cmd_action_preset_edit})
    cmd_register(r, Command{id = CMD_VIEW_SAVE_PRESET,    label = "Save Layout As…",  action = cmd_action_save_preset})

    // Render
    cmd_register(r, Command{id = CMD_RENDER_RESTART, label = "Restart", shortcut = "F5", action = cmd_action_render_restart, enabled_proc = cmd_enabled_render_restart})
}
