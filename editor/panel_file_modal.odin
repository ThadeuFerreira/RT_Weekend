package editor

import "core:fmt"
import "core:strings"
import imgui "RT_Weekend:vendor/odin-imgui"
import "RT_Weekend:core"
import "RT_Weekend:persistence"
import rt "RT_Weekend:raytrace"

FILE_MODAL_MAX_INPUT :: 512

FileModalMode :: enum {
    Import,
    SaveAs,
}

FileModalState :: struct {
    active:    bool,
    mode:      FileModalMode,
    title:     string,
    input:     [FILE_MODAL_MAX_INPUT]u8,
    input_len: int,
}

// file_modal_open activates the modal with the given mode and title.
file_modal_open :: proc(modal: ^FileModalState, mode: FileModalMode, title: string) {
    modal.active    = true
    modal.mode      = mode
    modal.title     = title
    modal.input_len = 0
    for i in 0..<FILE_MODAL_MAX_INPUT { modal.input[i] = 0 }
}

// file_modal_input_string returns the current typed text as a string slice (no allocation).
file_modal_input_string :: proc(modal: ^FileModalState) -> string {
    return string(modal.input[:modal.input_len])
}

// world_has_ground_plane returns true if the world contains a sphere used as ground (core.is_ground_heuristic).
world_has_ground_plane :: proc(world: []rt.Object) -> bool {
	for obj in world {
		if s, ok := obj.(rt.Sphere); ok && core.is_ground_heuristic(s.center[1], s.radius) {
			return true
		}
	}
	return false
}

// file_import_from_path loads a scene from path and restarts the render. Takes ownership of path (caller must not delete).
// Used by native open dialog and by file_modal_confirm when FILE_MODAL_FALLBACK is used for Import.
file_import_from_path :: proc(app: ^App, path: string) {
    if len(path) == 0 { return }
    ev := &app.e_edit_view
    app_clear_image_texture_cache(app)
    cam, world, volumes, ok := persistence.load_scene(path, app.r_camera.image_width, app.r_camera.image_height, app.r_camera.samples_per_pixel, &app.image_texture_cache)
    if !ok {
        app_push_log(app, fmt.tprintf("Import failed: %s", path))
        delete(path)
        return
    }
    rt.copy_camera_to_scene_params(&app.c_camera_params, cam)
    LoadFromWorld(ev.scene_mgr, world[:])
    align_editor_camera_to_render(ev, app.c_camera_params, true)
    ev.selection_kind = .None
    ev.selected_idx   = -1

    edit_history_free(&app.edit_history)
    app.edit_history = EditHistory{}
    // Only include ground plane when the loaded scene had one (core.is_ground_heuristic).
    app.include_ground_plane = world_has_ground_plane(world[:])
    app_set_ground_texture(app, nil)

    delete(app.current_scene_path)
    app.current_scene_path = path
    app.e_scene_dirty = false

    if !app.finished {
        rt.finish_render(app.r_session)
        app_set_render_state(app, .Idle)
    }
    rt.free_session(app.r_session)
    app.r_session = nil
    rt.free_world_volumes(app.r_world)
    delete(app.r_world)
    app.r_world = world
    world = nil
    clear(&app.e_volumes)
    if volumes != nil {
        for v in volumes { append(&app.e_volumes, v) }
        delete(volumes)
    }
    app.elapsed_secs = 0
    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    rt.init_camera(app.r_camera)
    _ = app_start_render_session(app)
    app_push_log(app, fmt.tprintf("Imported: %s (%d objects)", path, len(app.r_world)))

    free(cam)
}

// file_save_as_path saves the current scene to path. Takes ownership of path (caller must not delete).
// Appends ".json" if the path lacks that extension. Returns true on success, false on empty path or write failure.
file_save_as_path :: proc(app: ^App, path: string) -> bool {
    if len(path) == 0 { return false }
    // Ensure .json extension — dialogs on Linux/macOS don't auto-append.
    path := path
    if !strings.has_suffix(path, ".json") {
        new_path := strings.concatenate({path, ".json"})
        delete(path)
        path = new_path
    }
    ev := &app.e_edit_view
    ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
    world := app_build_world_from_scene(app, ev.export_scratch[:])
    AppendQuadsToWorld(ev.scene_mgr, &world)
    defer delete(world)
    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    if persistence.save_scene(path, app.r_camera, world, app.e_volumes[:]) {
        delete(app.current_scene_path)
        app.current_scene_path = path
        app.e_scene_dirty = false
        app_push_log(app, fmt.tprintf("Saved as: %s", path))
        return true
    }
    app_push_log(app, fmt.tprintf("Save failed: %s", path))
    delete(path)
    return false
}

// file_modal_confirm processes the modal result based on its mode.
file_modal_confirm :: proc(app: ^App) {
    modal := &app.file_modal
    if !modal.active { return }

    text := strings.clone(file_modal_input_string(modal))
    modal.active = false

    switch modal.mode {
    case .Import:
        if len(text) == 0 { delete(text); return }
        file_import_from_path(app, text)
    case .SaveAs:
        if len(text) == 0 { delete(text); return }
        file_save_as_path(app, text)
    }
}

// =============================================================================
// ImGui Modal Implementation (Track E)
// =============================================================================

// imgui_draw_file_modal draws the file path / preset name modal using ImGui.
// Call from imgui_draw_all_panels before imgui_rl_render.
imgui_draw_file_modal :: proc(app: ^App) {
    modal := &app.file_modal
    if !modal.active { return }
    // Visible title in title bar; "##file_modal" gives a stable popup ID
    popup_label := strings.concatenate({modal.title, "##file_modal"}, context.temp_allocator)
    label_c := strings.clone_to_cstring(popup_label, context.temp_allocator)
    if !imgui.IsPopupOpen(label_c) {
        imgui.OpenPopup(label_c)
    }
    viewport := imgui.GetMainViewport()
    center := imgui.Vec2{viewport.Pos.x + viewport.Size.x * 0.5, viewport.Pos.y + viewport.Size.y * 0.5}
    imgui.SetNextWindowPos(center, .Always, imgui.Vec2{0.5, 0.5})
    imgui.SetNextWindowSize(imgui.Vec2{400, 0}, .Always)
    if imgui.BeginPopupModal(label_c, nil, {.AlwaysAutoResize}) {
        imgui.Separator()
        // InputText writes directly into modal.input buffer
        imgui.InputText("##path", cast(cstring)raw_data(modal.input[:]), FILE_MODAL_MAX_INPUT)
        if imgui.Button("OK") {
            // sync input_len from buffer
            modal.input_len = len(string(cstring(raw_data(modal.input[:]))))
            file_modal_confirm(app)
            imgui.CloseCurrentPopup()
        }
        imgui.SameLine()
        if imgui.Button("Cancel") {
            modal.active = false
            imgui.CloseCurrentPopup()
        }
        imgui.EndPopup()
    }
}
