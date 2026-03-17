package editor

// imgui_panels_stub.odin — ImGui menu bar and panel stub windows.
//
// Each panel proc calls imgui.Begin/End with p_open pointing into
// app.e_panel_vis so the built-in close button works immediately.
// Replace each stub body in the corresponding Track task (A–E).

import "core:fmt"
import "core:strings"
import "core:c"
import "core:path/filepath"
import "RT_Weekend:core"
import "RT_Weekend:util"
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
        // NOTE: We call apply_scene_camera while dragging so dependent views stay in sync.
        // Undo state lives on app.e_camera_panel (not @(static)) so it resets on scene load.

        if imgui.DragFloat("FOV", &app.c_camera_params.vfov, 0.5, 1, 120, "%.1f°") {
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        _camera_panel_begin_undo_if_needed(app)
        _camera_panel_commit_undo_if_needed(app)

        if imgui.DragFloat3("Look From", &app.c_camera_params.lookfrom, 0.02, 0, 0, "%.3f") {
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        _camera_panel_begin_undo_if_needed(app)
        _camera_panel_commit_undo_if_needed(app)

        if imgui.DragFloat3("Look At", &app.c_camera_params.lookat, 0.02, 0, 0, "%.3f") {
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        _camera_panel_begin_undo_if_needed(app)
        _camera_panel_commit_undo_if_needed(app)

        // v_min=0, v_max=0 means unclamped in ImGui; clamp manually below
        if imgui.DragFloat("Defocus Angle", &app.c_camera_params.defocus_angle, 0.02, 0, 0, "%.3f") {
            if app.c_camera_params.defocus_angle < 0 { app.c_camera_params.defocus_angle = 0 }
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        _camera_panel_begin_undo_if_needed(app)
        _camera_panel_commit_undo_if_needed(app)

        // v_min=0.1, v_max=0 means unclamped in ImGui; clamp manually below
        if imgui.DragFloat("Focus Dist", &app.c_camera_params.focus_dist, 0.05, 0.1, 0, "%.3f") {
            if app.c_camera_params.focus_dist < 0.1 { app.c_camera_params.focus_dist = 0.1 }
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        _camera_panel_begin_undo_if_needed(app)
        _camera_panel_commit_undo_if_needed(app)

        // ColorEdit3 always produces values in [0, 1]; no clamp needed
        if imgui.ColorEdit3("Background", &app.c_camera_params.background) {
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        _camera_panel_begin_undo_if_needed(app)
        _camera_panel_commit_undo_if_needed(app)

        if imgui.SliderFloat("Shutter Open", &app.c_camera_params.shutter_open, 0, 1) {
            _camera_panel_clamp_shutter(&app.c_camera_params)
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        _camera_panel_begin_undo_if_needed(app)
        _camera_panel_commit_undo_if_needed(app)

        if imgui.SliderFloat("Shutter Close", &app.c_camera_params.shutter_close, 0, 1) {
            _camera_panel_clamp_shutter(&app.c_camera_params)
            rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
        }
        _camera_panel_begin_undo_if_needed(app)
        _camera_panel_commit_undo_if_needed(app)
    }
    imgui.End()
}

imgui_draw_details_panel :: proc(app: ^App) {
    if !app.e_panel_vis.details { return }
    if imgui.Begin("Details", &app.e_panel_vis.details) {
        ev := &app.e_edit_view
        det := &app.e_details

        switch ev.selection_kind {
        case .None:
            imgui.Text("Nothing selected")
            if len(app.e_volumes) > 0 {
                imgui.Separator()
                imgui.Text("Volumes")
                for i in 0..<len(app.e_volumes) {
                    v := &app.e_volumes[i]
                    imgui.PushIDInt(c.int(i))
                    defer imgui.PopID()

                    imgui.Text(fmt.ctprintf("Volume %d", i))

                    if imgui.DragFloat("Density", &v.density, 0.002, 0.0001, 1.0, "%.4f") {
                        v.density = clamp(v.density, f32(0.0001), f32(1))
                    }
                    if imgui.IsItemActivated() { det.drag_before_volume = v^ }
                    if imgui.IsItemDeactivatedAfterEdit() {
                        edit_history_push(&app.edit_history, ModifyVolumeAction{idx = i, before = det.drag_before_volume, after = v^})
                        mark_scene_dirty(app)
                    }

                    if imgui.ColorEdit3("Albedo", &v.albedo) {}
                    if imgui.IsItemActivated() { det.drag_before_volume = v^ }
                    if imgui.IsItemDeactivatedAfterEdit() {
                        v.albedo[0] = clamp(v.albedo[0], f32(0), f32(1))
                        v.albedo[1] = clamp(v.albedo[1], f32(0), f32(1))
                        v.albedo[2] = clamp(v.albedo[2], f32(0), f32(1))
                        edit_history_push(&app.edit_history, ModifyVolumeAction{idx = i, before = det.drag_before_volume, after = v^})
                        mark_scene_dirty(app)
                    }

                    imgui.Separator()
                }
            }

        case .Camera:
            imgui.Text("Camera")

            imgui.DragFloat("FOV", &app.c_camera_params.vfov, 0.5, 1, 120, "%.1f°")
            if imgui.IsItemActivated() { det.drag_before_c_camera_params = app.c_camera_params }
            if imgui.IsItemDeactivatedAfterEdit() {
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
                edit_history_push(&app.edit_history, ModifyCameraAction{before = det.drag_before_c_camera_params, after = app.c_camera_params})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
            }

            imgui.DragFloat3("Look From", &app.c_camera_params.lookfrom, 0.02, 0, 0, "%.3f")
            if imgui.IsItemActivated() { det.drag_before_c_camera_params = app.c_camera_params }
            if imgui.IsItemDeactivatedAfterEdit() {
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
                edit_history_push(&app.edit_history, ModifyCameraAction{before = det.drag_before_c_camera_params, after = app.c_camera_params})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
            }

            imgui.DragFloat3("Look At", &app.c_camera_params.lookat, 0.02, 0, 0, "%.3f")
            if imgui.IsItemActivated() { det.drag_before_c_camera_params = app.c_camera_params }
            if imgui.IsItemDeactivatedAfterEdit() {
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
                edit_history_push(&app.edit_history, ModifyCameraAction{before = det.drag_before_c_camera_params, after = app.c_camera_params})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
            }

            imgui.DragFloat("Defocus Angle", &app.c_camera_params.defocus_angle, 0.02, 0, 0, "%.3f")
            if imgui.IsItemActivated() { det.drag_before_c_camera_params = app.c_camera_params }
            if imgui.IsItemDeactivatedAfterEdit() {
                if app.c_camera_params.defocus_angle < 0 { app.c_camera_params.defocus_angle = 0 }
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
                edit_history_push(&app.edit_history, ModifyCameraAction{before = det.drag_before_c_camera_params, after = app.c_camera_params})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                if app.c_camera_params.defocus_angle < 0 { app.c_camera_params.defocus_angle = 0 }
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
            }

            imgui.DragFloat("Focus Dist", &app.c_camera_params.focus_dist, 0.05, 0.1, 0, "%.3f")
            if imgui.IsItemActivated() { det.drag_before_c_camera_params = app.c_camera_params }
            if imgui.IsItemDeactivatedAfterEdit() {
                if app.c_camera_params.focus_dist < 0.1 { app.c_camera_params.focus_dist = 0.1 }
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
                edit_history_push(&app.edit_history, ModifyCameraAction{before = det.drag_before_c_camera_params, after = app.c_camera_params})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                if app.c_camera_params.focus_dist < 0.1 { app.c_camera_params.focus_dist = 0.1 }
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
            }

            imgui.ColorEdit3("Background", &app.c_camera_params.background)
            if imgui.IsItemActivated() { det.drag_before_c_camera_params = app.c_camera_params }
            if imgui.IsItemDeactivatedAfterEdit() {
                app.c_camera_params.background[0] = clamp(app.c_camera_params.background[0], f32(0), f32(1))
                app.c_camera_params.background[1] = clamp(app.c_camera_params.background[1], f32(0), f32(1))
                app.c_camera_params.background[2] = clamp(app.c_camera_params.background[2], f32(0), f32(1))
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
                edit_history_push(&app.edit_history, ModifyCameraAction{before = det.drag_before_c_camera_params, after = app.c_camera_params})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
            }

            imgui.SliderFloat("Shutter Open", &app.c_camera_params.shutter_open, 0, 1)
            if imgui.IsItemActivated() { det.drag_before_c_camera_params = app.c_camera_params }
            if imgui.IsItemDeactivatedAfterEdit() {
                _camera_panel_clamp_shutter(&app.c_camera_params)
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
                edit_history_push(&app.edit_history, ModifyCameraAction{before = det.drag_before_c_camera_params, after = app.c_camera_params})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                _camera_panel_clamp_shutter(&app.c_camera_params)
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
            }

            imgui.SliderFloat("Shutter Close", &app.c_camera_params.shutter_close, 0, 1)
            if imgui.IsItemActivated() { det.drag_before_c_camera_params = app.c_camera_params }
            if imgui.IsItemDeactivatedAfterEdit() {
                _camera_panel_clamp_shutter(&app.c_camera_params)
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
                edit_history_push(&app.edit_history, ModifyCameraAction{before = det.drag_before_c_camera_params, after = app.c_camera_params})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                _camera_panel_clamp_shutter(&app.c_camera_params)
                rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
            }

        case .Sphere:
            if ev.selected_idx < 0 { break }
            sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx)
            if !ok { break }

            imgui.Text(fmt.ctprintf("Sphere %d", ev.selected_idx))

            imgui.DragFloat3("Center", &sphere.center, 0.02, 0, 0, "%.3f")
            if imgui.IsItemActivated() { det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx) }
            if imgui.IsItemDeactivatedAfterEdit() {
                SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
            }

            imgui.DragFloat("Radius", &sphere.radius, 0.01, 0.001, 0, "%.3f")
            if imgui.IsItemActivated() { det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx) }
            if imgui.IsItemDeactivatedAfterEdit() {
                if sphere.radius < 0.001 { sphere.radius = 0.001 }
                SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                mark_scene_dirty(app)
            } else if imgui.IsItemEdited() {
                if sphere.radius < 0.001 { sphere.radius = 0.001 }
                SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
            }

            kinds := [4]cstring{"Lambertian", "Metallic", "Dielectric", "DiffuseLight"}
            current := c.int(sphere.material_kind)
            imgui.ComboChar("Material", &current, &kinds[0], c.int(len(kinds)))
            if imgui.IsItemActivated() { det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx) }
            if imgui.IsItemDeactivatedAfterEdit() {
                sphere.material_kind = cast(core.MaterialKind)current
                SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                mark_scene_dirty(app)
            }

            // MOTION offset (center1-center)
            motion: [3]f32 = {0, 0, 0}
            if sphere.is_moving {
                motion[0] = sphere.center1[0] - sphere.center[0]
                motion[1] = sphere.center1[1] - sphere.center[1]
                motion[2] = sphere.center1[2] - sphere.center[2]
            }
            imgui.DragFloat3("Motion dX/Y/Z", &motion, 0.02, 0, 0, "%.3f")
            if imgui.IsItemActivated() { det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx) }
            if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                sphere.center1[0] = sphere.center[0] + motion[0]
                sphere.center1[1] = sphere.center[1] + motion[1]
                sphere.center1[2] = sphere.center[2] + motion[2]
                sphere.is_moving = (sphere.center1[0] != sphere.center[0] || sphere.center1[1] != sphere.center[1] || sphere.center1[2] != sphere.center[2])
                SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                if imgui.IsItemDeactivatedAfterEdit() {
                    edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                    mark_scene_dirty(app)
                }
            }

            // Material-specific fields
            switch sphere.material_kind {
            case .Lambertian:
                // ConstantTexture color (also used as "even" for checker)
                col: [3]f32 = {0.5, 0.5, 0.5}
                if ct, okc := sphere.albedo.(core.ConstantTexture); okc { col = ct.color }
                imgui.ColorEdit3("Albedo", &col)
                if imgui.IsItemActivated() { det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx) }
                if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                    sphere.albedo = core.ConstantTexture{color = col}
                    SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                    if imgui.IsItemDeactivatedAfterEdit() {
                        edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                        mark_scene_dirty(app)
                    }
                }

                // Image texture browse / clear
                if it, is_img := sphere.albedo.(core.ImageTexture); is_img {
                    imgui.Text(fmt.ctprintf("Image: %s", filepath.base(it.path)))
                    if imgui.SmallButton("× Clear") {
                        det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx)
                        sphere.albedo = core.ConstantTexture{color = {0.5, 0.5, 0.5}}
                        sphere.texture_kind = .Constant
                        sphere.image_path = ""
                        SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                        edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                        mark_scene_dirty(app)
                    }
                    imgui.SameLine()
                }
                if imgui.SmallButton("Browse…") {
                    default_dir := util.dialog_default_dir(app.current_scene_path)
                    img_path, ok2 := util.open_file_dialog(default_dir, util.IMAGE_FILTER_DESC, util.IMAGE_FILTER_EXT)
                    delete(default_dir)
                    if ok2 {
                        det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx)
                        sphere.albedo = core.ImageTexture{path = img_path}
                        sphere.texture_kind = .Image
                        sphere.image_path = img_path
                        app_ensure_image_cached(app, img_path)
                        SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                        edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                        mark_scene_dirty(app)
                    }
                }

            case .Metallic:
                // metallic albedo in sphere.albedo (stored as Texture; legacy uses ConstantTexture to store RGB)
                col: [3]f32 = {0.5, 0.5, 0.5}
                if ct, okc := sphere.albedo.(core.ConstantTexture); okc { col = ct.color }
                imgui.ColorEdit3("Albedo", &col)
                if imgui.IsItemActivated() { det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx) }
                if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                    sphere.albedo = core.ConstantTexture{color = col}
                    SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                    if imgui.IsItemDeactivatedAfterEdit() {
                        edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                        mark_scene_dirty(app)
                    }
                }

                imgui.DragFloat("Fuzz", &sphere.fuzz, 0.01, 0, 1, "%.3f")
                if imgui.IsItemActivated() { det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx) }
                if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                    sphere.fuzz = clamp(sphere.fuzz, f32(0), f32(1))
                    SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                    if imgui.IsItemDeactivatedAfterEdit() {
                        edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                        mark_scene_dirty(app)
                    }
                }

            case .Dielectric:
                imgui.DragFloat("IOR", &sphere.ref_idx, 0.01, 1, 3, "%.3f")
                if imgui.IsItemActivated() { det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx) }
                if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                    sphere.ref_idx = clamp(sphere.ref_idx, f32(1), f32(3))
                    SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                    if imgui.IsItemDeactivatedAfterEdit() {
                        edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                        mark_scene_dirty(app)
                    }
                }

            case .DiffuseLight:
                col: [3]f32 = {1, 1, 1}
                if ct, okc := sphere.albedo.(core.ConstantTexture); okc { col = ct.color }
                imgui.ColorEdit3("Emit", &col)
                if imgui.IsItemActivated() { det.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, ev.selected_idx) }
                if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                    sphere.albedo = core.ConstantTexture{color = col}
                    SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
                    if imgui.IsItemDeactivatedAfterEdit() {
                        edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = det.drag_before_sphere, after = sphere})
                        mark_scene_dirty(app)
                    }
                }
            case .Isotropic:
                imgui.TextDisabled("Isotropic material editing not supported here")
            }

        case .Quad:
            quad, ok := GetSceneQuad(ev.scene_mgr, ev.selected_idx)
            if !ok { break }
            imgui.Text(fmt.ctprintf("Quad %d", ev.selected_idx))

            // Minimal material editing mirroring old panel_details behavior
            // (lambertian/metallic/dielectric/emitter + color/param).
            kinds := [4]cstring{"Lambertian", "Metallic", "Dielectric", "DiffuseLight"}
            current: c.int = 0
            #partial switch _ in quad.material {
            case rt.lambertian:    current = 0
            case rt.metallic:      current = 1
            case rt.dielectric:    current = 2
            case rt.diffuse_light: current = 3
            }
            imgui.ComboChar("Material", &current, &kinds[0], c.int(len(kinds)))
            if imgui.IsItemActivated() { det.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, ev.selected_idx) }
            if imgui.IsItemDeactivatedAfterEdit() {
                // Rebuild material while preserving color where possible
                col := [3]f32{0.5, 0.5, 0.5}
                #partial switch m in quad.material {
                case rt.lambertian:
                    if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
                    else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
                case rt.metallic:
                    col = m.albedo
                case rt.diffuse_light:
                    // normalize emit to color if possible
                    intensity := max(m.emit[0], max(m.emit[1], m.emit[2]))
                    if intensity > 0 { col = {m.emit[0]/intensity, m.emit[1]/intensity, m.emit[2]/intensity} } else { col = {1, 1, 1} }
                }

                switch int(current) {
                case 0: quad.material = rt.lambertian{albedo = rt.ConstantTexture{color = col}}
                case 1: quad.material = rt.metallic{albedo = col, fuzz = 0.1}
                case 2: quad.material = rt.dielectric{ref_idx = 1.5}
                case 3: quad.material = rt.diffuse_light{emit = {2, 2, 2}}
                }
                SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
                edit_history_push(&app.edit_history, ModifyQuadAction{idx = ev.selected_idx, before = det.drag_before_quad, after = quad})
                mark_scene_dirty(app)
            }

            col := [3]f32{0.5, 0.5, 0.5}
            param: f32 = 0.1
            is_emitter := false
            #partial switch m in quad.material {
            case rt.lambertian:
                if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
                else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
            case rt.metallic:
                col = m.albedo
                param = m.fuzz
            case rt.dielectric:
                param = m.ref_idx
            case rt.diffuse_light:
                is_emitter = true
                intensity := max(m.emit[0], max(m.emit[1], m.emit[2]))
                if intensity > 0 { col = {m.emit[0]/intensity, m.emit[1]/intensity, m.emit[2]/intensity} } else { col = {1, 1, 1} }
                param = intensity
            }

            imgui.ColorEdit3(is_emitter ? "Emit Color" : "Color", &col)
            if imgui.IsItemActivated() { det.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, ev.selected_idx) }
            if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                if is_emitter {
                    quad.material = rt.diffuse_light{emit = {col[0]*param, col[1]*param, col[2]*param}}
                } else {
                    #partial switch m in quad.material {
                    case rt.lambertian:
                        quad.material = rt.lambertian{albedo = rt.ConstantTexture{color = col}}
                    case rt.metallic:
                        quad.material = rt.metallic{albedo = col, fuzz = clamp(param, f32(0), f32(1))}
                    }
                }
                SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
                if imgui.IsItemDeactivatedAfterEdit() {
                    edit_history_push(&app.edit_history, ModifyQuadAction{idx = ev.selected_idx, before = det.drag_before_quad, after = quad})
                    mark_scene_dirty(app)
                }
            }

            if is_emitter {
                imgui.DragFloat("Intensity", &param, 0.02, 0, 50, "%.3f")
                if imgui.IsItemActivated() { det.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, ev.selected_idx) }
                if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                    if param < 0 { param = 0 }
                    quad.material = rt.diffuse_light{emit = {col[0]*param, col[1]*param, col[2]*param}}
                    SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
                    if imgui.IsItemDeactivatedAfterEdit() {
                        edit_history_push(&app.edit_history, ModifyQuadAction{idx = ev.selected_idx, before = det.drag_before_quad, after = quad})
                        mark_scene_dirty(app)
                    }
                }
            } else if current == 1 {
                imgui.DragFloat("Fuzz", &param, 0.01, 0, 1, "%.3f")
                if imgui.IsItemActivated() { det.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, ev.selected_idx) }
                if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                    quad.material = rt.metallic{albedo = col, fuzz = clamp(param, f32(0), f32(1))}
                    SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
                    if imgui.IsItemDeactivatedAfterEdit() {
                        edit_history_push(&app.edit_history, ModifyQuadAction{idx = ev.selected_idx, before = det.drag_before_quad, after = quad})
                        mark_scene_dirty(app)
                    }
                }
            } else if current == 2 {
                imgui.DragFloat("IOR", &param, 0.01, 1, 3, "%.3f")
                if imgui.IsItemActivated() { det.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, ev.selected_idx) }
                if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                    quad.material = rt.dielectric{ref_idx = clamp(param, f32(1), f32(3))}
                    SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
                    if imgui.IsItemDeactivatedAfterEdit() {
                        edit_history_push(&app.edit_history, ModifyQuadAction{idx = ev.selected_idx, before = det.drag_before_quad, after = quad})
                        mark_scene_dirty(app)
                    }
                }
            }

        case .Volume:
            if ev.selected_idx < 0 || ev.selected_idx >= len(app.e_volumes) { break }
            v := app.e_volumes[ev.selected_idx]
            imgui.Text(fmt.ctprintf("Volume %d", ev.selected_idx))

            imgui.DragFloat3("Translate", &v.translate, 0.02, 0, 0, "%.3f")
            if imgui.IsItemActivated() { det.drag_before_volume = v }
            if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                app.e_volumes[ev.selected_idx] = v
                if imgui.IsItemDeactivatedAfterEdit() {
                    edit_history_push(&app.edit_history, ModifyVolumeAction{idx = ev.selected_idx, before = det.drag_before_volume, after = v})
                    mark_scene_dirty(app)
                }
            }

            imgui.DragFloat("Rotate Y (deg)", &v.rotate_y_deg, 0.2, 0, 0, "%.3f")
            if imgui.IsItemActivated() { det.drag_before_volume = v }
            if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                app.e_volumes[ev.selected_idx] = v
                if imgui.IsItemDeactivatedAfterEdit() {
                    edit_history_push(&app.edit_history, ModifyVolumeAction{idx = ev.selected_idx, before = det.drag_before_volume, after = v})
                    mark_scene_dirty(app)
                }
            }

            imgui.DragFloat("Density", &v.density, 0.002, 0.0001, 1.0, "%.4f")
            if imgui.IsItemActivated() { det.drag_before_volume = v }
            if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                v.density = clamp(v.density, f32(0.0001), f32(1))
                app.e_volumes[ev.selected_idx] = v
                if imgui.IsItemDeactivatedAfterEdit() {
                    edit_history_push(&app.edit_history, ModifyVolumeAction{idx = ev.selected_idx, before = det.drag_before_volume, after = v})
                    mark_scene_dirty(app)
                }
            }

            imgui.ColorEdit3("Albedo", &v.albedo)
            if imgui.IsItemActivated() { det.drag_before_volume = v }
            if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
                v.albedo[0] = clamp(v.albedo[0], f32(0), f32(1))
                v.albedo[1] = clamp(v.albedo[1], f32(0), f32(1))
                v.albedo[2] = clamp(v.albedo[2], f32(0), f32(1))
                app.e_volumes[ev.selected_idx] = v
                if imgui.IsItemDeactivatedAfterEdit() {
                    edit_history_push(&app.edit_history, ModifyVolumeAction{idx = ev.selected_idx, before = det.drag_before_volume, after = v})
                    mark_scene_dirty(app)
                }
            }
        }
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
