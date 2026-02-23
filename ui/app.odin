package ui

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:util"

LOG_RING_SIZE :: 64

FloatingPanel :: struct {
    title:        cstring,
    rect:         rl.Rectangle,
    min_size:     rl.Vector2,
    dragging:     bool,
    resizing:     bool,
    drag_offset:  rl.Vector2,
    visible:      bool,
    closeable:    bool,
    detachable:   bool,
    maximized:    bool,
    saved_rect:   rl.Rectangle,

    // Composable content renderer. Nil = empty body (chrome still draws).
    draw_content: proc(app: ^App, content: rl.Rectangle),
}

App :: struct {
    render_panel:  FloatingPanel,
    stats_panel:   FloatingPanel,
    log_panel:     FloatingPanel,

    render_tex:    rl.Texture2D,
    pixel_staging: []rl.Color,

    session:       ^rt.RenderSession,

    log_lines:     [LOG_RING_SIZE]string,
    log_count:     int,

    finished:      bool,
    elapsed_secs:  f64,
    render_start:  time.Time,
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
	if app == nil || layout == nil {
		return
	}
	panel_rect :: proc(r: util.RectF) -> rl.Rectangle {
		return rl.Rectangle{x = r.x, y = r.y, width = r.width, height = r.height}
	}
	app.render_panel.rect       = panel_rect(layout.render_panel.rect)
	app.render_panel.visible    = layout.render_panel.visible
	app.render_panel.maximized  = layout.render_panel.maximized
	app.render_panel.saved_rect = panel_rect(layout.render_panel.saved_rect)

	app.stats_panel.rect       = panel_rect(layout.stats_panel.rect)
	app.stats_panel.visible    = layout.stats_panel.visible
	app.stats_panel.maximized  = layout.stats_panel.maximized
	app.stats_panel.saved_rect = panel_rect(layout.stats_panel.saved_rect)

	app.log_panel.rect       = panel_rect(layout.log_panel.rect)
	app.log_panel.visible    = layout.log_panel.visible
	app.log_panel.maximized  = layout.log_panel.maximized
	app.log_panel.saved_rect = panel_rect(layout.log_panel.saved_rect)
}

// build_editor_layout_from_app allocates an EditorLayout and fills it from the current panel state. Caller must free the result.
build_editor_layout_from_app :: proc(app: ^App) -> ^util.EditorLayout {
	if app == nil {
		return nil
	}
	layout := new(util.EditorLayout)
	rect_from :: proc(r: rl.Rectangle) -> util.RectF {
		return util.RectF{x = r.x, y = r.y, width = r.width, height = r.height}
	}
	layout.render_panel = util.PanelState{
		rect       = rect_from(app.render_panel.rect),
		visible    = app.render_panel.visible,
		maximized  = app.render_panel.maximized,
		saved_rect = rect_from(app.render_panel.saved_rect),
	}
	layout.stats_panel = util.PanelState{
		rect       = rect_from(app.stats_panel.rect),
		visible    = app.stats_panel.visible,
		maximized  = app.stats_panel.maximized,
		saved_rect = rect_from(app.stats_panel.saved_rect),
	}
	layout.log_panel = util.PanelState{
		rect       = rect_from(app.log_panel.rect),
		visible    = app.log_panel.visible,
		maximized  = app.log_panel.maximized,
		saved_rect = rect_from(app.log_panel.saved_rect),
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
    WIN_H :: i32(720)

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
        render_panel = FloatingPanel{
            title        = "Render Preview",
            rect         = rl.Rectangle{10, 10, 820, 700},
            min_size     = rl.Vector2{200, 150},
            visible      = true,
            draw_content = draw_render_content,
        },
        stats_panel = FloatingPanel{
            title        = "Stats",
            rect         = rl.Rectangle{840, 10, 430, 220},
            min_size     = rl.Vector2{180, 140},
            visible      = true,
            draw_content = draw_stats_content,
        },
        log_panel = FloatingPanel{
            title        = "Log",
            rect         = rl.Rectangle{840, 240, 430, 470},
            min_size     = rl.Vector2{180, 100},
            visible      = true,
            closeable    = true,
            detachable   = true,
            draw_content = draw_log_content,
        },
        render_tex    = render_tex,
        pixel_staging = pixel_staging,
    }

    if initial_editor_layout != nil {
        apply_editor_layout(&app, initial_editor_layout)
    }

    g_app = &app
    rl.SetTraceLogCallback(cast(rl.TraceLogCallback)app_trace_log)

    app_push_log(&app, fmt.aprintf("Scene: %dx%d, %d spp", camera.image_width, camera.image_height, camera.samples_per_pixel))
    app_push_log(&app, fmt.aprintf("Threads: %d", num_threads))
    app_push_log(&app, strings.clone("Starting render..."))

    session := rt.start_render(camera, world, num_threads)
    app.session      = session
    app.render_start = time.now()

    frame := 0

    for !rl.WindowShouldClose() {
        frame += 1

        app.elapsed_secs = time.duration_seconds(time.diff(app.render_start, time.now()))

        mouse       := rl.GetMousePosition()
        lmb         := rl.IsMouseButtonDown(.LEFT)
        lmb_pressed := rl.IsMouseButtonPressed(.LEFT)

        panels := [3]^FloatingPanel{&app.render_panel, &app.stats_panel, &app.log_panel}

        sw := f32(rl.GetScreenWidth())
        sh := f32(rl.GetScreenHeight())
        for p in panels {
            update_panel(p, mouse, lmb, lmb_pressed)
            clamp_panel_to_screen(p, sw, sh)
        }

        if rl.IsKeyPressed(.L) {
            app.log_panel.visible = true
        }

        if frame % 4 == 0 {
            upload_render_texture(&app)
        }

        if !app.finished && rt.get_render_progress(session) >= 1.0 {
            rt.finish_render(session)
            app.finished = true
            upload_render_texture(&app)
            app_push_log(&app, fmt.aprintf("Done! (%.2fs)", app.elapsed_secs))
        }

        rl.BeginDrawing()
        rl.ClearBackground(rl.Color{20, 20, 30, 255})

        for p in panels {
            if p == &app.log_panel && p.maximized {
                draw_dim_overlay()
            }
            draw_panel(p, &app)
        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }

    // Early close: finish_render still runs and blocks until workers drain the tile queue (no abort).
    if !app.finished {
        rt.finish_render(session)
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
