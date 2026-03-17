package editor

// imgui_panels_stub.odin — ImGui menu bar and panel stub windows.
//
// Each panel proc calls imgui.Begin/End with p_open pointing into
// app.e_panel_vis so the built-in close button works immediately.
// Replace each stub body in the corresponding Track task (A–E).

import "core:strings"
import imgui "RT_Weekend:vendor/odin-imgui"

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

imgui_draw_render_panel :: proc(app: ^App) {
    if !app.e_panel_vis.render { return }
    if imgui.Begin("Render Preview", &app.e_panel_vis.render) {
        imgui.Text("(render panel — Track C)")
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
    if imgui.Begin("Viewport", &app.e_panel_vis.viewport) {
        imgui.Text("(viewport panel — Track C)")
    }
    imgui.End()
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
    if imgui.Begin("Camera Preview", &app.e_panel_vis.camera_preview) {
        imgui.Text("(camera preview — Track C)")
    }
    imgui.End()
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

    // ImGui modal popups (Track E) — drawn after panels so they overlay correctly
    imgui_draw_save_changes_modal(app)
    imgui_draw_confirm_load_modal(app)
    imgui_draw_file_modal(app)

    if app.e_panel_vis.imgui_metrics {
        imgui.ShowMetricsWindow(&app.e_panel_vis.imgui_metrics)
    }
}
