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

    completed  := int(sync.atomic_load(&session.work_queue.completed))
    total      := session.work_queue.total_tiles
    progress   := f32(0)
    if total > 0 {
        progress = f32(completed) / f32(total) * 100.0
    }

    elapsed := app.elapsed_secs

    progress_color := CONTENT_TEXT_COLOR
    if app.finished {
        progress_color = DONE_COLOR
    }

    rl.DrawText(
        fmt.ctprintf("Tiles:    %d / %d  (%.1f%%)", completed, total, progress),
        x, y, fs, progress_color,
    )
    y += line_h

    rl.DrawText(
        fmt.ctprintf("Threads:  %d", session.num_threads),
        x, y, fs, CONTENT_TEXT_COLOR,
    )
    y += line_h

    mins := int(elapsed) / 60
    secs := elapsed - f64(mins*60)
    rl.DrawText(
        fmt.ctprintf("Elapsed:  %dm %.2fs", mins, secs),
        x, y, fs, CONTENT_TEXT_COLOR,
    )
    y += line_h

    rl.DrawText(
        fmt.ctprintf("Size:     %dx%d", session.camera.image_width, session.camera.image_height),
        x, y, fs, CONTENT_TEXT_COLOR,
    )
    y += line_h

    rl.DrawText(
        fmt.ctprintf("Samples:  %d/px", session.camera.samples_per_pixel),
        x, y, fs, CONTENT_TEXT_COLOR,
    )
    y += line_h

    status := app.finished ? cstring("Complete") : cstring("Rendering...")
    status_color := app.finished ? DONE_COLOR : ACCENT_COLOR
    rl.DrawText(status, x, y, fs, status_color)
    y += line_h

    if total > 0 {
        bar_y := y + 4
        bar_w := content.width - 20
        bar_h := f32(12)
        bar_rect := rl.Rectangle{content.x + 10, f32(bar_y), bar_w, bar_h}
        rl.DrawRectangleRec(bar_rect, rl.Color{60, 60, 80, 255})
        fill_w := bar_w * (f32(completed) / f32(total))
        fill_rect := rl.Rectangle{bar_rect.x, bar_rect.y, fill_w, bar_h}
        fill_color := app.finished ? DONE_COLOR : ACCENT_COLOR
        rl.DrawRectangleRec(fill_rect, fill_color)
        rl.DrawRectangleLinesEx(bar_rect, 1, BORDER_COLOR)
    }
}