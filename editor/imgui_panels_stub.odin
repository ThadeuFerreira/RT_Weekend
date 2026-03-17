package editor

// imgui_panels_stub.odin — ImGui menu bar and panel stub windows.
//
// Each panel proc calls imgui.Begin/End with p_open pointing into
// app.e_panel_vis so the built-in close button works immediately.
// Replace each stub body in the corresponding Track task (A–E).

import "core:fmt"
import "core:strings"
import "RT_Weekend:core"
import imgui "RT_Weekend:vendor/odin-imgui"
import rt "RT_Weekend:raytrace"
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
_imgui_u8_buffer_len :: proc(buf: []u8) -> int {
    for b, i in buf {
        if b == 0 { return i }
    }
    return len(buf)
}

@(private)
_imgui_show_texture :: proc(tex_id: u32, tex_w, tex_h: i32) {
    if tex_id == 0 || tex_w <= 0 || tex_h <= 0 { return }
    avail := imgui.GetContentRegionAvail()
    if avail.x <= 1 || avail.y <= 1 { return }

    aspect := f32(tex_w) / max(f32(tex_h), 1)
    draw_size := avail
    if draw_size.x / max(draw_size.y, 1) > aspect {
        draw_size.x = draw_size.y * aspect
    } else {
        draw_size.y = draw_size.x / aspect
    }

    imgui.Image(imgui.TextureID(uintptr(tex_id)), draw_size, imgui.Vec2{0, 1}, imgui.Vec2{1, 0})
}

@(private)
_content_browser_sync_filter_lower :: proc(st: ^ContentBrowserState) {
    if st == nil { return }
    st.filter_len = _imgui_u8_buffer_len(st.filter_input[:])
    filter_lower_new := strings.to_lower(content_browser_filter_string(st))
    if filter_lower_new != st.filter_lower {
        delete(st.filter_lower)
        st.filter_lower = filter_lower_new
    } else {
        delete(filter_lower_new)
    }
}

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
        if app.r_session == nil {
            imgui.TextUnformatted("No active render")
        } else {
            progress := rt.get_render_progress(app.r_session)
            imgui.ProgressBar(progress, imgui.Vec2{-1, 0})
            imgui.Separator()
            mode := "GPU" if app.r_session.use_gpu else "CPU"
            imgui.Text("Mode:     %s", mode)
            imgui.Text("Elapsed:  %.2fs", app.elapsed_secs)
            imgui.Text("Threads:  %d", app.num_threads)
            imgui.Text("Res:      %dx%d @ %d spp",
                app.r_camera.image_width, app.r_camera.image_height, app.r_camera.samples_per_pixel)
            if app.finished {
                imgui.TextUnformatted("Status:   Done")
            } else {
                imgui.TextUnformatted("Status:   Rendering...")
            }
        }
    }
    imgui.End()
}

imgui_draw_console_panel :: proc(app: ^App) {
    if !app.e_panel_vis.console { return }
    if imgui.Begin("Console", &app.e_panel_vis.console) {
        // Oldest-first so newest entries appear at the bottom (standard console convention)
        count := min(app.log_count, LOG_RING_SIZE)
        start := (app.log_count - count) % LOG_RING_SIZE
        for i in 0..<count {
            idx := (start + i) % LOG_RING_SIZE
            line := app.log_lines[idx]
            if len(line) > 0 {
                imgui.TextUnformatted(strings.clone_to_cstring(line, context.temp_allocator))
            }
        }
        if imgui.GetScrollY() >= imgui.GetScrollMaxY() {
            imgui.SetScrollHereY(1.0)
        }
    }
    imgui.End()
}

imgui_draw_system_info_panel :: proc(app: ^App) {
    if !app.e_panel_vis.system_info { return }
    if imgui.Begin("System Info", &app.e_panel_vis.system_info) {
        // Use cached system info (queried once at startup; never changes at runtime)
        imgui.Text("Odin:      %v", app.system_info.OdinVersion)
        imgui.Text("OS:        %v", app.system_info.OS.Name)
        imgui.Text("CPU:       %v", app.system_info.CPU.Name)
        imgui.Text("CPU cores: %vc/%vt", app.system_info.CPU.Cores, app.system_info.CPU.LogicalCores)
        imgui.Text("RAM:       %#.1M", app.system_info.RAM.Total)
        for gpu in app.system_info.GPUs {
            imgui.Separator()
            imgui.Text("GPU:       %v", gpu.Model)
            imgui.Text("Vendor:    %v", gpu.Vendor)
            imgui.Text("VRAM:      %#.1M", gpu.VRAM)
        }
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
        st := &app.e_camera_panel

        commit_camera_undo_if_needed :: proc(app: ^App) {
            st := &app.e_camera_panel
            if st.imgui_drag_active && imgui.IsItemDeactivatedAfterEdit() {
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
                edit_history_push(&app.edit_history, ModifyCameraAction{
                    before = st.imgui_drag_before,
                    after  = app.c_camera_params,
                })
                mark_scene_dirty(app)
                st.imgui_drag_active = false
            }
        }

        begin_camera_undo_if_needed :: proc(app: ^App) {
            st := &app.e_camera_panel
            if imgui.IsItemActivated() {
                st.imgui_drag_before = app.c_camera_params
                st.imgui_drag_active = true
            }
        }

        clamp_shutter_invariants :: proc(params: ^core.CameraParams) {
            params.shutter_open  = clamp(params.shutter_open,  f32(0), f32(1))
            params.shutter_close = clamp(params.shutter_close, f32(0), f32(1))
            if params.shutter_open > params.shutter_close {
                params.shutter_close = params.shutter_open
            }
        }

        // NOTE: We call apply_scene_camera while dragging so dependent views stay in sync.
        // We only push undo + dirty on gesture end (IsItemDeactivatedAfterEdit()).

        if imgui.DragFloat("FOV", &app.c_camera_params.vfov, 0.5, 1, 120, "%.1f°") {
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        begin_camera_undo_if_needed(app)
        commit_camera_undo_if_needed(app)

        if imgui.DragFloat3("Look From", &app.c_camera_params.lookfrom, 0.02, 0, 0, "%.3f") {
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        begin_camera_undo_if_needed(app)
        commit_camera_undo_if_needed(app)

        if imgui.DragFloat3("Look At", &app.c_camera_params.lookat, 0.02, 0, 0, "%.3f") {
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        begin_camera_undo_if_needed(app)
        commit_camera_undo_if_needed(app)

        if imgui.DragFloat("Defocus Angle", &app.c_camera_params.defocus_angle, 0.02, 0, 0, "%.3f") {
            if app.c_camera_params.defocus_angle < 0 { app.c_camera_params.defocus_angle = 0 }
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        begin_camera_undo_if_needed(app)
        commit_camera_undo_if_needed(app)

        if imgui.DragFloat("Focus Dist", &app.c_camera_params.focus_dist, 0.05, 0.1, 0, "%.3f") {
            if app.c_camera_params.focus_dist < 0.1 { app.c_camera_params.focus_dist = 0.1 }
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        begin_camera_undo_if_needed(app)
        commit_camera_undo_if_needed(app)

        if imgui.ColorEdit3("Background", &app.c_camera_params.background) {
            // background already in [0..1] with default ImGui behavior, but clamp defensively
            app.c_camera_params.background[0] = clamp(app.c_camera_params.background[0], f32(0), f32(1))
            app.c_camera_params.background[1] = clamp(app.c_camera_params.background[1], f32(0), f32(1))
            app.c_camera_params.background[2] = clamp(app.c_camera_params.background[2], f32(0), f32(1))
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        begin_camera_undo_if_needed(app)
        commit_camera_undo_if_needed(app)

        if imgui.SliderFloat("Shutter Open", &app.c_camera_params.shutter_open, 0, 1) {
            clamp_shutter_invariants(&app.c_camera_params)
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        begin_camera_undo_if_needed(app)
        commit_camera_undo_if_needed(app)

        if imgui.SliderFloat("Shutter Close", &app.c_camera_params.shutter_close, 0, 1) {
            clamp_shutter_invariants(&app.c_camera_params)
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        begin_camera_undo_if_needed(app)
        commit_camera_undo_if_needed(app)
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
        tex, has_tex := texture_view_current(app)
        if !has_tex {
            imgui.TextUnformatted("No texture")
            imgui.TextUnformatted("Select a sphere in the Viewport to preview its material.")
        } else {
            sig := texture_view_sig(app, tex)
            defer delete(sig)
            need_rebuild := !app.e_texture_view.valid || app.e_texture_view.last_sig != sig

            if need_rebuild {
                if app.e_texture_view.valid {
                    rl.UnloadTexture(app.e_texture_view.preview_tex)
                    app.e_texture_view.valid = false
                }
                delete(app.e_texture_view.last_sig)
                app.e_texture_view.last_sig = strings.clone(sig)

                img, buf_to_free, ok := texture_view_build_image(app, tex)
                if ok {
                    // Capture dimensions before unload; rl.UnloadImage zeroes data pointer only,
                    // but reading after is fragile (implementation-dependent)
                    w, h := img.width, img.height
                    app.e_texture_view.preview_tex = rl.LoadTextureFromImage(img)
                    if buf_to_free != nil {
                        delete(buf_to_free)
                    } else {
                        rl.UnloadImage(img)
                    }
                    if rl.IsTextureValid(app.e_texture_view.preview_tex) {
                        app.e_texture_view.preview_w = w
                        app.e_texture_view.preview_h = h
                        app.e_texture_view.valid = true
                    } else {
                        rl.UnloadTexture(app.e_texture_view.preview_tex)
                        app.e_texture_view.valid = false
                    }
                }
            }

            if app.e_texture_view.valid {
                _imgui_show_texture(app.e_texture_view.preview_tex.id, app.e_texture_view.preview_w, app.e_texture_view.preview_h)
            } else {
                imgui.TextUnformatted("Texture unavailable")
            }
        }
    }
    imgui.End()
}

imgui_draw_content_browser_panel :: proc(app: ^App) {
    if !app.e_panel_vis.content_browser { return }
    if imgui.Begin("Content Browser", &app.e_panel_vis.content_browser) {
        st := &app.e_content_browser
        if st.scan_requested || !st.scanned {
            content_browser_scan_assets(app)
        }

        // Only sync filter when InputText returns true (text changed), avoiding per-frame alloc
        if imgui.InputText("Filter", cstring(&st.filter_input[0]), CONTENT_BROWSER_FILTER_MAX) {
            _content_browser_sync_filter_lower(st)
        }
        imgui.SameLine()
        if imgui.Button("Refresh") {
            st.scan_requested = true
        }
        imgui.Separator()

        visible_count := 0
        if imgui.BeginChild("Assets", imgui.Vec2{-1, 220}, {.Borders}) {
            for asset, asset_idx in st.assets {
                if content_browser_matches_filter(asset, st.filter_lower) {
                    visible_count += 1
                    prefix := "T"
                    if asset.kind == .Scene { prefix = "S" }
                    label := fmt.aprintf("[%s] %s##asset_%d", prefix, asset.name, asset_idx,
                        allocator = context.temp_allocator)
                    selected := asset_idx == st.selected_idx
                    if imgui.Selectable(strings.clone_to_cstring(label, context.temp_allocator), selected) {
                        st.selected_idx = asset_idx
                    }
                }
            }
            if visible_count == 0 {
                imgui.TextUnformatted("No assets match the current filter")
            }
        }
        imgui.EndChild()

        asset := content_browser_selected_asset(app)
        content_browser_ensure_preview(app)
        imgui.Separator()

        if asset == nil {
            imgui.TextUnformatted("Select an asset")
        } else {
            imgui.TextUnformatted(strings.clone_to_cstring(asset.name, context.temp_allocator))
            imgui.TextUnformatted(strings.clone_to_cstring(asset.path, context.temp_allocator))
            if imgui.BeginChild("Preview", imgui.Vec2{-1, 220}, {.Borders}) {
                if asset.kind == .Texture && st.preview_valid {
                    _imgui_show_texture(st.preview_tex.id, st.preview_w, st.preview_h)
                } else if asset.kind == .Scene {
                    imgui.TextUnformatted("Scene asset")
                    imgui.TextUnformatted("Use Open Scene to load it into the editor.")
                } else {
                    imgui.TextUnformatted("Texture preview unavailable")
                }
            }
            imgui.EndChild()
        }

        primary_enabled := asset != nil && asset.kind == .Texture
        secondary_enabled := asset != nil && asset.kind == .Scene
        if primary_enabled {
            if imgui.Button("Assign Texture") {
                _ = content_browser_assign_texture(app, asset.path)
            }
        } else {
            imgui.TextDisabled("Assign Texture")
        }
        if secondary_enabled {
            if imgui.Button("Open Scene") {
                content_browser_open_scene(app, asset.path)
            }
        } else {
            imgui.TextDisabled("Open Scene")
        }
    }
    imgui.End()
}

imgui_draw_outliner_panel :: proc(app: ^App) {
    if !app.e_panel_vis.outliner { return }
    if imgui.Begin("World Outliner", &app.e_panel_vis.outliner) {
        ev := &app.e_edit_view
        sm := ev.scene_mgr

        obj_count := SceneManagerLen(sm)
        vol_count := len(app.e_volumes)

        any_rows := false

        for i in 0..<obj_count {
            if sphere, ok := GetSceneSphere(sm, i); ok {
                any_rows = true
                label := fmt.ctprintf("Sphere %d  (%.2f, %.2f, %.2f)", i, sphere.center[0], sphere.center[1], sphere.center[2])
                is_sel := ev.selection_kind == .Sphere && ev.selected_idx == i
                if imgui.Selectable(label, is_sel) {
                    ev.selection_kind = .Sphere
                    ev.selected_idx   = i
                }
                continue
            }
            if quad, ok := GetSceneQuad(sm, i); ok {
                _ = quad
                any_rows = true
                label := fmt.ctprintf("Quad %d  (%.2f, %.2f, %.2f)", i, quad.Q[0], quad.Q[1], quad.Q[2])
                is_sel := ev.selection_kind == .Quad && ev.selected_idx == i
                if imgui.Selectable(label, is_sel) {
                    ev.selection_kind = .Quad
                    ev.selected_idx   = i
                }
                continue
            }
        }

        for i in 0..<vol_count {
            any_rows = true
            label := fmt.ctprintf("Volume %d", i)
            is_sel := ev.selection_kind == .Volume && ev.selected_idx == i
            if imgui.Selectable(label, is_sel) {
                ev.selection_kind = .Volume
                ev.selected_idx   = i
            }
        }

        if !any_rows {
            imgui.TextDisabled("No objects in scene")
        }
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
