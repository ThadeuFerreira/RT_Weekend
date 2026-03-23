package editor

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"
import "RT_Weekend:persistence"
import "RT_Weekend:util"
import imgui "RT_Weekend:vendor/odin-imgui"

LOG_RING_SIZE :: 64

// Panel chrome constants — shared by all panel draw procs.
TITLE_BAR_HEIGHT   :: f32(24)
RESIZE_GRIP_SIZE   :: f32(14)

PANEL_BG_COLOR     :: rl.Color{35,  35,  50,  230}
TITLE_BG_COLOR     :: rl.Color{55,  55,  80,  255}
TITLE_TEXT_COLOR   :: rl.RAYWHITE
BORDER_COLOR       :: rl.Color{80,  80, 110,  255}
CONTENT_TEXT_COLOR :: rl.Color{200, 210, 220, 255}
ACCENT_COLOR       :: rl.Color{100, 180, 255, 255}
DONE_COLOR         :: rl.Color{100, 220, 120, 255}

PANEL_ID_RENDER         :: "render_preview"
PANEL_ID_STATS          :: "stats"
PANEL_ID_CONSOLE        :: "console"
PANEL_ID_SYSTEM_INFO    :: "system_info"
PANEL_ID_VIEWPORT       :: "viewport"
PANEL_ID_CAMERA         :: "camera"
PANEL_ID_DETAILS        :: "details"
PANEL_ID_CAMERA_PREVIEW :: "camera_preview"
PANEL_ID_TEXTURE_VIEW    :: "texture_view"
PANEL_ID_CONTENT_BROWSER :: "content_browser"
PANEL_ID_OUTLINER        :: "outliner"

// app_active_ground_texture returns the currently configured custom ground texture.
// Nil means "use default grey ground".
app_active_ground_texture :: proc(app: ^App) -> rt.Texture {
    if !app.has_custom_ground_texture { return core.ConstantTexture{color = {0.5, 0.5, 0.5}} }
    return app.custom_ground_texture
}

// app_set_ground_texture updates the custom ground texture used for world rebuilds.
// Pass nil to clear and use default grey ground.
app_set_ground_texture :: proc(app: ^App, ground_texture: rt.Texture) {
    if ground_texture == nil {
        app.has_custom_ground_texture = false
        return
    }
    app.custom_ground_texture = ground_texture
    app.has_custom_ground_texture = true
}

// app_build_world_from_scene rebuilds render objects from shared scene spheres, preserving
// any runtime image textures through app.image_texture_cache when available.
app_build_world_from_scene :: proc(app: ^App, scene_objects: []core.SceneSphere) -> [dynamic]rt.Object {
    return rt.build_world_from_scene(
        scene_objects,
        app_active_ground_texture(app),
        &app.image_texture_cache,
        app.include_ground_plane,
    )
}

// app_set_image_texture_cache_from_world refreshes the editor's runtime image cache from a world.
// The cache owns only the map container; Texture_Image pointers remain owned elsewhere.
app_set_image_texture_cache_from_world :: proc(app: ^App, world: [dynamic]rt.Object) {
    if app.image_texture_cache != nil {
        delete(app.image_texture_cache)
        app.image_texture_cache = nil
    }
    if len(world) == 0 { return }
    app.image_texture_cache = rt.collect_image_texture_cache(world[:])
}

// app_clear_image_texture_cache destroys all cached Texture_Image and frees the map.
// Call before loading a new scene so the previous scene's images are released.
app_clear_image_texture_cache :: proc(app: ^App) {
    if app.image_texture_cache == nil { return }
    for _, img in app.image_texture_cache {
        rt.texture_image_destroy(img)
        free(img)
    }
    delete(app.image_texture_cache)
    app.image_texture_cache = nil
}

// app_ensure_image_cached loads the image at path into app.image_texture_cache if not already present.
// Returns true when the image is ready (already cached or freshly loaded). Logs on failure.
app_ensure_image_cached :: proc(app: ^App, path: string) -> bool {
    if app.image_texture_cache == nil {
        app.image_texture_cache = make(map[string]^rt.Texture_Image)
    }
    if path in app.image_texture_cache { return true }
    img := new(rt.Texture_Image)
    img^ = rt.texture_image_init()
    if !rt.texture_image_load(img, path) {
        free(img)
        app_push_log(app, fmt.aprintf("Image load failed: %s", path))
        return false
    }
    app.image_texture_cache[path] = img
    return true
}

// app_append_volumes_to_world appends all volumes in app.e_volumes to world as ConstantMedium objects.
app_append_volumes_to_world :: proc(app: ^App, world: ^[dynamic]rt.Object) {
    for v in app.e_volumes {
        append(world, rt.build_volume_from_scene_volume(v))
    }
}

// app_restart_render replaces the current world with new_world and starts a fresh render.
// If a render is in progress, the restart is dropped so the main thread is not blocked
// (finish_render would join workers and freeze the UI). Request restart again after the
// current render completes, or close the window to stop the render.
app_restart_render :: proc(app: ^App, new_world: [dynamic]rt.Object) {
    if !app.finished && app.r_session != nil {
        return
    }

    rt.free_session(app.r_session)
    app.r_session = nil

    rt.free_world_volumes(app.r_world)
    delete(app.r_world)
    app.r_world = new_world

    app.finished     = false
    app.elapsed_secs = 0
    app.render_start = time.now()

    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    rt.init_camera(app.r_camera)
    app.r_session = rt.start_render_auto(app.r_camera, app.r_world, app.num_threads, app.prefer_gpu)
    app_push_log(app, fmt.aprintf("Re-rendering (%d objects)...", len(app.r_world)))
}

// app_restart_render_with_scene builds a raytrace world from shared scene objects and starts a fresh render.
// When ground_texture is nil, the ground plane uses default grey; otherwise the given texture (e.g. from an example scene).
// If a render is in progress, the restart is dropped (same as app_restart_render) to keep the UI responsive.
app_restart_render_with_scene :: proc(app: ^App, scene_objects: []core.SceneSphere, ground_texture: rt.Texture = nil) {
    if !app.finished && app.r_session != nil {
        return
    }
    if ground_texture != nil {
        app_set_ground_texture(app, ground_texture)
    }

    rt.free_session(app.r_session)
    app.r_session = nil

    rt.free_world_volumes(app.r_world)
    delete(app.r_world)
    app.r_world = app_build_world_from_scene(app, scene_objects)
    AppendQuadsToWorld(app.e_edit_view.scene_mgr, &app.r_world)
    app_append_volumes_to_world(app, &app.r_world)

    app.finished     = false
    app.elapsed_secs = 0
    app.render_start = time.now()

    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    rt.init_camera(app.r_camera)
    app.r_session = rt.start_render_auto(app.r_camera, app.r_world, app.num_threads, app.prefer_gpu)
    app_push_log(app, fmt.aprintf("Re-rendering (%d objects)...", len(app.r_world)))
}

App :: struct {
    e_panel_vis:   ImguiPanelVis,
    e_reset_layout: bool,

    render_tex:    rl.Texture2D,
    pixel_staging: []rl.Color,

    r_session:     ^rt.RenderSession,

    // Kept separately so re-renders can reuse the same camera and replace the world.
    num_threads:   int,
    r_camera:      ^rt.Camera,
    r_world:       [dynamic]rt.Object,
    e_volumes:     [dynamic]core.SceneVolume,
    custom_ground_texture: rt.Texture,
    has_custom_ground_texture: bool,
    include_ground_plane: bool,
    image_texture_cache: map[string]^rt.Texture_Image,
    c_camera_params: core.CameraParams, // shared camera definition; applied to r_camera before each render

    // User's chosen render path (GPU vs CPU). Persists across scene changes and re-renders until toggled.
    prefer_gpu:    bool,
    // Whether the render preview should upload intermediate framebuffer results while rendering.
    show_intermediate_render: bool,

    // Render settings inputs (editable in render panel)
    r_height_input:     string,  // e.g., "600" (vertical resolution)
    r_samples_input:    string,  // e.g., "10"
    r_aspect_ratio:     int,     // 0=4:3, 1=16:9
    r_active_input:     int,     // 0=none, 1=height, 2=samples, 3=aspect dropdown

    // Track if render settings or scene have changed since last render
    r_render_pending:   bool,    // true when settings or scene changed

    log_lines:     [LOG_RING_SIZE]string,
    log_count:     int,

    finished:      bool,
    elapsed_secs:  f64,
    render_start:  time.Time,

    e_edit_view:    EditViewState,
    e_camera_panel: CameraPanelState,
    e_details:      DetailsPanelState,
    e_outliner:     OutlinerPanelState,
    e_texture_view: TextureViewPanelState,
    e_content_browser: ContentBrowserState,

    // Camera Preview: rasterized view from render camera (app.c_camera_params)
    preview_port_tex: rl.RenderTexture2D,
    preview_port_w:   i32,
    preview_port_h:   i32,

    // Keyboard state: updated once per frame by keyboard_update; use instead of rl.IsKeyDown in features (nudge, etc.)
    keyboard: KeyboardState,

    // UI event logging: when true (and UI_EVENT_LOG_ENABLED is set at build time), click/drag/hover
    // events are written to the Console panel and stderr. Chrome trace output is controlled separately
    // by TRACE_CAPTURE_ENABLED + the benchmark capture toggle in the Render menu.
    // Default: false — enable via View menu or set directly in code for a debug session.
    ui_event_log_enabled: bool,

    // Input consumption: reset each frame, set by menu bar/modal first, prevents click bleed
    input_consumed: bool,

    // Set true by File → Exit to signal the main loop to terminate.
    should_exit: bool,

    // Command registry: registered once on startup
    commands: CommandRegistry,

    // Undo/redo history for scene mutations
    edit_history: EditHistory,

    // Clipboard for copy/paste (sphere only for now)
    e_clipboard_sphere: core.SceneSphere,
    e_has_clipboard:    bool,

    // File modal (shared for Import, Save As, Preset Name)
    file_modal: FileModalState,

    // Current scene file path (empty until a file has been imported or saved-as)
    current_scene_path: string,

    // Tracks whether the scene has unsaved changes (set on edit, cleared on save/load/new)
    e_scene_dirty: bool,

    // Save-changes modal (exit or import when dirty): Save / Don't Save / Cancel
    e_save_changes: SaveChangesModalState,

    // Confirm-load modal for example scene loading
    e_confirm_load: ConfirmLoadModalState,

    // Cached system info (queried once at startup; never changes at runtime)
    system_info: util.System_Info,
}

g_app: ^App = nil

// mark_scene_dirty sets the scene as having unsaved changes. Call after any edit (add/delete/modify sphere or camera).
// Also invalidates the Viewport cached BVH (viz_bvh_dirty) and viewport sphere cache so the 3D viewport
// shows up-to-date geometry and material/color after any change.
mark_scene_dirty :: proc(app: ^App) {
    if app != nil {
        app.e_scene_dirty = true
        if app.e_edit_view.initialized {
            app.e_edit_view.viz_bvh_dirty             = true
            app.e_edit_view.viewport_sphere_cache_dirty = true
        }
    }
}

upload_render_texture :: proc(app: ^App) {
    session := app.r_session
    if session == nil { return }

    buf    := &session.pixel_buffer
    camera := session.r_camera
    clamp  := rt.Interval{0.0, 0.999}

    for y in 0..<buf.height {
        for x in 0..<buf.width {
            raw := buf.pixels[y * buf.width + x] * camera.pixel_samples_scale

            r := rt.linear_to_gamma(raw[0])
            g := rt.linear_to_gamma(raw[1])
            b := rt.linear_to_gamma(raw[2])

            idx := y * buf.width + x
            app.pixel_staging[idx] = rl.Color{
                u8(rt.interval_clamp(clamp, r) * 255.0),
                u8(rt.interval_clamp(clamp, g) * 255.0),
                u8(rt.interval_clamp(clamp, b) * 255.0),
                255,
            }
        }
    }

    rl.UpdateTexture(app.render_tex, raw_data(app.pixel_staging))
}

// app_push_log appends a line to the log ring. Takes ownership of msg; callers must pass
// a heap-allocated string (e.g. fmt.aprintf, strings.concatenate, or strings.clone for literals).
// Do not use the string after the call.
app_push_log :: proc(app: ^App, msg: string) {
    if app == nil {
        delete(msg)
        return
    }
    idx := app.log_count % LOG_RING_SIZE
    if app.log_count >= LOG_RING_SIZE {
        delete(app.log_lines[idx])
    }
    app.log_lines[idx] = msg
    app.log_count += 1
}

apply_editor_view_config :: proc(ev: ^EditViewState, cfg: ^persistence.EditorViewConfig) {
    if ev == nil || cfg == nil { return }
    if cfg.camera_mode == "free_fly" {
        ev.camera_mode = .FreeFly
    } else if cfg.camera_mode == "orbit" {
        ev.camera_mode = .Orbit
    }
    if cfg.move_speed > 0 {
        ev.move_speed = cfg.move_speed
    }
    if cfg.speed_factor > 0 {
        ev.speed_factor = cfg.speed_factor
    }
    ev.lock_axis_x = cfg.lock_axis_x
    ev.lock_axis_y = cfg.lock_axis_y
    ev.lock_axis_z = cfg.lock_axis_z
    ev.grid_visible = cfg.grid_visible
    if cfg.grid_density > 0 {
        ev.grid_density = cfg.grid_density
    }
}

build_editor_view_config_from_app :: proc(ev: ^EditViewState) -> ^persistence.EditorViewConfig {
    if ev == nil { return nil }
    camera_mode := "orbit"
    if ev.camera_mode == .FreeFly { camera_mode = "free_fly" }
    cfg := new(persistence.EditorViewConfig)
    cfg^ = persistence.EditorViewConfig{
        camera_mode  = camera_mode,
        move_speed   = ev.move_speed,
        speed_factor = ev.speed_factor,
        lock_axis_x  = ev.lock_axis_x,
        lock_axis_y  = ev.lock_axis_y,
        lock_axis_z  = ev.lock_axis_z,
        grid_visible = ev.grid_visible,
        grid_density = ev.grid_density,
    }
    return cfg
}

app_trace_log :: proc "c" (logLevel: rl.TraceLogLevel, text: cstring, args: ^rawptr) {
    context = runtime.default_context()
    if g_app == nil { return }
    prefix: string
    #partial switch logLevel {
    case .INFO:    prefix = "[INFO] "
    case .WARNING: prefix = "[WARN] "
    case .ERROR:   prefix = "[ERR]  "
    case .DEBUG:   prefix = "[DBG]  "
    case: prefix = "       "
    }
    app_push_log(g_app, strings.concatenate({prefix, string(text)}))
}

run_app :: proc(
    r_camera: ^rt.Camera,
    r_world: [dynamic]rt.Object,
    num_threads: int,
    use_gpu: bool = false,
    initial_editor_view: ^persistence.EditorViewConfig = nil,
    config_save_path: string = "",
    initial_volumes: [dynamic]core.SceneVolume = nil,
) {
    WIN_W :: i32(1280)
    WIN_H :: i32(1280)

    rl.SetTraceLogLevel(.WARNING)
    rl.SetConfigFlags(rl.ConfigFlags{
        rl.ConfigFlag.WINDOW_RESIZABLE,
        rl.ConfigFlag.WINDOW_HIGHDPI,
    })
    rl.InitWindow(WIN_W, WIN_H, "Ray Tracer — Live Preview")
    defer rl.CloseWindow()
    rl.SetWindowMinSize(640, 360)
    rl.SetTargetFPS(60)

    // Dear ImGui — must be initialised after the OpenGL context is live.
    imgui_rl_setup()
    defer imgui_rl_shutdown()

    img := rl.GenImageColor(i32(r_camera.image_width), i32(r_camera.image_height), rl.BLACK)
    render_tex := rl.LoadTextureFromImage(img)
    rl.UnloadImage(img)
    defer rl.UnloadTexture(render_tex)

    pixel_staging := make([]rl.Color, r_camera.image_width * r_camera.image_height)

    app := App{
        render_tex          = render_tex,
        pixel_staging       = pixel_staging,
        include_ground_plane = true,
        show_intermediate_render = true,
        r_height_input      = fmt.aprintf("%d", r_camera.image_height),
        r_samples_input     = fmt.aprintf("%d", r_camera.samples_per_pixel),
        r_aspect_ratio      = 1, // default to 16:9
        r_render_pending    = true, // initial render needed
    }
    app.r_camera    = r_camera
    app.num_threads = num_threads
    app.prefer_gpu  = use_gpu
    app.system_info = util.get_system_info()
    defer delete(app.pixel_staging)
    defer { if len(app.current_scene_path) > 0 { delete(app.current_scene_path) } }
    defer edit_history_free(&app.edit_history)
    register_all_commands(&app)
    rt.copy_camera_to_scene_params(&app.c_camera_params, r_camera)
	// Startup default (no loaded world): editor uses its built-in 3 spheres.
	// Ensure they are visible by default with a white miss/background color.
	if len(r_world) == 0 {
		app.c_camera_params.background = [3]f32{1, 1, 1}
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
	}
    app_set_image_texture_cache_from_world(&app, r_world)
    init_edit_view(&app.e_edit_view)
    // If a world was passed in (from a scene file), populate the edit view with it.
    // Otherwise the edit view keeps its 3 default spheres.
    if len(r_world) > 0 {
        LoadFromWorld(app.e_edit_view.scene_mgr, r_world[:])
    }
    align_editor_camera_to_render(&app.e_edit_view, app.c_camera_params, true)
    if initial_editor_view != nil {
        apply_editor_view_config(&app.e_edit_view, initial_editor_view)
    }
    rt.free_world_volumes(r_world)
    delete(r_world) // edit view is now the source of truth; free the raw rt.Object array
    app.e_volumes = make([dynamic]core.SceneVolume)
    if initial_volumes != nil {
        for v in initial_volumes { append(&app.e_volumes, v) }
        delete(initial_volumes)
    }
    // Build the startup world from the edit view (always): spheres + quads + volumes.
    ExportToSceneSpheres(app.e_edit_view.scene_mgr, &app.e_edit_view.export_scratch)
    app.r_world = app_build_world_from_scene(&app, app.e_edit_view.export_scratch[:])
    AppendQuadsToWorld(app.e_edit_view.scene_mgr, &app.r_world)
    app_append_volumes_to_world(&app, &app.r_world)
    app.e_details  = DetailsPanelState{prop_drag_idx = -1}
    app.e_camera_panel  = CameraPanelState{drag_idx = -1}
    app.e_content_browser = ContentBrowserState{selected_idx = -1, scan_requested = true}
    defer rl.UnloadRenderTexture(app.e_edit_view.viewport_tex)
    defer { if app.preview_port_w > 0 { rl.UnloadRenderTexture(app.preview_port_tex) } }
    defer {
        if app.e_texture_view.valid { rl.UnloadTexture(app.e_texture_view.preview_tex) }
        delete(app.e_texture_view.last_sig)
    }
    defer content_browser_free_state(&app.e_content_browser)
    defer delete(app.e_edit_view.export_scratch)
    defer {
        for i in 0..<len(app.e_edit_view.viewport_sphere_cache) {
            free_viewport_sphere_cache_entry(&app.e_edit_view.viewport_sphere_cache[i])
        }
        delete(app.e_edit_view.viewport_sphere_cache)
    }
    defer free_scene_manager(app.e_edit_view.scene_mgr)
    defer {
        if app.e_edit_view.viz_bvh_root != nil {
            rt.free_bvh(app.e_edit_view.viz_bvh_root)
            app.e_edit_view.viz_bvh_root = nil
        }
    }
    defer { rt.free_session(app.r_session) }
    defer { rt.free_world_volumes(app.r_world); delete(app.r_world); delete(app.e_volumes) }
    defer { if app.image_texture_cache != nil { delete(app.image_texture_cache) } }
    defer {
        delete(app.r_height_input)
        delete(app.r_samples_input)
    }

    // Panel visibility — all open by default; ImGui persists layout via imgui.ini.
    app.e_panel_vis = ImguiPanelVis{
        render          = true,
        stats           = true,
        console         = true,
        system_info     = true,
        viewport        = true,
        camera          = true,
        details         = true,
        camera_preview  = true,
        texture_view    = true,
        content_browser = true,
        outliner        = true,
    }

    app.e_reset_layout = !os.exists("imgui.ini")

    g_app = &app
    rl.SetTraceLogCallback(cast(rl.TraceLogCallback)app_trace_log)

    app_push_log(&app, fmt.aprintf("Scene: %dx%d, %d spp", r_camera.image_width, r_camera.image_height, r_camera.samples_per_pixel))
    app_push_log(&app, fmt.aprintf("Threads: %d", num_threads))
    if use_gpu {
        app_push_log(&app, strings.clone("Starting render (GPU mode requested)..."))
    } else {
        app_push_log(&app, strings.clone("Starting render..."))
    }

    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    rt.init_camera(app.r_camera)
    util.trace_register_thread(0, "MainThread")
    // In debug builds, auto-start trace capture so UI events are recorded from the first frame
    // without requiring manual Render → Start Benchmark. Auto-saved on exit below.
    when UI_EVENT_LOG_ENABLED {
        app.ui_event_log_enabled = true
        cmd_action_benchmark_start(&app)
    }
    app.r_session      = rt.start_render_auto(app.r_camera, app.r_world, app.num_threads, app.prefer_gpu)
    app.render_start = time.now()

    // Log the actual render mode after start_render_auto decides CPU vs GPU.
    if app.r_session.use_gpu {
        app_push_log(&app, strings.clone("[GPU] GPU rendering active"))
    }

    frame := 0

    for !rl.WindowShouldClose() && !app.should_exit {
        frame_scope := util.trace_scope_begin("Frame", "game")
        frame += 1

        if !app.finished {
            app.elapsed_secs = time.duration_seconds(time.diff(app.render_start, time.now()))
        }

        // ── Input phase (priority order) ──────────────────────────────────
        keyboard_update(&app.keyboard)
        app.input_consumed = false

        // Note: Modals are now handled by ImGui in imgui_draw_all_panels().
        // Keyboard shortcuts stay blocked whenever ImGui wants keyboard focus.
        if !app.input_consumed && !imgui_rl_want_capture_keyboard() {
            ctrl_held  := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
            shift_held := rl.IsKeyDown(.LEFT_SHIFT)   || rl.IsKeyDown(.RIGHT_SHIFT)

            if !ctrl_held {
                if rl.IsKeyPressed(.F5) { cmd_execute(&app, CMD_RENDER_RESTART) }
                if rl.IsKeyPressed(.L) { app.e_panel_vis.console = true }
                if rl.IsKeyPressed(.S) { app.e_panel_vis.system_info = true }
                if rl.IsKeyPressed(.E) { app.e_panel_vis.viewport = true }
                if rl.IsKeyPressed(.C) { app.e_panel_vis.camera = true }
                if rl.IsKeyPressed(.O) { app.e_panel_vis.details = true }
                if rl.IsKeyPressed(.T) { app.e_panel_vis.texture_view = true }
                if rl.IsKeyPressed(.B) {
                    app.e_panel_vis.content_browser = true
                    app.e_content_browser.scan_requested = true
                }
            }

            if ctrl_held {
                if rl.IsKeyPressed(.Z) {
                    if shift_held { cmd_execute(&app, CMD_REDO) } else { cmd_execute(&app, CMD_UNDO) }
                }
                if rl.IsKeyPressed(.Y) { cmd_execute(&app, CMD_REDO) }
                if rl.IsKeyPressed(.C) { cmd_execute(&app, CMD_EDIT_COPY) }
                if rl.IsKeyPressed(.V) { cmd_execute(&app, CMD_EDIT_PASTE) }
                if rl.IsKeyPressed(.D) { cmd_execute(&app, CMD_EDIT_DUPLICATE) }
            }
        }

        // ── Backend tick: advance one unit of rendering work per frame ──
        if app.r_session.backend != nil && !rt.backend_done(app.r_session.backend) {
            tick_scope := util.trace_scope_begin("Backend.Tick", "render")
            defer util.trace_scope_end(tick_scope)
            rt.backend_tick(app.r_session.backend)
        }

        // ── Render texture upload ─────────────────────────────────────────
        if app.show_intermediate_render && frame % 4 == 0 {
            if app.r_session.backend != nil {
                out_bytes := transmute([][4]u8)(app.pixel_staging)
                rt.backend_readback(app.r_session.backend, out_bytes)
                rl.UpdateTexture(app.render_tex, raw_data(app.pixel_staging))
            }
        }

        if !app.finished && rt.get_render_progress(app.r_session) >= 1.0 {
            continuous_restart := false
            b := app.r_session.backend
            if b != nil && b.mode == .Continuous {
                out_bytes := transmute([][4]u8)(app.pixel_staging)
                rt.backend_final_readback(b, out_bytes)
                rl.UpdateTexture(app.render_tex, raw_data(app.pixel_staging))
                rt.backend_reset(b)
                continuous_restart = true
            }
            if !continuous_restart {
                // Final readback before finishing (GPU needs this for last sample).
                if b != nil {
                    out_bytes := transmute([][4]u8)(app.pixel_staging)
                    rt.backend_final_readback(b, out_bytes)
                    rl.UpdateTexture(app.render_tex, raw_data(app.pixel_staging))
                }
                rt.finish_render(app.r_session)
                app.elapsed_secs = time.duration_seconds(time.diff(app.render_start, time.now()))
                app.finished = true
                // CPU backend: do a final readback after finish (threads joined, buffer complete).
                if b != nil && b.kind == .CPU {
                    out_bytes := transmute([][4]u8)(app.pixel_staging)
                    rt.backend_readback(b, out_bytes)
                    rl.UpdateTexture(app.render_tex, raw_data(app.pixel_staging))
                }
                app_push_log(&app, fmt.aprintf("Done! (%.2fs)", app.elapsed_secs))
            }
        }

        // ── Draw phase ────────────────────────────────────────────────────
        rl.BeginDrawing()
        rl.ClearBackground(rl.Color{20, 20, 30, 255})

        // Off-screen textures (viewport, camera preview) are rendered inside their
        // respective panel procs — after imgui.GetContentRegionAvail() — so the
        // texture size always matches the panel size that frame (no stretch on resize).

        // Dear ImGui frame: DockSpace + menu bar + all panel stubs.
        imgui_rl_new_frame()
        imgui_draw_all_panels(&app)
        imgui_rl_render()

        rl.EndDrawing()

        util.trace_scope_end(frame_scope)
        free_all(context.temp_allocator)
    }

    // Early close: finish_render still runs and blocks until workers drain the tile queue (no abort).
    if !app.finished {
        rt.finish_render(app.r_session)
    }

    if len(config_save_path) > 0 {
        config := persistence.RenderConfig{
            width             = r_camera.image_width,
            height            = r_camera.image_height,
            samples_per_pixel = r_camera.samples_per_pixel,
        }
        config.editor_view = build_editor_view_config_from_app(&app.e_edit_view) // panel layout is persisted by ImGui via imgui.ini
        if !persistence.save_config(config_save_path, config) {
            fmt.fprintf(os.stderr, "Failed to save config: %s\n", config_save_path)
        }
        if config.editor_view != nil {
            free(config.editor_view)
        }
    }

    // Auto-save any in-progress trace capture in debug builds (started automatically at launch).
    // If the user already stopped capture manually via the menu, this is a no-op (stop_capture
    // returns false when not capturing).
    when UI_EVENT_LOG_ENABLED {
        cmd_action_benchmark_stop(&app)
    }

    g_app = nil
    for i in 0..<LOG_RING_SIZE {
        if len(app.log_lines[i]) > 0 {
            delete(app.log_lines[i])
        }
    }
}
