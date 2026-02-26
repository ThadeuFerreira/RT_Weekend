package editor

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
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

// file_modal_confirm processes the modal result based on its mode.
file_modal_confirm :: proc(app: ^App) {
    modal := &app.file_modal
    if !modal.active { return }

    text := strings.clone(file_modal_input_string(modal))
    modal.active = false

    ev := &app.edit_view

    switch modal.mode {
    case .Import:
        if len(text) == 0 { delete(text); return }
        cam, world, ok := persistence.load_scene(text, app.camera.image_width, app.camera.image_height, app.camera.samples_per_pixel)
        if !ok {
            app_push_log(app, fmt.aprintf("Import failed: %s", text))
            delete(text)
            return
        }
        // Apply loaded camera to params
        rt.copy_camera_to_scene_params(&app.camera_params, cam)
        // Load converted spheres into scene manager
        converted := rt.convert_world_to_edit_spheres(world)
LoadFromSceneSpheres(ev.scene_mgr, converted[:])
        delete(converted)
        ev.selection_kind = .None
        ev.selected_idx   = -1

        // Store path
        delete(app.current_scene_path)
        app.current_scene_path = text

        // Restart render
        if !app.finished {
            rt.finish_render(app.session)
            app.finished = true
        }
        rt.free_session(app.session)
        app.session = nil
ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
        delete(app.world)
        app.world = rt.build_world_from_scene(ev.export_scratch[:])
        app.finished     = false
        app.elapsed_secs = 0
        rt.apply_scene_camera(app.camera, &app.camera_params)
        rt.init_camera(app.camera)
        app.session = rt.start_render(app.camera, app.world, app.num_threads)
        app_push_log(app, fmt.aprintf("Imported: %s (%d objects)", text, SceneManagerLen(ev.scene_mgr)))

        // Free the camera returned by load_scene (values already copied into app.camera + params)
        free(cam)
        delete(world)

    case .SaveAs:
        if len(text) == 0 { delete(text); return }
ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
        world := rt.build_world_from_scene(ev.export_scratch[:])
        defer delete(world)
        rt.apply_scene_camera(app.camera, &app.camera_params)
        if persistence.save_scene(text, app.camera, world) {
            delete(app.current_scene_path)
            app.current_scene_path = text
            app_push_log(app, fmt.aprintf("Saved as: %s", text))
        } else {
            app_push_log(app, fmt.aprintf("Save failed: %s", text))
            delete(text)
        }

    case .PresetName:
        if len(text) == 0 { delete(text); return }
        layout_save_named_preset(app, text)
        app_push_log(app, fmt.aprintf("Preset saved: %s", text))
        // text ownership transferred to the preset
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
