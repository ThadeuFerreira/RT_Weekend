package ui

import "core:fmt"
import "core:sync"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

draw_stats_content :: proc(app: ^App, content: rl.Rectangle) {
    x := i32(content.x) + 10
    y := i32(content.y) + 8
    line_h := i32(20)
    fs := i32(14)

    session := app.session
    if session == nil { return }

    elapsed := app.elapsed_secs

    progress_color := CONTENT_TEXT_COLOR
    if app.finished {
        progress_color = DONE_COLOR
    }

    // Render mode — GPU or CPU.
    mode := session.use_gpu ? cstring("GPU") : cstring("CPU")
    draw_ui_text(app, fmt.ctprintf("Mode:     %s", mode), x, y, fs, CONTENT_TEXT_COLOR)
    y += line_h

    // Progress line: GPU shows sample count; CPU shows tile count.
    progress_frac := f32(0)
    if session.use_gpu {
        r := session.gpu_renderer
        cur, tot := 0, 0
        if r != nil { cur, tot = rt.gpu_renderer_get_samples(r) }
        if tot > 0 {
            progress_frac = f32(cur) / f32(tot)
        } else if app.finished {
            progress_frac = 1.0
        }
        pct := progress_frac * 100.0
        draw_ui_text(app,
            fmt.ctprintf("Samples:  %d / %d  (%.1f%%)", cur, tot, pct),
            x, y, fs, progress_color,
        )
    } else {
        completed := int(sync.atomic_load(&session.work_queue.completed))
        total     := session.work_queue.total_tiles
        if total > 0 {
            progress_frac = f32(completed) / f32(total)
        }
        pct := progress_frac * 100.0
        draw_ui_text(app,
            fmt.ctprintf("Tiles:    %d / %d  (%.1f%%)", completed, total, pct),
            x, y, fs, progress_color,
        )
    }
    y += line_h

    draw_ui_text(app,
        fmt.ctprintf("Threads:  %d", session.num_threads),
        x, y, fs, CONTENT_TEXT_COLOR,
    )
    y += line_h

    mins := int(elapsed) / 60
    secs := elapsed - f64(mins*60)
    draw_ui_text(app,
        fmt.ctprintf("Elapsed:  %dm %.2fs", mins, secs),
        x, y, fs, CONTENT_TEXT_COLOR,
    )
    y += line_h

    draw_ui_text(app,
        fmt.ctprintf("Size:     %dx%d", session.camera.image_width, session.camera.image_height),
        x, y, fs, CONTENT_TEXT_COLOR,
    )
    y += line_h

    draw_ui_text(app,
        fmt.ctprintf("Samples:  %d/px", session.camera.samples_per_pixel),
        x, y, fs, CONTENT_TEXT_COLOR,
    )
    y += line_h

    status := app.finished ? cstring("Complete") : cstring("Rendering...")
    status_color := app.finished ? DONE_COLOR : ACCENT_COLOR
    draw_ui_text(app, status, x, y, fs, status_color)
    y += line_h

    // Progress bar (works for both GPU and CPU paths via progress_frac).
    bar_y := y + 4
    bar_w := content.width - 20
    bar_h := f32(12)
    bar_rect := rl.Rectangle{content.x + 10, f32(bar_y), bar_w, bar_h}
    rl.DrawRectangleRec(bar_rect, rl.Color{60, 60, 80, 255})
    fill_w := bar_w * progress_frac
    fill_rect := rl.Rectangle{bar_rect.x, bar_rect.y, fill_w, bar_h}
    fill_color := app.finished ? DONE_COLOR : ACCENT_COLOR
    rl.DrawRectangleRec(fill_rect, fill_color)
    rl.DrawRectangleLinesEx(bar_rect, 1, BORDER_COLOR)
}