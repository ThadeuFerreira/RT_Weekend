package editor

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import "RT_Weekend:core"
import "RT_Weekend:persistence"
import rt "RT_Weekend:raytrace"

FILE_MODAL_MAX_INPUT :: 512

FileModalMode :: enum {
    Import,
    SaveAs,
    PresetName,
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

// modal_button_rects returns the OK and Cancel button rectangles for a dialog at (dx,dy,w,h).
@(private="file")
modal_button_rects :: proc(dx, dy, dialog_w, dialog_h: f32) -> (btn_ok, btn_cancel: rl.Rectangle) {
    btn_ok     = rl.Rectangle{dx + dialog_w - 130, dy + dialog_h - 30, 55, 22}
    btn_cancel = rl.Rectangle{dx + dialog_w - 70,  dy + dialog_h - 30, 60, 22}
    return
}

// file_modal_update handles all input for the modal (keyboard + mouse buttons).
// Sets app.input_consumed = true when modal is active.
file_modal_update :: proc(app: ^App) {
    modal := &app.file_modal
    if !modal.active { return }

    app.input_consumed = true

    // Typed characters
    for {
        ch := rl.GetCharPressed()
        if ch == 0 { break }
        if modal.input_len < FILE_MODAL_MAX_INPUT - 1 {
            modal.input[modal.input_len] = u8(ch)
            modal.input_len += 1
        }
    }

    // Backspace
    if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) {
        if modal.input_len > 0 {
            modal.input_len -= 1
            modal.input[modal.input_len] = 0
        }
    }

    // Confirm on Enter
    if rl.IsKeyPressed(.ENTER) {
        file_modal_confirm(app)
        return
    }

    // Cancel on Escape
    if rl.IsKeyPressed(.ESCAPE) {
        modal.active = false
        return
    }

    // Mouse button clicks
    if rl.IsMouseButtonPressed(.LEFT) {
        sw := f32(rl.GetScreenWidth())
        sh := f32(rl.GetScreenHeight())
        dialog_w, dialog_h := f32(420), f32(130)
        dx := (sw - dialog_w) * 0.5
        dy := (sh - dialog_h) * 0.5
        btn_ok, btn_cancel := modal_button_rects(dx, dy, dialog_w, dialog_h)
        mouse := rl.GetMousePosition()
        if rl.CheckCollisionPointRec(mouse, btn_ok) {
            file_modal_confirm(app)
        } else if rl.CheckCollisionPointRec(mouse, btn_cancel) {
            modal.active = false
        }
    }
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
        app_push_log(app, fmt.aprintf("Import failed: %s", path))
        delete(path)
        return
    }
    rt.copy_camera_to_scene_params(&app.c_camera_params, cam)
    LoadFromWorld(ev.scene_mgr, world[:])
    align_editor_camera_to_render(ev, app.c_camera_params, true)

    edit_history_free(&app.edit_history)
    app.edit_history = EditHistory{}
    // Only include ground plane when the loaded scene had one (core.is_ground_heuristic).
    app.include_ground_plane = world_has_ground_plane(world[:])
    app_set_ground_texture(app, nil)

    delete(app.current_scene_path)
    app.current_scene_path = path
    app.e_scene_dirty = false

    teardown_previous_scene_for_load(app)
    app.r_world = world
    world = nil
    if volumes != nil {
        for v in volumes { append(&app.e_volumes, v) }
        delete(volumes)
    }
    app.finished     = false
    app.elapsed_secs = 0
    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    rt.init_camera(app.r_camera)
    app.r_session = rt.start_render_auto(app.r_camera, app.r_world, app.num_threads, app.prefer_gpu)
    app_push_log(app, fmt.aprintf("Imported: %s (%d objects)", path, len(app.r_world)))

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
        app_push_log(app, fmt.aprintf("Saved as: %s", path))
        return true
    }
    app_push_log(app, fmt.aprintf("Save failed: %s", path))
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
    case .PresetName:
        if len(text) == 0 { delete(text); return }
        layout_save_named_preset(app, text)
        app_push_log(app, fmt.aprintf("Preset saved: %s", text))
    }
}

// file_modal_draw renders the modal overlay. Call after all other drawing (drawn on top).
// Input handling is in file_modal_update — this proc is draw-only.
file_modal_draw :: proc(app: ^App) {
    modal := &app.file_modal
    if !modal.active { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    // Dim background
    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 160})

    // Dialog box
    dialog_w := f32(420)
    dialog_h := f32(130)
    dx := (sw - dialog_w) * 0.5
    dy := (sh - dialog_h) * 0.5
    dialog_rect := rl.Rectangle{dx, dy, dialog_w, dialog_h}

    rl.DrawRectangleRec(dialog_rect, PANEL_BG_COLOR)
    rl.DrawRectangleLinesEx(dialog_rect, 1, BORDER_COLOR)

    // Title bar
    rl.DrawRectangleRec(rl.Rectangle{dx, dy, dialog_w, TITLE_BAR_HEIGHT}, TITLE_BG_COLOR)
    draw_ui_text(app, strings.clone_to_cstring(modal.title, context.temp_allocator), i32(dx) + 8, i32(dy) + 5, 14, TITLE_TEXT_COLOR)

    // Input label
    input_label: cstring
    switch modal.mode {
    case .Import, .SaveAs: input_label = "File path:"
    case .PresetName:      input_label = "Preset name:"
    }
    draw_ui_text(app, input_label, i32(dx) + 10, i32(dy) + 32, 12, CONTENT_TEXT_COLOR)

    // Input box
    input_rect := rl.Rectangle{dx + 10, dy + 48, dialog_w - 20, 22}
    rl.DrawRectangleRec(input_rect, rl.Color{20, 22, 35, 255})
    rl.DrawRectangleLinesEx(input_rect, 1, ACCENT_COLOR)

    // Current text + cursor blink
    disp_text := file_modal_input_string(modal)
    cursor_str := (i32(rl.GetTime() * 2) % 2) == 0 ? "|" : ""
    full_text := strings.concatenate({disp_text, cursor_str}, context.temp_allocator)
    draw_ui_text(app, strings.clone_to_cstring(full_text, context.temp_allocator), i32(input_rect.x) + 4, i32(input_rect.y) + 3, 12, CONTENT_TEXT_COLOR)

    // Buttons (hover highlight only — clicks handled in file_modal_update)
    btn_ok, btn_cancel := modal_button_rects(dx, dy, dialog_w, dialog_h)
    mouse      := rl.GetMousePosition()
    ok_hov     := rl.CheckCollisionPointRec(mouse, btn_ok)
    cancel_hov := rl.CheckCollisionPointRec(mouse, btn_cancel)

    rl.DrawRectangleRec(btn_ok,     ok_hov     ? rl.Color{80, 160, 80, 255} : rl.Color{55, 110, 55, 255})
    rl.DrawRectangleRec(btn_cancel, cancel_hov ? rl.Color{160, 60, 60, 255} : rl.Color{110, 40, 40, 255})
    rl.DrawRectangleLinesEx(btn_ok,     1, BORDER_COLOR)
    rl.DrawRectangleLinesEx(btn_cancel, 1, BORDER_COLOR)
    draw_ui_text(app, "OK",     i32(btn_ok.x) + 12, i32(btn_ok.y) + 3, 12, rl.RAYWHITE)
    draw_ui_text(app, "Cancel", i32(btn_cancel.x) + 5, i32(btn_cancel.y) + 3, 12, rl.RAYWHITE)
}
