package editor

import "core:fmt"
import "core:strings"
import "core:time"
import imgui "RT_Weekend:vendor/odin-imgui"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:util"

// Save Changes? modal (exit or import when scene is dirty)
SaveChangesReason :: enum { None, Exit, Import }
SaveChangesModalState :: struct {
    active: bool,
    reason: SaveChangesReason,
}

save_changes_modal_open :: proc(modal: ^SaveChangesModalState, reason: SaveChangesReason) {
    modal.active = true
    modal.reason = reason
}


// --- Load Example Scene confirmation ---

ConfirmLoadModalState :: struct {
    active:      bool,
    scene_idx:   int,
    scene_label: string, // alias into EXAMPLE_SCENES (no alloc)
}

confirm_load_modal_open :: proc(modal: ^ConfirmLoadModalState, scene_idx: int) {
    modal.active      = true
    modal.scene_idx   = scene_idx
    modal.scene_label = EXAMPLE_SCENES[scene_idx].label
}


// load_example_at loads an example scene, optionally saving first. Returns false if save dialog cancelled.
@(private="file")
load_example_at :: proc(app: ^App, scene_idx: int, save_first: bool) -> bool {
    if save_first {
        if len(app.current_scene_path) > 0 {
            if !cmd_action_file_save(app) { return false } // save failed, don't load
        } else {
            // No path yet (e.g. modified example): open Save As so user can save with custom name
            default_dir := util.dialog_default_dir(app.current_scene_path)
            path, ok := util.save_file_dialog(default_dir, "scene.json", util.SCENE_FILTER_DESC, util.SCENE_FILTER_EXT)
            delete(default_dir)
            if !ok { return false } // user cancelled save dialog, don't load
            if !file_save_as_path(app, path) { return false } // save failed, don't load
        }
    }
    spheres, quads, cam, ground_tex, include_ground, volumes := EXAMPLE_SCENES[scene_idx].build()
    defer delete(spheres)
    defer delete(quads)
    defer delete(volumes)
    app_set_ground_texture(app, ground_tex)
    app.include_ground_plane = include_ground
    app_clear_image_texture_cache(app)
    ev := &app.e_edit_view
    LoadFromSceneSpheres(ev.scene_mgr, spheres)
    for q in quads {
        InsertQuadAt(ev.scene_mgr, SceneManagerLen(ev.scene_mgr), q)
    }
    ev.selection_kind = .None
    ev.selected_idx   = -1
    app.c_camera_params = cam
    align_editor_camera_to_render(ev, app.c_camera_params, true)
    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    delete(app.current_scene_path)
    app.current_scene_path = ""
    edit_history_free(&app.edit_history)
    app.edit_history = EditHistory{}
    app.e_scene_dirty = false
    rt.free_session(app.r_session)
    app.r_session = nil
    ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
    rt.free_world_volumes(app.r_world)
    delete(app.r_world)
    app.r_world = app_build_world_from_scene(app, ev.export_scratch[:])
    AppendQuadsToWorld(ev.scene_mgr, &app.r_world)
    clear(&app.e_volumes)
    if volumes != nil {
        for v in volumes { append(&app.e_volumes, v) }
    }
    for v in app.e_volumes {
        append(&app.r_world, rt.build_volume_from_scene_volume(v))
    }
    app.finished     = false
    app.elapsed_secs = 0
    app.render_start = time.now()
    rt.init_camera(app.r_camera)
    _ = app_start_render_session(app)
    return true
}

@(private="file")
confirm_load_execute :: proc(app: ^App, save_first: bool) {
    modal := &app.e_confirm_load
    if !app.finished { return }
    if load_example_at(app, modal.scene_idx, save_first) {
        app_push_log(app, fmt.tprintf("Loaded example: %s", modal.scene_label))
        modal.active = false
    }
    // If load_example_at returned false, user cancelled Save As dialog; keep modal open
}

// imgui_draw_save_changes_modal draws the "Save Changes?" modal using ImGui.
// Call from imgui_draw_all_panels before imgui_rl_render.
imgui_draw_save_changes_modal :: proc(app: ^App) {
    modal := &app.e_save_changes
    if !modal.active { return }
    if !imgui.IsPopupOpen("Save Changes?") {
        imgui.OpenPopup("Save Changes?")
    }
    viewport := imgui.GetMainViewport()
    center := imgui.Vec2{viewport.Pos.x + viewport.Size.x * 0.5, viewport.Pos.y + viewport.Size.y * 0.5}
    imgui.SetNextWindowPos(center, .Always, imgui.Vec2{0.5, 0.5})
    if imgui.BeginPopupModal("Save Changes?", nil, {.AlwaysAutoResize}) {
        if modal.reason == .Exit {
            imgui.Text("Save before closing?")
        } else {
            imgui.Text("Save before loading another scene?")
        }
        imgui.Separator()
        save_enabled := len(app.current_scene_path) > 0
        if !save_enabled { imgui.BeginDisabled() }
        if imgui.Button("Save") {
            if cmd_action_file_save(app) {
                _save_changes_proceed(app, modal)
            }
        }
        if !save_enabled { imgui.EndDisabled() }
        imgui.SameLine()
        if imgui.Button("Save As…") {
            default_dir := util.dialog_default_dir(app.current_scene_path)
            path, ok := util.save_file_dialog(default_dir, "scene.json",
                util.SCENE_FILTER_DESC, util.SCENE_FILTER_EXT)
            delete(default_dir)
            if ok && file_save_as_path(app, path) {
                _save_changes_proceed(app, modal)
            }
        }
        imgui.SameLine()
        if imgui.Button("Cancel") {
            modal.active = false
            modal.reason = .None
            imgui.CloseCurrentPopup()
        }
        imgui.SameLine()
        if imgui.Button("Continue (discard)") {
            _save_changes_proceed(app, modal)
        }
        imgui.EndPopup()
    }
}

// Must be called from within imgui_draw_save_changes_modal (i.e. while BeginPopupModal is active);
// otherwise imgui.CloseCurrentPopup() is a no-op.
@(private="file")
_save_changes_proceed :: proc(app: ^App, modal: ^SaveChangesModalState) {
    reason := modal.reason
    modal.active = false
    modal.reason = .None
    imgui.CloseCurrentPopup()
    switch reason {
    case .Exit:
        app.should_exit = true
    case .Import:
        default_dir := util.dialog_default_dir(app.current_scene_path)
        path, ok := util.open_file_dialog(default_dir, util.SCENE_FILTER_DESC, util.SCENE_FILTER_EXT)
        delete(default_dir)
        if ok { file_import_from_path(app, path) }
    case .None:
    }
}

// imgui_draw_confirm_load_modal draws the "Load Example Scene?" modal using ImGui.
// Call from imgui_draw_all_panels before imgui_rl_render.
imgui_draw_confirm_load_modal :: proc(app: ^App) {
    modal := &app.e_confirm_load
    if !modal.active { return }
    if !imgui.IsPopupOpen("Load Example Scene?") {
        imgui.OpenPopup("Load Example Scene?")
    }
    viewport := imgui.GetMainViewport()
    center := imgui.Vec2{viewport.Pos.x + viewport.Size.x * 0.5, viewport.Pos.y + viewport.Size.y * 0.5}
    imgui.SetNextWindowPos(center, .Always, imgui.Vec2{0.5, 0.5})
    if imgui.BeginPopupModal("Load Example Scene?", nil, {.AlwaysAutoResize}) {
        label_c := strings.clone_to_cstring(modal.scene_label, context.temp_allocator)
        imgui.Text("\"%s\" will replace your current scene.", label_c)
        imgui.Text("This cannot be undone.")
        imgui.Separator()
        save_enabled := app.e_scene_dirty
        if !save_enabled { imgui.BeginDisabled() }
        if imgui.Button("Save & Load") {
            if len(app.current_scene_path) > 0 {
                if cmd_action_file_save(app) {
                    confirm_load_execute(app, false) // already saved above
                }
            } else {
                default_dir := util.dialog_default_dir(app.current_scene_path)
                path, ok := util.save_file_dialog(default_dir, "scene.json",
                    util.SCENE_FILTER_DESC, util.SCENE_FILTER_EXT)
                delete(default_dir)
                if ok && file_save_as_path(app, path) {
                    confirm_load_execute(app, false) // already saved above
                }
            }
        }
        if !save_enabled { imgui.EndDisabled() }
        imgui.SameLine()
        if imgui.Button("Load") {
            confirm_load_execute(app, false)
        }
        imgui.SameLine()
        if imgui.Button("Cancel") {
            modal.active = false
            imgui.CloseCurrentPopup()
        }
        imgui.EndPopup()
    }
}
