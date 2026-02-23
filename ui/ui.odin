package ui

import "core:fmt"
import "core:sync"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

TITLE_BAR_HEIGHT  :: f32(24)
RESIZE_GRIP_SIZE  :: f32(14)

PANEL_BG_COLOR    :: rl.Color{35,  35,  50,  230}
TITLE_BG_COLOR    :: rl.Color{55,  55,  80,  255}
TITLE_TEXT_COLOR  :: rl.RAYWHITE
BORDER_COLOR      :: rl.Color{80,  80, 110,  255}
CONTENT_TEXT_COLOR :: rl.Color{200, 210, 220, 255}
ACCENT_COLOR      :: rl.Color{100, 180, 255, 255}
DONE_COLOR        :: rl.Color{100, 220, 120, 255}

update_panel :: proc(panel: ^FloatingPanel, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
    if !panel.visible { return }

    title_rect := rl.Rectangle{
        panel.rect.x,
        panel.rect.y,
        panel.rect.width,
        TITLE_BAR_HEIGHT,
    }
    grip_rect := rl.Rectangle{
        panel.rect.x + panel.rect.width  - RESIZE_GRIP_SIZE,
        panel.rect.y + panel.rect.height - RESIZE_GRIP_SIZE,
        RESIZE_GRIP_SIZE,
        RESIZE_GRIP_SIZE,
    }

    close_rect  := rl.Rectangle{ panel.rect.x + panel.rect.width - 22, panel.rect.y + 4, 16, 16 }
    detach_rect := rl.Rectangle{ panel.rect.x + panel.rect.width - 42, panel.rect.y + 4, 16, 16 }

    if lmb_pressed {
        if panel.closeable && rl.CheckCollisionPointRec(mouse, close_rect) {
            panel.visible = false
            return
        }
        if panel.detachable && rl.CheckCollisionPointRec(mouse, detach_rect) {
            if panel.maximized {
                panel.rect      = panel.saved_rect
                panel.maximized = false
            } else {
                panel.saved_rect = panel.rect
                sw := f32(rl.GetScreenWidth())
                sh := f32(rl.GetScreenHeight())
                mw := sw * 0.85
                mh := sh * 0.85
                panel.rect      = rl.Rectangle{ (sw-mw)*0.5, (sh-mh)*0.5, mw, mh }
                panel.maximized = true
            }
            return
        }
        if !panel.maximized {
            if rl.CheckCollisionPointRec(mouse, grip_rect) {
                panel.resizing = true
            } else if rl.CheckCollisionPointRec(mouse, title_rect) {
                panel.dragging = true
                panel.drag_offset = rl.Vector2{
                    mouse.x - panel.rect.x,
                    mouse.y - panel.rect.y,
                }
            }
        }
    }

    if !lmb {
        panel.dragging = false
        panel.resizing = false
    }

    if panel.dragging {
        panel.rect.x = mouse.x - panel.drag_offset.x
        panel.rect.y = mouse.y - panel.drag_offset.y
    }

    if panel.resizing {
        new_w := mouse.x - panel.rect.x
        new_h := mouse.y - panel.rect.y
        panel.rect.width  = max(new_w, panel.min_size.x)
        panel.rect.height = max(new_h, panel.min_size.y)
    }
}

draw_panel_chrome :: proc(panel: FloatingPanel) -> rl.Rectangle {
    if !panel.visible {
        return rl.Rectangle{}
    }

    rl.DrawRectangleRec(panel.rect, PANEL_BG_COLOR)
    rl.DrawRectangleLinesEx(panel.rect, 1, BORDER_COLOR)

    title_rect := rl.Rectangle{panel.rect.x, panel.rect.y, panel.rect.width, TITLE_BAR_HEIGHT}
    rl.DrawRectangleRec(title_rect, TITLE_BG_COLOR)
    rl.DrawText(panel.title, i32(panel.rect.x) + 6, i32(panel.rect.y) + 5, 14, TITLE_TEXT_COLOR)

    mouse := rl.GetMousePosition()

    // Close button [X] — rightmost
    if panel.closeable {
        close_rect  := rl.Rectangle{ panel.rect.x + panel.rect.width - 22, panel.rect.y + 4, 16, 16 }
        close_hover := rl.CheckCollisionPointRec(mouse, close_rect)
        close_color := close_hover ? rl.RED : TITLE_TEXT_COLOR
        cx := close_rect.x + close_rect.width  * 0.5
        cy := close_rect.y + close_rect.height * 0.5
        d  := f32(4)
        rl.DrawLineEx(rl.Vector2{cx-d, cy-d}, rl.Vector2{cx+d, cy+d}, 2, close_color)
        rl.DrawLineEx(rl.Vector2{cx+d, cy-d}, rl.Vector2{cx-d, cy+d}, 2, close_color)
    }

    // Detach/restore button — second from right
    if panel.detachable {
        detach_rect  := rl.Rectangle{ panel.rect.x + panel.rect.width - 42, panel.rect.y + 4, 16, 16 }
        detach_hover := rl.CheckCollisionPointRec(mouse, detach_rect)
        detach_color := detach_hover ? ACCENT_COLOR : TITLE_TEXT_COLOR
        if panel.maximized {
            // Restore icon: two offset overlapping boxes
            rl.DrawRectangleLinesEx(rl.Rectangle{detach_rect.x+2, detach_rect.y+4, 9, 9}, 1, detach_color)
            rl.DrawRectangleLinesEx(rl.Rectangle{detach_rect.x+5, detach_rect.y+2, 9, 9}, 1, detach_color)
        } else {
            // Maximize icon: single hollow box
            rl.DrawRectangleLinesEx(rl.Rectangle{detach_rect.x+2, detach_rect.y+2, 12, 12}, 1, detach_color)
        }
    }

    // Resize grip: two parallel diagonal lines (only when not maximized)
    if !panel.maximized {
        gx := panel.rect.x + panel.rect.width
        gy := panel.rect.y + panel.rect.height
        gs := RESIZE_GRIP_SIZE
        rl.DrawLineEx(
            rl.Vector2{gx - gs,       gy},
            rl.Vector2{gx,       gy - gs},
            2, BORDER_COLOR,
        )
        rl.DrawLineEx(
            rl.Vector2{gx - gs*0.55, gy},
            rl.Vector2{gx,       gy - gs*0.55},
            2, BORDER_COLOR,
        )
    }

    return rl.Rectangle{
        panel.rect.x,
        panel.rect.y + TITLE_BAR_HEIGHT,
        panel.rect.width,
        panel.rect.height - TITLE_BAR_HEIGHT,
    }
}

draw_dim_overlay :: proc() {
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    rl.DrawRectangle(0, 0, sw, sh, rl.Color{0, 0, 0, 140})
}

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

draw_log_content :: proc(app: ^App, content: rl.Rectangle) {
    x    := i32(content.x) + 8
    y    := i32(content.y) + 6
    fs   := i32(12)
    lh   := i32(16)
    max_lines := int((content.height - 10) / f32(lh))
    if max_lines <= 0 { return }

    count   := app.log_count
    visible := min(count, max_lines)
    start   := count - visible

    for i in 0..<visible {
        idx := (start + i) % LOG_RING_SIZE
        msg := app.log_lines[idx]
        if len(msg) == 0 { continue }
        rl.DrawText(fmt.ctprintf("%s", msg), x, y + i32(i)*lh, fs, CONTENT_TEXT_COLOR)
    }
}

upload_render_texture :: proc(app: ^App) {
    session := app.session
    if session == nil { return }

    buf    := &session.pixel_buffer
    camera := session.camera
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

draw_render_panel :: proc(app: ^App) {
    content := draw_panel_chrome(app.render_panel)
    if !app.render_panel.visible { return }

    cam    := app.session.camera
    src_w  := f32(cam.image_width)
    src_h  := f32(cam.image_height)
    aspect := src_w / src_h

    dest_w := content.width
    dest_h := content.height
    if dest_w / dest_h > aspect {
        dest_w = dest_h * aspect
    } else {
        dest_h = dest_w / aspect
    }

    ox := content.x + (content.width  - dest_w) * 0.5
    oy := content.y + (content.height - dest_h) * 0.5

    src  := rl.Rectangle{0, 0, src_w, src_h}
    dest := rl.Rectangle{ox, oy, dest_w, dest_h}

    rl.DrawTexturePro(app.render_tex, src, dest, rl.Vector2{0, 0}, 0, rl.WHITE)
}

draw_stats_panel :: proc(app: ^App) {
    content := draw_panel_chrome(app.stats_panel)
    if !app.stats_panel.visible { return }
    draw_stats_content(app, content)
}

draw_log_panel :: proc(app: ^App) {
    content := draw_panel_chrome(app.log_panel)
    if !app.log_panel.visible { return }
    draw_log_content(app, content)
}
