package editor

import "core:fmt"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

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

// confirm_load_modal_update handles keyboard and mouse input. Sets input_consumed when active.
confirm_load_modal_update :: proc(app: ^App) {
    modal := &app.e_confirm_load
    if !modal.active { return }

    app.input_consumed = true

    if rl.IsKeyPressed(.ESCAPE) {
        modal.active = false
        return
    }
    if rl.IsKeyPressed(.ENTER) {
        confirm_load_execute(app, false)
        return
    }

    if rl.IsMouseButtonPressed(.LEFT) {
        sw := f32(rl.GetScreenWidth())
        sh := f32(rl.GetScreenHeight())
        dialog_w := f32(480)
        dialog_h := f32(160)
        dx := (sw - dialog_w) * 0.5
        dy := (sh - dialog_h) * 0.5

        btn_save_load, btn_load, btn_cancel := confirm_button_rects(dx, dy, dialog_w, dialog_h)
        mouse := rl.GetMousePosition()
        save_enabled := len(app.current_scene_path) > 0

        if save_enabled && rl.CheckCollisionPointRec(mouse, btn_save_load) {
            confirm_load_execute(app, true)
        } else if rl.CheckCollisionPointRec(mouse, btn_load) {
            confirm_load_execute(app, false)
        } else if rl.CheckCollisionPointRec(mouse, btn_cancel) {
            modal.active = false
        }
    }
}

@(private="file")
confirm_button_rects :: proc(dx, dy, dialog_w, dialog_h: f32) -> (btn_save_load, btn_load, btn_cancel: rl.Rectangle) {
    by := dy + dialog_h - 34
    btn_save_load = rl.Rectangle{dx + 12,           by, 110, 24}
    btn_load      = rl.Rectangle{dx + 12 + 118,     by, 70,  24}
    btn_cancel    = rl.Rectangle{dx + 12 + 118 + 78, by, 70,  24}
    return
}

// confirm_load_modal_draw renders the confirmation dialog overlay.
confirm_load_modal_draw :: proc(app: ^App) {
    modal := &app.e_confirm_load
    if !modal.active { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    // Dim background
    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 160})

    dialog_w := f32(480)
    dialog_h := f32(160)
    dx := (sw - dialog_w) * 0.5
    dy := (sh - dialog_h) * 0.5
    dialog_rect := rl.Rectangle{dx, dy, dialog_w, dialog_h}

    rl.DrawRectangleRec(dialog_rect, PANEL_BG_COLOR)
    rl.DrawRectangleLinesEx(dialog_rect, 1, BORDER_COLOR)

    // Title bar
    rl.DrawRectangleRec(rl.Rectangle{dx, dy, dialog_w, TITLE_BAR_HEIGHT}, TITLE_BG_COLOR)
    draw_ui_text(app, "Load Example Scene?", i32(dx) + 8, i32(dy) + 5, 14, TITLE_TEXT_COLOR)

    // Body text
    label_c := strings.clone_to_cstring(modal.scene_label, context.temp_allocator)
    line1 := fmt.ctprintf("\"%s\" will replace your current scene.", label_c)
    draw_ui_text(app, line1, i32(dx) + 12, i32(dy) + 36, 12, CONTENT_TEXT_COLOR)
    draw_ui_text(app, "This cannot be undone.", i32(dx) + 12, i32(dy) + 54, 12, CONTENT_TEXT_COLOR)

    // Buttons
    mouse := rl.GetMousePosition()
    save_enabled := len(app.current_scene_path) > 0
    btn_save_load, btn_load, btn_cancel := confirm_button_rects(dx, dy, dialog_w, dialog_h)

    // [Save & Load]
    save_hov := save_enabled && rl.CheckCollisionPointRec(mouse, btn_save_load)
    save_bg: rl.Color
    if !save_enabled {
        save_bg = rl.Color{40, 60, 40, 130}
    } else if save_hov {
        save_bg = rl.Color{80, 160, 80, 255}
    } else {
        save_bg = rl.Color{55, 110, 55, 255}
    }
    rl.DrawRectangleRec(btn_save_load, save_bg)
    rl.DrawRectangleLinesEx(btn_save_load, 1, BORDER_COLOR)
    save_label_col := save_enabled ? rl.RAYWHITE : rl.Color{160, 160, 160, 120}
    draw_ui_text(app, "Save & Load", i32(btn_save_load.x) + 6, i32(btn_save_load.y) + 4, 12, save_label_col)

    // [Load]
    load_hov := rl.CheckCollisionPointRec(mouse, btn_load)
    load_bg := load_hov ? rl.Color{80, 120, 200, 255} : rl.Color{55, 80, 160, 255}
    rl.DrawRectangleRec(btn_load, load_bg)
    rl.DrawRectangleLinesEx(btn_load, 1, BORDER_COLOR)
    draw_ui_text(app, "Load", i32(btn_load.x) + 12, i32(btn_load.y) + 4, 12, rl.RAYWHITE)

    // [Cancel]
    cancel_hov := rl.CheckCollisionPointRec(mouse, btn_cancel)
    cancel_bg := cancel_hov ? rl.Color{160, 60, 60, 255} : rl.Color{110, 40, 40, 255}
    rl.DrawRectangleRec(btn_cancel, cancel_bg)
    rl.DrawRectangleLinesEx(btn_cancel, 1, BORDER_COLOR)
    draw_ui_text(app, "Cancel", i32(btn_cancel.x) + 6, i32(btn_cancel.y) + 4, 12, rl.RAYWHITE)
}

@(private="file")
confirm_load_execute :: proc(app: ^App, save_first: bool) {
    modal := &app.e_confirm_load
    if !app.finished { return }

    if save_first {
        cmd_action_file_save(app)
    }

    spheres, cam := EXAMPLE_SCENES[modal.scene_idx].build()
    defer delete(spheres)

    ev := &app.e_edit_view
    LoadFromSceneSpheres(ev.scene_mgr, spheres)
    ev.selection_kind = .None
    ev.selected_idx   = -1

    app.c_camera_params = cam
    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)

    delete(app.current_scene_path)
    app.current_scene_path = ""

    edit_history_free(&app.edit_history)
    app.edit_history = EditHistory{}

    app.e_scene_dirty = false

    rt.free_session(app.r_session)
    app.r_session = nil

    ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
    delete(app.r_world)
    app.r_world = rt.build_world_from_scene(ev.export_scratch[:])

    app.finished     = false
    app.elapsed_secs = 0
    app.render_start = time.now()

    rt.init_camera(app.r_camera)
    app.r_session = rt.start_render_auto(app.r_camera, app.r_world, app.num_threads, app.prefer_gpu)
    app_push_log(app, fmt.aprintf("Loaded example: %s", modal.scene_label))

    modal.active = false
}
