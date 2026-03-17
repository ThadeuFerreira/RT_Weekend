package editor

// imgui_panels_stub.odin — ImGui menu bar and panel stub windows.
//
// Each panel proc calls imgui.Begin/End with p_open pointing into
// app.e_panel_vis so the built-in close button works immediately.
// Replace each stub body in the corresponding Track task (A–E).

import "core:c"
import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import imgui "RT_Weekend:vendor/odin-imgui"
import rl "vendor:raylib"

// imgui_draw_main_menu_bar renders the application main menu bar using Dear
// ImGui.  All items wire to the existing command registry so enabled/checked
// states remain correct.
imgui_draw_main_menu_bar :: proc(app: ^App) {
    if !imgui.BeginMainMenuBar() { return }
    defer imgui.EndMainMenuBar()

    if imgui.BeginMenu("File") {
        if imgui.MenuItem("New",     "Ctrl+N") { cmd_execute(app, CMD_FILE_NEW) }
        if imgui.MenuItem("Import…", "Ctrl+O") { cmd_execute(app, CMD_FILE_IMPORT) }
        imgui.Separator()
        if imgui.MenuItem("Save",    "Ctrl+S", false, cmd_action_file_save_enabled(app)) {
            cmd_execute(app, CMD_FILE_SAVE)
        }
        if imgui.MenuItem("Save As…") { cmd_execute(app, CMD_FILE_SAVE_AS) }
        imgui.Separator()
        if imgui.MenuItem("Exit", "Alt+F4") { cmd_execute(app, CMD_FILE_EXIT) }
        imgui.EndMenu()
    }

    if imgui.BeginMenu("Edit") {
        if imgui.MenuItem("Undo",      "Ctrl+Z", false, cmd_enabled_undo(app))      { cmd_execute(app, CMD_UNDO) }
        if imgui.MenuItem("Redo",      "Ctrl+Y", false, cmd_enabled_redo(app))      { cmd_execute(app, CMD_REDO) }
        imgui.Separator()
        if imgui.MenuItem("Copy",      "Ctrl+C", false, cmd_enabled_copy(app))      { cmd_execute(app, CMD_EDIT_COPY) }
        if imgui.MenuItem("Paste",     "Ctrl+V", false, cmd_enabled_paste(app))     { cmd_execute(app, CMD_EDIT_PASTE) }
        if imgui.MenuItem("Duplicate", "Ctrl+D", false, cmd_enabled_duplicate(app)) { cmd_execute(app, CMD_EDIT_DUPLICATE) }
        imgui.EndMenu()
    }

    if imgui.BeginMenu("View") {
        if imgui.MenuItem("Render Preview",  nil, app.e_panel_vis.render)          { cmd_execute(app, CMD_VIEW_RENDER) }
        if imgui.MenuItem("Stats",           nil, app.e_panel_vis.stats)            { cmd_execute(app, CMD_VIEW_STATS) }
        if imgui.MenuItem("Console",         nil, app.e_panel_vis.console)          { cmd_execute(app, CMD_VIEW_CONSOLE) }
        if imgui.MenuItem("System Info",     nil, app.e_panel_vis.system_info)      { cmd_execute(app, CMD_VIEW_SYSINFO) }
        imgui.Separator()
        if imgui.MenuItem("Viewport",        nil, app.e_panel_vis.viewport)         { cmd_execute(app, CMD_VIEW_EDIT) }
        if imgui.MenuItem("Camera",          nil, app.e_panel_vis.camera)           { cmd_execute(app, CMD_VIEW_CAMERA) }
        if imgui.MenuItem("Details",         nil, app.e_panel_vis.details)          { cmd_execute(app, CMD_VIEW_PROPS) }
        if imgui.MenuItem("Camera Preview",  nil, app.e_panel_vis.camera_preview)   { cmd_execute(app, CMD_VIEW_PREVIEW) }
        if imgui.MenuItem("Texture View",    nil, app.e_panel_vis.texture_view)     { cmd_execute(app, CMD_VIEW_TEXTURE) }
        if imgui.MenuItem("Content Browser", nil, app.e_panel_vis.content_browser)  { cmd_execute(app, CMD_VIEW_CONTENT_BROWSER) }
        if imgui.MenuItem("World Outliner",  nil, app.e_panel_vis.outliner)         { cmd_execute(app, CMD_VIEW_OUTLINER) }
        imgui.Separator()
        if imgui.MenuItem("ImGui Metrics",   nil, app.e_panel_vis.imgui_metrics)    {
            app.e_panel_vis.imgui_metrics = !app.e_panel_vis.imgui_metrics
        }
        imgui.EndMenu()
    }

    if imgui.BeginMenu("Examples") {
        for scene, i in EXAMPLE_SCENES {
            label := strings.clone_to_cstring(scene.label, context.temp_allocator)
            if imgui.MenuItem(label) {
                app.e_confirm_load.scene_idx = i
                cmd_execute(app, CMD_SCENE_LOAD_EXAMPLE)
            }
        }
        imgui.EndMenu()
    }

    if imgui.BeginMenu("Render") {
        if imgui.MenuItem("Restart", "F5") { cmd_execute(app, CMD_RENDER_RESTART) }
        imgui.Separator()
        if imgui.MenuItem("Start Visual Benchmark", nil, false, cmd_enabled_benchmark_start(app)) {
            cmd_execute(app, CMD_BENCHMARK_START)
        }
        if imgui.MenuItem("Stop Visual Benchmark", nil, false, cmd_enabled_benchmark_stop(app)) {
            cmd_execute(app, CMD_BENCHMARK_STOP)
        }
        imgui.EndMenu()
    }
}

// ─── Panel stubs ──────────────────────────────────────────────────────────────
// Each proc below is a placeholder.  Replace the body with real ImGui widgets
// in the corresponding migration track (see the plan comment).

@(private)
_imgui_fit_size :: proc(avail: imgui.Vec2, aspect: f32) -> imgui.Vec2 {
    size := avail
    if size.x <= 0 { size.x = 1 }
    if size.y <= 0 { size.y = 1 }
    if size.x / max(size.y, 1) > aspect {
        size = imgui.Vec2{size.y * aspect, size.y}
    } else {
        size = imgui.Vec2{size.x, size.x / aspect}
    }
    return size
}

@(private)
_imgui_update_int_string :: proc(dst: ^string, value: int) {
    next := fmt.aprintf("%d", value)
    delete(dst^)
    dst^ = next
}

@(private)
_imgui_render_settings_height :: proc() -> f32 {
    // 4 rows of controls + one text line; +12 = extra vertical padding so the image area doesn't feel cramped.
    return imgui.GetFrameHeightWithSpacing() * 4 + imgui.GetTextLineHeightWithSpacing() + 12
}

imgui_draw_render_panel :: proc(app: ^App) {
    if !app.e_panel_vis.render { return }
    flags := imgui.WindowFlags{.NoScrollbar, .NoScrollWithMouse}
    if imgui.Begin("Render Preview", &app.e_panel_vis.render, flags) {
        avail := imgui.GetContentRegionAvail()
        settings_h := _imgui_render_settings_height()
        image_h := max(avail.y - settings_h, 120)
        if imgui.BeginChild("RenderImage", imgui.Vec2{-1, image_h}, {.Borders}) {
            tex_id := imgui.TextureID(uintptr(app.render_tex.id))
            img_avail := imgui.GetContentRegionAvail()
            aspect := f32(app.render_tex.width) / max(f32(app.render_tex.height), 1)
            size := _imgui_fit_size(img_avail, aspect)
            imgui.Image(tex_id, size)
        }
        imgui.EndChild()

        imgui.Separator()
        height, _ := strconv.parse_int(strings.trim_space(app.r_height_input))
        samples, _ := strconv.parse_int(strings.trim_space(app.r_samples_input))
        height_i := c.int(max(height, 1))
        samples_i := c.int(max(samples, 1))
        if imgui.InputInt("Height", &height_i) {
            if height_i < 1 { height_i = 1 }
            _imgui_update_int_string(&app.r_height_input, int(height_i))
            app.r_render_pending = true
        }
        if imgui.InputInt("Samples", &samples_i) {
            if samples_i < 1 { samples_i = 1 }
            _imgui_update_int_string(&app.r_samples_input, int(samples_i))
            app.r_render_pending = true
        }

        preview: cstring = "4:3"
        if app.r_aspect_ratio == RENDER_ASPECT_16_9 { preview = "16:9" }
        if imgui.BeginCombo("Aspect", preview) {
            aspect_options := [2]cstring{"4:3", "16:9"}
            for label, i in aspect_options {
                selected := app.r_aspect_ratio == i
                if imgui.Selectable(label, selected) {
                    app.r_aspect_ratio = i
                    app.r_render_pending = true
                }
            }
            imgui.EndCombo()
        }
        _ = imgui.Checkbox("Use GPU (next render)", &app.prefer_gpu)
        _ = imgui.Checkbox("Show Progress", &app.show_intermediate_render)
    }
    imgui.End()
}

imgui_draw_stats_panel :: proc(app: ^App) {
    if !app.e_panel_vis.stats { return }
    if imgui.Begin("Stats", &app.e_panel_vis.stats) {
        imgui.Text("(stats panel — Track A)")
    }
    imgui.End()
}

imgui_draw_console_panel :: proc(app: ^App) {
    if !app.e_panel_vis.console { return }
    if imgui.Begin("Console", &app.e_panel_vis.console) {
        imgui.Text("(console panel — Track A)")
    }
    imgui.End()
}

imgui_draw_system_info_panel :: proc(app: ^App) {
    if !app.e_panel_vis.system_info { return }
    if imgui.Begin("System Info", &app.e_panel_vis.system_info) {
        imgui.Text("(system info panel — Track A)")
    }
    imgui.End()
}

imgui_draw_viewport_panel :: proc(app: ^App) {
    if !app.e_panel_vis.viewport { return }
    imgui.PushStyleVarImVec2(.WindowPadding, imgui.Vec2{0, 0})
    if imgui.Begin("Viewport", &app.e_panel_vis.viewport) {
        size := imgui.GetContentRegionAvail()
        app.e_edit_view.tex_w = max(i32(size.x), 1)
        app.e_edit_view.tex_h = max(i32(size.y), 1)

        tex_id := imgui.TextureID(uintptr(app.e_edit_view.viewport_tex.texture.id))
        imgui.Image(tex_id, size, imgui.Vec2{0, 1}, imgui.Vec2{1, 0})

        hovered := imgui.IsItemHovered()
        ev := &app.e_edit_view
        if hovered && rl.IsMouseButtonDown(.RIGHT) {
            if !ev.rmb_held {
                ev.rmb_held = true
                ev.last_mouse = rl.GetMousePosition()
            } else {
                mouse := rl.GetMousePosition()
                delta := mouse - ev.last_mouse
                ev.last_mouse = mouse
                ev.camera_yaw -= delta.x * 0.01
                ev.camera_pitch -= delta.y * 0.01
                ev.camera_pitch = clamp(ev.camera_pitch, -math.PI/2 + 0.01, math.PI/2 - 0.01)
                update_orbit_camera(ev)
            }
        } else if ev.rmb_held {
            ev.rmb_held = false
        }
    }
    imgui.End()
    imgui.PopStyleVar()
}

imgui_draw_camera_panel :: proc(app: ^App) {
    if !app.e_panel_vis.camera { return }
    if imgui.Begin("Camera", &app.e_panel_vis.camera) {
        imgui.Text("(camera panel — Track B)")
    }
    imgui.End()
}

imgui_draw_details_panel :: proc(app: ^App) {
    if !app.e_panel_vis.details { return }
    if imgui.Begin("Details", &app.e_panel_vis.details) {
        imgui.Text("(details panel — Track D)")
    }
    imgui.End()
}

imgui_draw_camera_preview_panel :: proc(app: ^App) {
    if !app.e_panel_vis.camera_preview { return }
    imgui.PushStyleVarImVec2(.WindowPadding, imgui.Vec2{0, 0})
    if imgui.Begin("Camera Preview", &app.e_panel_vis.camera_preview) {
        if app.preview_port_w > 0 && app.preview_port_h > 0 {
            avail := imgui.GetContentRegionAvail()
            aspect := f32(app.preview_port_w) / max(f32(app.preview_port_h), 1)
            size := _imgui_fit_size(avail, aspect)
            tex_id := imgui.TextureID(uintptr(app.preview_port_tex.texture.id))
            imgui.Image(tex_id, size, imgui.Vec2{0, 1}, imgui.Vec2{1, 0})
        } else {
            imgui.TextUnformatted("(camera preview unavailable)")
        }
    }
    imgui.End()
    imgui.PopStyleVar()
}

imgui_draw_texture_view_panel :: proc(app: ^App) {
    if !app.e_panel_vis.texture_view { return }
    if imgui.Begin("Texture View", &app.e_panel_vis.texture_view) {
        imgui.Text("(texture view — Track A)")
    }
    imgui.End()
}

imgui_draw_content_browser_panel :: proc(app: ^App) {
    if !app.e_panel_vis.content_browser { return }
    if imgui.Begin("Content Browser", &app.e_panel_vis.content_browser) {
        imgui.Text("(content browser — Track A)")
    }
    imgui.End()
}

imgui_draw_outliner_panel :: proc(app: ^App) {
    if !app.e_panel_vis.outliner { return }
    if imgui.Begin("World Outliner", &app.e_panel_vis.outliner) {
        imgui.Text("(world outliner — Track B)")
    }
    imgui.End()
}

// imgui_draw_all_panels draws the DockSpace, menu bar, and all panel windows.
// Call this between imgui_rl_new_frame() and imgui_rl_render().
imgui_draw_all_panels :: proc(app: ^App) {
    imgui.DockSpaceOverViewport({}, nil, {.PassthruCentralNode})
    imgui_draw_main_menu_bar(app)
    imgui_draw_render_panel(app)
    imgui_draw_stats_panel(app)
    imgui_draw_console_panel(app)
    imgui_draw_system_info_panel(app)
    imgui_draw_viewport_panel(app)
    imgui_draw_camera_panel(app)
    imgui_draw_details_panel(app)
    imgui_draw_camera_preview_panel(app)
    imgui_draw_texture_view_panel(app)
    imgui_draw_content_browser_panel(app)
    imgui_draw_outliner_panel(app)
    if app.e_panel_vis.imgui_metrics {
        imgui.ShowMetricsWindow(&app.e_panel_vis.imgui_metrics)
    }
}
