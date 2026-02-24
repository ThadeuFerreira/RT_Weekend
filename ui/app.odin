package ui

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:scene"
import "RT_Weekend:util"

LOG_RING_SIZE :: 64

PANEL_ID_RENDER      :: "render_preview"
PANEL_ID_STATS       :: "stats"
PANEL_ID_LOG         :: "log"
PANEL_ID_SYSTEM_INFO :: "system_info"
PANEL_ID_EDIT_VIEW   :: "edit_view"
PANEL_ID_CAMERA      :: "camera"

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

    rt.free_session(app.session)
    app.session = nil

    delete(app.world)
    app.world = new_world

    app.finished     = false
    app.elapsed_secs = 0
    app.render_start = time.now()

    rt.apply_scene_camera(app.camera, &app.camera_params)
    rt.init_camera(app.camera)
    app.session = rt.start_render(app.camera, app.world, app.num_threads)
    app_push_log(app, fmt.aprintf("Re-rendering (%d objects)...", len(app.world)))
}

// app_restart_render_with_scene builds a raytrace world from shared scene objects and starts a fresh render.
// Used by the edit view so it does not need to import raytrace.
app_restart_render_with_scene :: proc(app: ^App, scene_objects: []scene.SceneSphere) {
    if !app.finished { return }

    rt.free_session(app.session)
    app.session = nil

    delete(app.world)
    app.world = rt.build_world_from_scene(scene_objects)

    app.finished     = false
    app.elapsed_secs = 0
    app.render_start = time.now()

    rt.apply_scene_camera(app.camera, &app.camera_params)
    rt.init_camera(app.camera)
    app.session = rt.start_render(app.camera, app.world, app.num_threads)
    app_push_log(app, fmt.aprintf("Re-rendering (%d objects)...", len(app.world)))
}

App :: struct {
    panels:        [dynamic]^FloatingPanel,

    render_tex:    rl.Texture2D,
    pixel_staging: []rl.Color,

    session:       ^rt.RenderSession,

    // Kept separately so re-renders can reuse the same camera and replace the world.
    num_threads:   int,
    camera:        ^rt.Camera,
    world:         [dynamic]rt.Object,
    camera_params: scene.CameraParams, // shared camera definition; applied to camera before each render

    log_lines:     [LOG_RING_SIZE]string,
    log_count:     int,

    finished:      bool,
    elapsed_secs:  f64,
    render_start:  time.Time,

    edit_view:      EditViewState,
    camera_panel:   CameraPanelState,
    menu_bar:       MenuBarState,
}

g_app: ^App = nil

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
apply_editor_layout :: proc(app: ^App, layout: ^util.EditorLayout) {
    if app == nil || layout == nil { return }
    panel_rect :: proc(r: util.RectF) -> rl.Rectangle {
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
build_editor_layout_from_app :: proc(app: ^App) -> ^util.EditorLayout {
    if app == nil { return nil }
    layout := new(util.EditorLayout)
    layout.panels = make(map[string]util.PanelState)
    rect_from :: proc(r: rl.Rectangle) -> util.RectF {
        return util.RectF{x = r.x, y = r.y, width = r.width, height = r.height}
    }
    for p in app.panels {
        layout.panels[p.id] = util.PanelState{
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
    camera: ^rt.Camera,
    world: [dynamic]rt.Object,
    num_threads: int,
    initial_editor_layout: ^util.EditorLayout = nil,
    config_save_path: string = "",
) {
    WIN_W :: i32(1280)
    WIN_H :: i32(1280)

    rl.SetTraceLogLevel(.WARNING)
    rl.InitWindow(WIN_W, WIN_H, "Ray Tracer — Live Preview")
    defer rl.CloseWindow()
    rl.SetWindowState(rl.ConfigFlags{rl.ConfigFlag.WINDOW_RESIZABLE})
    rl.SetWindowMinSize(640, 360)
    rl.SetTargetFPS(60)

    img := rl.GenImageColor(i32(camera.image_width), i32(camera.image_height), rl.BLACK)
    render_tex := rl.LoadTextureFromImage(img)
    rl.UnloadImage(img)
    defer rl.UnloadTexture(render_tex)

    pixel_staging := make([]rl.Color, camera.image_width * camera.image_height)
    defer delete(pixel_staging)

    app := App{
        render_tex    = render_tex,
        pixel_staging = pixel_staging,
    }
    app.camera      = camera
    app.world       = world
    app.num_threads = num_threads
    app.menu_bar    = MenuBarState{open_menu_index = -1}
    rt.copy_camera_to_scene_params(&app.camera_params, camera)
    init_edit_view(&app.edit_view)
    defer rl.UnloadRenderTexture(app.edit_view.viewport_tex)
    defer delete(app.edit_view.objects)
    defer { rt.free_session(app.session) }
    defer delete(app.world)
    defer {
        for p in app.panels { free(p) }
        delete(app.panels)
    }

    app_add_panel(&app, make_panel(PanelDesc{
        id           = PANEL_ID_RENDER,
        title        = "Render Preview",
        rect         = rl.Rectangle{10, 30, 820, 700},
        min_size     = rl.Vector2{200, 150},
        visible      = true,
        draw_content = draw_render_content,
    }))
    app_add_panel(&app, make_panel(PanelDesc{
        id           = PANEL_ID_STATS,
        title        = "Stats",
        rect         = rl.Rectangle{840, 30, 430, 220},
        min_size     = rl.Vector2{180, 140},
        visible      = true,
        draw_content = draw_stats_content,
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

    if initial_editor_layout != nil {
        apply_editor_layout(&app, initial_editor_layout)
    }

    g_app = &app
    rl.SetTraceLogCallback(cast(rl.TraceLogCallback)app_trace_log)

    app_push_log(&app, fmt.aprintf("Scene: %dx%d, %d spp", camera.image_width, camera.image_height, camera.samples_per_pixel))
    app_push_log(&app, fmt.aprintf("Threads: %d", num_threads))
    app_push_log(&app, strings.clone("Starting render..."))

    rt.apply_scene_camera(app.camera, &app.camera_params)
    rt.init_camera(app.camera)
    app.session      = rt.start_render(app.camera, app.world, app.num_threads)
    app.render_start = time.now()

    frame := 0

    for !rl.WindowShouldClose() {
        frame += 1

        app.elapsed_secs = time.duration_seconds(time.diff(app.render_start, time.now()))

        mouse       := rl.GetMousePosition()
        lmb         := rl.IsMouseButtonDown(.LEFT)
        lmb_pressed := rl.IsMouseButtonPressed(.LEFT)

        sw := f32(rl.GetScreenWidth())
        sh := f32(rl.GetScreenHeight())
        menu_bar_update(&app, &app.menu_bar, mouse, lmb_pressed)
        for p in app.panels {
            update_panel(p, mouse, lmb, lmb_pressed)
            clamp_panel_to_screen(p, sw, sh)
            if p.update_content != nil && p.visible {
                content_rect := rl.Rectangle{
                    p.rect.x,
                    p.rect.y + TITLE_BAR_HEIGHT,
                    p.rect.width,
                    p.rect.height - TITLE_BAR_HEIGHT,
                }
                p.update_content(&app, content_rect, mouse, lmb, lmb_pressed)
            }
        }

        if rl.IsKeyPressed(.L) {
            if log := app_find_panel(&app, PANEL_ID_LOG); log != nil {
                log.visible = true
            }
        }
        if rl.IsKeyPressed(.S) {
            if si := app_find_panel(&app, PANEL_ID_SYSTEM_INFO); si != nil {
                si.visible = true
            }
        }
        if rl.IsKeyPressed(.E) {
            if ev := app_find_panel(&app, PANEL_ID_EDIT_VIEW); ev != nil {
                ev.visible = true
            }
        }
        if rl.IsKeyPressed(.C) {
            if cam := app_find_panel(&app, PANEL_ID_CAMERA); cam != nil {
                cam.visible = true
            }
        }

        if frame % 4 == 0 {
            upload_render_texture(&app)
        }

        if !app.finished && rt.get_render_progress(app.session) >= 1.0 {
            rt.finish_render(app.session)
            app.finished = true
            upload_render_texture(&app)
            app_push_log(&app, fmt.aprintf("Done! (%.2fs)", app.elapsed_secs))
        }

        rl.BeginDrawing()
        rl.ClearBackground(rl.Color{20, 20, 30, 255})

        for p in app.panels {
            if p.dim_when_maximized && p.maximized { draw_dim_overlay() }
            draw_panel(p, &app)
        }
        menu_bar_draw(&app, &app.menu_bar)

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }

    // Early close: finish_render still runs and blocks until workers drain the tile queue (no abort).
    if !app.finished {
        rt.finish_render(app.session)
    }

    if len(config_save_path) > 0 {
        config := util.RenderConfig{
            width             = camera.image_width,
            height            = camera.image_height,
            samples_per_pixel = camera.samples_per_pixel,
        }
        config.editor = build_editor_layout_from_app(&app)
        if !util.save_config(config_save_path, config) {
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
