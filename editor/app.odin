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

LOG_RING_SIZE :: 64

PANEL_ID_RENDER      :: "render_preview"
PANEL_ID_STATS       :: "stats"
PANEL_ID_LOG         :: "log"
PANEL_ID_SYSTEM_INFO :: "system_info"
PANEL_ID_EDIT_VIEW   :: "edit_view"
PANEL_ID_CAMERA        :: "camera"
PANEL_ID_OBJECT_PROPS  :: "object_props"
PANEL_ID_PREVIEW_PORT  :: "preview_port"

FloatingPanel :: struct {
    id:                 string,
    title:              cstring,
    rect:               rl.Rectangle,
    min_size:           rl.Vector2,
    dragging:           bool,
    resizing:           bool,
    drag_offset:        rl.Vector2,
    visible:            bool,
    closeable:          bool,
    detachable:         bool,
    maximized:          bool,
    saved_rect:         rl.Rectangle,
    dim_when_maximized: bool,
    style:              ^PanelStyle,

    // Composable content renderer. Nil = empty body (chrome still draws).
    draw_content:   proc(app: ^App, content: rl.Rectangle),

    // Input strategy. Called during the update phase after chrome interaction is resolved.
    // Nil = panel has no custom input handling.
    update_content: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool),
}

// PanelDesc is a builder struct for constructing a FloatingPanel via make_panel.
PanelDesc :: struct {
    id:                 string,
    title:              cstring,
    rect:               rl.Rectangle,
    min_size:           rl.Vector2,
    visible:            bool,
    closeable:          bool,
    detachable:         bool,
    dim_when_maximized: bool,
    style:              ^PanelStyle,
    draw_content:       proc(app: ^App, content: rl.Rectangle),
    update_content:     proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool),
}

// make_panel allocates a FloatingPanel from a PanelDesc. Caller must either transfer ownership via app_add_panel or free() the panel.
make_panel :: proc(desc: PanelDesc) -> ^FloatingPanel {
    p := new(FloatingPanel)
    p^ = FloatingPanel{
        id                 = desc.id,
        title              = desc.title,
        rect               = desc.rect,
        min_size           = desc.min_size,
        visible            = desc.visible,
        closeable          = desc.closeable,
        detachable         = desc.detachable,
        dim_when_maximized = desc.dim_when_maximized,
        style              = desc.style,
        draw_content       = desc.draw_content,
        update_content     = desc.update_content,
    }
    return p
}

// app_add_panel appends a heap-allocated panel to app.panels. App takes ownership.
app_add_panel :: proc(app: ^App, panel: ^FloatingPanel) {
    append(&app.panels, panel)
}

// app_find_panel returns the panel with the given id, or nil if not found.
app_find_panel :: proc(app: ^App, id: string) -> ^FloatingPanel {
    for p in app.panels {
        if p.id == id { return p }
    }
    return nil
}

// app_restart_render replaces the current world with new_world and starts a fresh render.
// No-op if the current render has not yet finished (finish_render must have been called).
app_restart_render :: proc(app: ^App, new_world: [dynamic]rt.Object) {
    if !app.finished { return }

    rt.free_session(app.r_session)
    app.r_session = nil

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
// Used by the edit view so it does not need to import raytrace.
app_restart_render_with_scene :: proc(app: ^App, scene_objects: []core.SceneSphere) {
    if !app.finished { return }

    rt.free_session(app.r_session)
    app.r_session = nil

    delete(app.r_world)
    app.r_world = rt.build_world_from_scene(scene_objects)

    app.finished     = false
    app.elapsed_secs = 0
    app.render_start = time.now()

    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    rt.init_camera(app.r_camera)
    app.r_session = rt.start_render_auto(app.r_camera, app.r_world, app.num_threads, app.prefer_gpu)
    app_push_log(app, fmt.aprintf("Re-rendering (%d objects)...", len(app.r_world)))
}

App :: struct {
    panels:        [dynamic]^FloatingPanel,
    dock_layout:   DockLayout,

    render_tex:    rl.Texture2D,
    pixel_staging: []rl.Color,

    r_session:     ^rt.RenderSession,

    // Kept separately so re-renders can reuse the same camera and replace the world.
    num_threads:   int,
    r_camera:      ^rt.Camera,
    r_world:       [dynamic]rt.Object,
    c_camera_params: core.CameraParams, // shared camera definition; applied to r_camera before each render

    // User's chosen render path (GPU vs CPU). Persists across scene changes and re-renders until toggled.
    prefer_gpu:    bool,

    // Render settings inputs (editable in render panel)
    r_height_input:     string,  // e.g., "600" (vertical resolution)
    r_samples_input:    string,  // e.g., "10"
    r_aspect_ratio:     int,     // 0=4:3, 1=16:9
    r_active_input:     int,     // 0=none, 1=height, 2=samples, 3=aspect dropdown
    r_render_btn_down:  bool,    // button pressed state

    // Track if render settings or scene have changed since last render
    r_render_pending:   bool,    // true when settings or scene changed

    log_lines:     [LOG_RING_SIZE]string,
    log_count:     int,

    finished:      bool,
    elapsed_secs:  f64,
    render_start:  time.Time,

    e_edit_view:    EditViewState,
    e_camera_panel: CameraPanelState,
    e_menu_bar:     MenuBarState,
    e_object_props: ObjectPropsPanelState,

    // Preview Port: rasterized view from render camera (app.c_camera_params)
    preview_port_tex: rl.RenderTexture2D,
    preview_port_w:   i32,
    preview_port_h:   i32,

    // SDF UI font (optional; fallback to default font if load fails)
    ui_font:       rl.Font,
    ui_font_shader: rl.Shader,
    use_sdf_font:   bool,

    // Input consumption: reset each frame, set by menu bar/modal first, prevents click bleed
    input_consumed: bool,

    // Set true by File → Exit to signal the main loop to terminate.
    should_exit: bool,

    // Command registry: registered once on startup
    commands: CommandRegistry,

    // Undo/redo history for scene mutations
    edit_history: EditHistory,

    // File modal (shared for Import, Save As, Preset Name)
    file_modal: FileModalState,

    // Current scene file path (empty until a file has been imported or saved-as)
    current_scene_path: string,

    // Named layout presets (built-ins + user-saved)
    layout_presets: [dynamic]persistence.LayoutPreset,
}

g_app: ^App = nil

// has_custom_ui_font returns true when a custom font (SDF or LoadFontEx) is loaded for UI text.
has_custom_ui_font :: proc(app: ^App) -> bool {
    return app != nil && app.ui_font.glyphCount > 0
}

// draw_ui_text draws text using the SDF font when available, else custom font (LoadFontEx), else default font.
draw_ui_text :: proc(app: ^App, text: cstring, x, y: i32, fontSize: i32, color: rl.Color) {
    if app == nil {
        rl.DrawText(text, x, y, fontSize, color)
        return
    }
    if app.use_sdf_font {
        draw_text_sdf(app.ui_font, app.ui_font_shader, text, rl.Vector2{f32(x), f32(y)}, f32(fontSize), 0, color)
        return
    }
    if has_custom_ui_font(app) {
        rl.DrawTextEx(app.ui_font, text, rl.Vector2{f32(x), f32(y)}, f32(fontSize), 0, color)
        return
    }
    rl.DrawText(text, x, y, fontSize, color)
}

// UITextSize is the result of measure_ui_text (width and height in pixels).
UITextSize :: struct { width, height: i32 }

// measure_ui_text returns width and height of text using the custom or default font.
measure_ui_text :: proc(app: ^App, text: cstring, fontSize: i32) -> UITextSize {
    if app != nil && has_custom_ui_font(app) {
        size := rl.MeasureTextEx(app.ui_font, text, f32(fontSize), 0)
        return UITextSize{i32(size.x), i32(size.y)}
    }
    return UITextSize{rl.MeasureText(text, fontSize), fontSize}
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

// apply_editor_layout sets each panel's rect, visible, maximized, and saved_rect from the loaded layout.
apply_editor_layout :: proc(app: ^App, layout: ^persistence.EditorLayout) {
    if app == nil || layout == nil { return }
    panel_rect :: proc(r: persistence.RectF) -> rl.Rectangle {
        return rl.Rectangle{x = r.x, y = r.y, width = r.width, height = r.height}
    }
    for p in app.panels {
        if state, ok := layout.panels[p.id]; ok {
            p.rect       = panel_rect(state.rect)
            p.visible    = state.visible
            p.maximized  = state.maximized
            p.saved_rect = panel_rect(state.saved_rect)
        }
    }
}

// build_editor_layout_from_app allocates an EditorLayout and fills it from the current panel state. Caller must free the result.
build_editor_layout_from_app :: proc(app: ^App) -> ^persistence.EditorLayout {
    if app == nil { return nil }
    layout := new(persistence.EditorLayout)
    layout.panels = make(map[string]persistence.PanelState)
    rect_from :: proc(r: rl.Rectangle) -> persistence.RectF {
        return persistence.RectF{x = r.x, y = r.y, width = r.width, height = r.height}
    }
    for p in app.panels {
        layout.panels[p.id] = persistence.PanelState{
            rect       = rect_from(p.rect),
            visible    = p.visible,
            maximized  = p.maximized,
            saved_rect = rect_from(p.saved_rect),
        }
    }
    return layout
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
    initial_editor_layout: ^persistence.EditorLayout = nil,
    config_save_path: string = "",
    initial_presets: []persistence.LayoutPreset = nil,
) {
    WIN_W :: i32(1280)
    WIN_H :: i32(1280)

    rl.SetTraceLogLevel(.WARNING)
    rl.InitWindow(WIN_W, WIN_H, "Ray Tracer — Live Preview")
    defer rl.CloseWindow()
    rl.SetWindowState(rl.ConfigFlags{rl.ConfigFlag.WINDOW_RESIZABLE})
    rl.SetWindowMinSize(640, 360)
    rl.SetTargetFPS(60)

    // Load UI font when SDF feature is enabled; otherwise use raylib default font
    ui_font: rl.Font
    ui_shader: rl.Shader
    sdf_ok := false
    when USE_SDF_FONT {
        rl.SetTraceLogLevel(.ALL)
        ui_font, ui_shader, sdf_ok = load_sdf_font("assets/fonts/Inter-Regular.ttf", "assets/shaders/sdf.fs", SDF_BASE_SIZE)
        if !sdf_ok {
            if font_ex, ex_ok := load_font_ex_fallback("assets/fonts/Inter-Regular.ttf", FONTEX_FALLBACK_SIZE); ex_ok {
                ui_font = font_ex
            }
        }
        rl.SetTraceLogLevel(.WARNING)
    }

    img := rl.GenImageColor(i32(r_camera.image_width), i32(r_camera.image_height), rl.BLACK)
    render_tex := rl.LoadTextureFromImage(img)
    rl.UnloadImage(img)
    defer rl.UnloadTexture(render_tex)

    pixel_staging := make([]rl.Color, r_camera.image_width * r_camera.image_height)
    defer delete(pixel_staging)

    app := App{
        render_tex          = render_tex,
        pixel_staging       = pixel_staging,
        use_sdf_font        = sdf_ok,
        ui_font             = ui_font,
        ui_font_shader      = ui_shader,
        r_height_input      = fmt.aprintf("%d", r_camera.image_height),
        r_samples_input     = fmt.aprintf("%d", r_camera.samples_per_pixel),
        r_aspect_ratio      = 1, // default to 16:9
        r_render_pending    = true, // initial render needed
    }
    when USE_SDF_FONT {
        if has_custom_ui_font(&app) {
            defer unload_ui_font(&app.ui_font, app.ui_font_shader, app.use_sdf_font)
        }
    }
    app.r_camera    = r_camera
    app.num_threads = num_threads
    app.prefer_gpu  = use_gpu
    app.e_menu_bar  = MenuBarState{open_menu_index = -1}
    app.layout_presets = make([dynamic]persistence.LayoutPreset)
    defer {
        for &p in app.layout_presets { delete(p.name); delete(p.layout.panels) }
        delete(app.layout_presets)
    }
    defer { if len(app.current_scene_path) > 0 { delete(app.current_scene_path) } }
    defer edit_history_free(&app.edit_history)
    register_all_commands(&app)
    // Load persisted presets (cloned so app owns them)
    for p in initial_presets {
        import_preset := persistence.LayoutPreset{
            name   = strings.clone(p.name),
            layout = persistence.EditorLayout{panels = make(map[string]persistence.PanelState)},
        }
        for k, v in p.layout.panels {
            import_preset.layout.panels[strings.clone(k)] = v
        }
        append(&app.layout_presets, import_preset)
    }
    rt.copy_camera_to_scene_params(&app.c_camera_params, r_camera)
    init_edit_view(&app.e_edit_view)
    // If a world was passed in (from a scene file), populate the edit view with it.
    // Otherwise the edit view keeps its 3 default spheres.
    if len(r_world) > 0 {
        converted := rt.convert_world_to_edit_spheres(r_world)
        LoadFromSceneSpheres(app.e_edit_view.scene_mgr, converted[:])
        delete(converted)
    }
    delete(r_world) // edit view is now the source of truth; free the raw rt.Object array
    // Build the startup world from the edit view (always).
    ExportToSceneSpheres(app.e_edit_view.scene_mgr, &app.e_edit_view.export_scratch)
    app.r_world = rt.build_world_from_scene(app.e_edit_view.export_scratch[:])
    app.e_object_props = ObjectPropsPanelState{prop_drag_idx = -1}
    defer rl.UnloadRenderTexture(app.e_edit_view.viewport_tex)
    defer { if app.preview_port_w > 0 { rl.UnloadRenderTexture(app.preview_port_tex) } }
    defer delete(app.e_edit_view.export_scratch)
    defer free_scene_manager(app.e_edit_view.scene_mgr)
    defer { rt.free_session(app.r_session) }
    defer delete(app.r_world)
    defer {
        for p in app.panels { free(p) }
        delete(app.panels)
        delete(app.r_height_input)
        delete(app.r_samples_input)
    }

    app_add_panel(&app, make_panel(PanelDesc{
        id             = PANEL_ID_RENDER,
        title          = "Render Preview",
        rect           = rl.Rectangle{10, 30, 820, 700},
        min_size       = rl.Vector2{260, 200},
        visible        = true,
        draw_content   = draw_render_content,
        update_content = update_render_content,
    }))
    app_add_panel(&app, make_panel(PanelDesc{
        id             = PANEL_ID_STATS,
        title          = "Stats",
        rect           = rl.Rectangle{840, 30, 430, 220},
        min_size       = rl.Vector2{180, 140},
        visible        = true,
        draw_content   = draw_stats_content,
        update_content = update_stats_content,
    }))
    app_add_panel(&app, make_panel(PanelDesc{
        id                 = PANEL_ID_LOG,
        title              = "Log",
        rect               = rl.Rectangle{840, 240, 430, 470},
        min_size           = rl.Vector2{180, 100},
        visible            = true,
        closeable          = true,
        detachable         = true,
        dim_when_maximized = true,
        draw_content       = draw_log_content,
    }))
    app_add_panel(&app, make_panel(PanelDesc{
        id           = PANEL_ID_SYSTEM_INFO,
        title        = "System Info",
        rect         = rl.Rectangle{840, 470, 430, 220},
        min_size     = rl.Vector2{180, 140},
        visible      = true,
        closeable    = true,
        detachable   = true,
        draw_content = draw_system_info_content,
    }))
    app_add_panel(&app, make_panel(PanelDesc{
        id             = PANEL_ID_EDIT_VIEW,
        title          = "Edit View",
        rect           = rl.Rectangle{10, 850, 820, 700},
        min_size       = rl.Vector2{300, 250},
        visible        = true,
        closeable      = true,
        detachable     = true,
        draw_content   = draw_edit_view_content,
        update_content = update_edit_view_content,
    }))
    app_add_panel(&app, make_panel(PanelDesc{
        id             = PANEL_ID_CAMERA,
        title          = "Camera",
        rect           = rl.Rectangle{840, 700, 250, 220},
        min_size       = rl.Vector2{200, 180},
        visible        = true,
        closeable      = true,
        detachable     = true,
        draw_content   = draw_camera_panel_content,
        update_content = update_camera_panel_content,
    }))
    app_add_panel(&app, make_panel(PanelDesc{
        id             = PANEL_ID_OBJECT_PROPS,
        title          = "Object Properties",
        rect           = rl.Rectangle{1100, 30, 260, 340},
        min_size       = rl.Vector2{240, 240},
        visible        = true,
        closeable      = true,
        detachable     = true,
        draw_content   = draw_object_props_content,
        update_content = update_object_props_content,
    }))
    app_add_panel(&app, make_panel(PanelDesc{
        id           = PANEL_ID_PREVIEW_PORT,
        title        = "Preview Port",
        rect         = rl.Rectangle{840, 920, 250, 180},
        min_size     = rl.Vector2{160, 120},
        visible      = true,
        closeable    = true,
        detachable   = true,
        draw_content = draw_preview_port_content,
    }))

    if initial_editor_layout != nil {
        apply_editor_layout(&app, initial_editor_layout)
    }
    layout_build_default(&app, &app.dock_layout)

    g_app = &app
    rl.SetTraceLogCallback(cast(rl.TraceLogCallback)app_trace_log)

    if app.use_sdf_font {
        app_push_log(&app, strings.clone("Font: SDF (Inter) loaded"))
    } else if has_custom_ui_font(&app) {
        app_push_log(&app, strings.clone("Font: Inter (LoadFontEx fallback)"))
    } else {
        app_push_log(&app, strings.clone("Font: default (SDF/Inter load failed)"))
    }

    app_push_log(&app, fmt.aprintf("Scene: %dx%d, %d spp", r_camera.image_width, r_camera.image_height, r_camera.samples_per_pixel))
    app_push_log(&app, fmt.aprintf("Threads: %d", num_threads))
    if use_gpu {
        app_push_log(&app, strings.clone("Starting render (GPU mode requested)..."))
    } else {
        app_push_log(&app, strings.clone("Starting render..."))
    }

    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    rt.init_camera(app.r_camera)
    app.r_session      = rt.start_render_auto(app.r_camera, app.r_world, app.num_threads, app.prefer_gpu)
    app.render_start = time.now()

    // Log the actual render mode after start_render_auto decides CPU vs GPU.
    if app.r_session.use_gpu {
        app_push_log(&app, strings.clone("[GPU] GPU rendering active"))
    }

    frame := 0

    for !rl.WindowShouldClose() && !app.should_exit {
        frame += 1

        app.elapsed_secs = time.duration_seconds(time.diff(app.render_start, time.now()))

        mouse       := rl.GetMousePosition()
        lmb         := rl.IsMouseButtonDown(.LEFT)
        lmb_pressed := rl.IsMouseButtonPressed(.LEFT)

        // ── Input phase (priority order) ──────────────────────────────────
        app.input_consumed = false

        // Priority 1: menu bar
        menu_bar_update(&app, &app.e_menu_bar, mouse, lmb_pressed)

        // Priority 2: file modal (blocks all other input when active)
        file_modal_update(&app)

        // Priority 3: keyboard shortcuts (only when not consumed by menu/modal)
        if !app.input_consumed {
            if rl.IsKeyPressed(.F5) { cmd_execute(&app, CMD_RENDER_RESTART) }
            if rl.IsKeyPressed(.L) {
                if log := app_find_panel(&app, PANEL_ID_LOG); log != nil { log.visible = true }
            }
            if rl.IsKeyPressed(.S) {
                if si := app_find_panel(&app, PANEL_ID_SYSTEM_INFO); si != nil { si.visible = true }
            }
            if rl.IsKeyPressed(.E) {
                if ev := app_find_panel(&app, PANEL_ID_EDIT_VIEW); ev != nil { ev.visible = true }
            }
            if rl.IsKeyPressed(.C) {
                if cam := app_find_panel(&app, PANEL_ID_CAMERA); cam != nil { cam.visible = true }
            }
            if rl.IsKeyPressed(.O) {
                if op := app_find_panel(&app, PANEL_ID_OBJECT_PROPS); op != nil { op.visible = true }
            }
            if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) {
                if rl.IsKeyPressed(.Z) {
                    if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) {
                        cmd_execute(&app, CMD_REDO)
                    } else {
                        cmd_execute(&app, CMD_UNDO)
                    }
                }
                if rl.IsKeyPressed(.Y) { cmd_execute(&app, CMD_REDO) }
            }
        }

        // GPU path: dispatch one more sample per frame until all samples done.
        if app.r_session.use_gpu {
            r := app.r_session.gpu_renderer
            if r != nil && !rt.gpu_renderer_done(r) {
                rt.gpu_renderer_dispatch(r)
            }
        }

        // ── Render texture upload ─────────────────────────────────────────
        if frame % 4 == 0 {
            if app.r_session.use_gpu {
                // Only readback while the renderer is alive (nil after finish_render).
                if app.r_session.gpu_renderer != nil {
                    out_bytes := transmute([][4]u8)(app.pixel_staging)
                    rt.gpu_renderer_readback(app.r_session.gpu_renderer, out_bytes)
                    rl.UpdateTexture(app.render_tex, raw_data(app.pixel_staging))
                }
            } else {
                upload_render_texture(&app)
            }
        }

        if !app.finished && rt.get_render_progress(app.r_session) >= 1.0 {
            if app.r_session.use_gpu {
                // Do a final readback before finish_render destroys the renderer.
                out_bytes := transmute([][4]u8)(app.pixel_staging)
                rt.gpu_renderer_readback(app.r_session.gpu_renderer, out_bytes)
                rl.UpdateTexture(app.render_tex, raw_data(app.pixel_staging))
            }
            rt.finish_render(app.r_session)
            app.finished = true
            if !app.r_session.use_gpu {
                upload_render_texture(&app)
            }
            app_push_log(&app, fmt.aprintf("Done! (%.2fs)", app.elapsed_secs))
        }

        // ── Draw phase ────────────────────────────────────────────────────
        rl.BeginDrawing()
        rl.ClearBackground(rl.Color{20, 20, 30, 255})

        // Pass effective lmb_pressed (blocked when modal or menu consumed input)
        effective_lmb_pressed := lmb_pressed && !app.input_consumed
        layout_update_and_draw(&app, &app.dock_layout, mouse, lmb, effective_lmb_pressed)
        menu_bar_draw(&app, &app.e_menu_bar)
        file_modal_draw(&app)

        rl.EndDrawing()

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
        config.editor = build_editor_layout_from_app(&app)
        // Snapshot user presets for saving
        if len(app.layout_presets) > 0 {
            config.presets = app.layout_presets[:]
        }
        if !persistence.save_config(config_save_path, config) {
            fmt.fprintf(os.stderr, "Failed to save config: %s\n", config_save_path)
        }
        if config.editor != nil {
            delete(config.editor.panels)
            free(config.editor)
        }
    }

    g_app = nil
    for i in 0..<LOG_RING_SIZE {
        if len(app.log_lines[i]) > 0 {
            delete(app.log_lines[i])
        }
    }
}
