package editor

import "core:fmt"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import imgui "RT_Weekend:vendor/odin-imgui"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:util"

// Save Changes? modal (exit or import when scene is dirty)
SaveChangesReason :: enum { None, Exit, Import }
SaveChangesModalState :: struct {
    active: bool,
    reason: SaveChangesReason,
}

// User choice: Save (overwrite), Save As (pick path), Cancel, Continue (discard)
SaveChangesChoice :: enum { Save, Save_As, Cancel, Continue }

save_changes_modal_open :: proc(modal: ^SaveChangesModalState, reason: SaveChangesReason) {
    modal.active = true
    modal.reason = reason
}

@(private="file")
save_changes_button_rects :: proc(dx, dy, dialog_w, dialog_h: f32) -> (btn_save, btn_save_as, btn_cancel, btn_continue: rl.Rectangle) {
    by := dy + dialog_h - 34
    btn_save     = rl.Rectangle{dx + 12,         by, 55,  24}
    btn_save_as  = rl.Rectangle{dx + 12 + 63,   by, 65,  24}
    btn_cancel   = rl.Rectangle{dx + 12 + 136,  by, 58,  24}
    btn_continue = rl.Rectangle{dx + 12 + 202, by, 70,  24}
    return
}

@(private="file")
save_changes_do_action :: proc(app: ^App, reason: SaveChangesReason) {
    switch reason {
    case .Exit:
        app.should_exit = true
    case .Import:
        default_dir := util.dialog_default_dir(app.current_scene_path)
        path, ok := util.open_file_dialog(default_dir, util.SCENE_FILTER_DESC, util.SCENE_FILTER_EXT)
        delete(default_dir)
        if ok {
            file_import_from_path(app, path)
        }
    case .None:
        break
    }
}

save_changes_modal_update :: proc(app: ^App) {
    modal := &app.e_save_changes
    if !modal.active { return }

    app.input_consumed = true

    if rl.IsKeyPressed(.ESCAPE) {
        save_changes_modal_apply(app, .Cancel)
        return
    }
    if rl.IsKeyPressed(.ENTER) {
        // Enter = Save if path exists, else Save As (never silently discard — avoid Continue as default)
        if len(app.current_scene_path) > 0 {
            save_changes_modal_apply(app, .Save)
        } else {
            save_changes_modal_apply(app, .Save_As)
        }
        return
    }

    if rl.IsMouseButtonPressed(.LEFT) {
        sw := f32(rl.GetScreenWidth())
        sh := f32(rl.GetScreenHeight())
        dialog_w := f32(460)
        dialog_h := f32(140)
        dx := (sw - dialog_w) * 0.5
        dy := (sh - dialog_h) * 0.5
        btn_save, btn_save_as, btn_cancel, btn_continue := save_changes_button_rects(dx, dy, dialog_w, dialog_h)
        mouse := rl.GetMousePosition()
        save_enabled := len(app.current_scene_path) > 0
        if save_enabled && rl.CheckCollisionPointRec(mouse, btn_save) {
            save_changes_modal_apply(app, .Save)
        } else if rl.CheckCollisionPointRec(mouse, btn_save_as) {
            save_changes_modal_apply(app, .Save_As)
        } else if rl.CheckCollisionPointRec(mouse, btn_cancel) {
            save_changes_modal_apply(app, .Cancel)
        } else if rl.CheckCollisionPointRec(mouse, btn_continue) {
            save_changes_modal_apply(app, .Continue)
        }
    }
}

@(private="file")
save_changes_modal_apply :: proc(app: ^App, choice: SaveChangesChoice) {
    modal := &app.e_save_changes
    reason := modal.reason

    switch choice {
    case .Cancel:
        modal.active = false
        modal.reason = .None
        return
    case .Save:
        if len(app.current_scene_path) > 0 {
            if !cmd_action_file_save(app) {
                return // save failed (e.g. disk full, permissions); keep modal open
            }
        }
        modal.active = false
        modal.reason = .None
        save_changes_do_action(app, reason)
    case .Save_As:
        default_dir := util.dialog_default_dir(app.current_scene_path)
        path, ok := util.save_file_dialog(default_dir, "scene.json", util.SCENE_FILTER_DESC, util.SCENE_FILTER_EXT)
        delete(default_dir)
        if !ok { return } // user cancelled; modal stays open
        if !file_save_as_path(app, path) {
            return // save failed; keep modal open
        }
        modal.active = false
        modal.reason = .None
        save_changes_do_action(app, reason)
    case .Continue:
        modal.active = false
        modal.reason = .None
        save_changes_do_action(app, reason)
    }
}

save_changes_modal_draw :: proc(app: ^App) {
    modal := &app.e_save_changes
    if !modal.active { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    dialog_w := f32(460)
    dialog_h := f32(140)
    dx := (sw - dialog_w) * 0.5
    dy := (sh - dialog_h) * 0.5
    dialog_rect := rl.Rectangle{dx, dy, dialog_w, dialog_h}

    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 160})
    rl.DrawRectangleRec(dialog_rect, PANEL_BG_COLOR)
    rl.DrawRectangleLinesEx(dialog_rect, 1, BORDER_COLOR)
    rl.DrawRectangleRec(rl.Rectangle{dx, dy, dialog_w, TITLE_BAR_HEIGHT}, TITLE_BG_COLOR)
    rl.DrawText( "Save Changes?", i32(dx) + 8, i32(dy) + 5, 14, TITLE_TEXT_COLOR)
    if modal.reason == .Exit {
        rl.DrawText( "Save before closing?", i32(dx) + 12, i32(dy) + 36, 12, CONTENT_TEXT_COLOR)
    } else {
        rl.DrawText( "Save before loading another scene?", i32(dx) + 12, i32(dy) + 36, 12, CONTENT_TEXT_COLOR)
    }

    btn_save, btn_save_as, btn_cancel, btn_continue := save_changes_button_rects(dx, dy, dialog_w, dialog_h)
    mouse := rl.GetMousePosition()
    save_enabled := len(app.current_scene_path) > 0
    save_hov     := save_enabled && rl.CheckCollisionPointRec(mouse, btn_save)
    save_as_hov  := rl.CheckCollisionPointRec(mouse, btn_save_as)
    cancel_hov   := rl.CheckCollisionPointRec(mouse, btn_cancel)
    continue_hov := rl.CheckCollisionPointRec(mouse, btn_continue)

    save_bg: rl.Color
    if !save_enabled {
        save_bg = rl.Color{40, 60, 40, 130}
    } else if save_hov {
        save_bg = rl.Color{80, 160, 80, 255}
    } else {
        save_bg = rl.Color{55, 110, 55, 255}
    }
    rl.DrawRectangleRec(btn_save, save_bg)
    rl.DrawRectangleRec(btn_save_as,  save_as_hov  ? rl.Color{80, 160, 80, 255} : rl.Color{55, 110, 55, 255})
    rl.DrawRectangleRec(btn_cancel,   cancel_hov   ? rl.Color{160, 60, 60, 255} : rl.Color{110, 40, 40, 255})
    rl.DrawRectangleRec(btn_continue, continue_hov ? rl.Color{80, 120, 200, 255} : rl.Color{55, 80, 160, 255})
    rl.DrawRectangleLinesEx(btn_save, 1, BORDER_COLOR)
    rl.DrawRectangleLinesEx(btn_save_as, 1, BORDER_COLOR)
    rl.DrawRectangleLinesEx(btn_cancel, 1, BORDER_COLOR)
    rl.DrawRectangleLinesEx(btn_continue, 1, BORDER_COLOR)

    save_label_col := save_enabled ? rl.RAYWHITE : rl.Color{160, 160, 160, 120}
    rl.DrawText( "Save",    i32(btn_save.x) + 14,     i32(btn_save.y) + 4, 12, save_label_col)
    rl.DrawText( "Save As", i32(btn_save_as.x) + 8,   i32(btn_save_as.y) + 4, 12, rl.RAYWHITE)
    rl.DrawText( "Cancel",  i32(btn_cancel.x) + 8,    i32(btn_cancel.y) + 4, 12, rl.RAYWHITE)
    rl.DrawText( "Continue", i32(btn_continue.x) + 4, i32(btn_continue.y) + 4, 12, rl.RAYWHITE)
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
        // Save & Load only when dirty (so user can save before replacing); disabled when scene is clean
        save_enabled := app.e_scene_dirty

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
    rl.DrawText( "Load Example Scene?", i32(dx) + 8, i32(dy) + 5, 14, TITLE_TEXT_COLOR)

    // Body text
    label_c := strings.clone_to_cstring(modal.scene_label, context.temp_allocator)
    line1 := fmt.ctprintf("\"%s\" will replace your current scene.", label_c)
    rl.DrawText( line1, i32(dx) + 12, i32(dy) + 36, 12, CONTENT_TEXT_COLOR)
    rl.DrawText( "This cannot be undone.", i32(dx) + 12, i32(dy) + 54, 12, CONTENT_TEXT_COLOR)

    // Buttons: Save & Load enabled only when dirty; Load and Cancel always available
    mouse := rl.GetMousePosition()
    save_enabled := app.e_scene_dirty
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
    rl.DrawText( "Save & Load", i32(btn_save_load.x) + 6, i32(btn_save_load.y) + 4, 12, save_label_col)

    // [Load]
    load_hov := rl.CheckCollisionPointRec(mouse, btn_load)
    load_bg := load_hov ? rl.Color{80, 120, 200, 255} : rl.Color{55, 80, 160, 255}
    rl.DrawRectangleRec(btn_load, load_bg)
    rl.DrawRectangleLinesEx(btn_load, 1, BORDER_COLOR)
    rl.DrawText( "Load", i32(btn_load.x) + 12, i32(btn_load.y) + 4, 12, rl.RAYWHITE)

    // [Cancel]
    cancel_hov := rl.CheckCollisionPointRec(mouse, btn_cancel)
    cancel_bg := cancel_hov ? rl.Color{160, 60, 60, 255} : rl.Color{110, 40, 40, 255}
    rl.DrawRectangleRec(btn_cancel, cancel_bg)
    rl.DrawRectangleLinesEx(btn_cancel, 1, BORDER_COLOR)
    rl.DrawText( "Cancel", i32(btn_cancel.x) + 6, i32(btn_cancel.y) + 4, 12, rl.RAYWHITE)
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
    app.r_session = rt.start_render_auto(app.r_camera, app.r_world, app.num_threads, app.prefer_gpu)
    return true
}

@(private="file")
confirm_load_execute :: proc(app: ^App, save_first: bool) {
    modal := &app.e_confirm_load
    if !app.finished { return }
    if load_example_at(app, modal.scene_idx, save_first) {
        app_push_log(app, fmt.aprintf("Loaded example: %s", modal.scene_label))
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
