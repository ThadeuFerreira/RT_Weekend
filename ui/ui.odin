package ui

import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

// PanelStyle holds the intrinsic immutable visual theme for a panel (Flyweight pattern).
// Shared across many panels with the same look; per-instance state lives in FloatingPanel.
PanelStyle :: struct {
    bg_color:           rl.Color,
    title_bg_color:     rl.Color,
    title_text_color:   rl.Color,
    border_color:       rl.Color,
    content_text_color: rl.Color,
    accent_color:       rl.Color,
    done_color:         rl.Color,
    title_bar_height:   f32,
    resize_grip_size:   f32,
}

DEFAULT_PANEL_STYLE :: PanelStyle{
    bg_color           = rl.Color{35,  35,  50,  230},
    title_bg_color     = rl.Color{55,  55,  80,  255},
    title_text_color   = rl.RAYWHITE,
    border_color       = rl.Color{80,  80, 110,  255},
    content_text_color = rl.Color{200, 210, 220, 255},
    accent_color       = rl.Color{100, 180, 255, 255},
    done_color         = rl.Color{100, 220, 120, 255},
    title_bar_height   = 24,
    resize_grip_size   = 14,
}

// Package-level constants kept for content procs that have not yet been migrated to PanelStyle.
TITLE_BAR_HEIGHT   :: f32(24)
RESIZE_GRIP_SIZE   :: f32(14)

PANEL_BG_COLOR     :: rl.Color{35,  35,  50,  230}
TITLE_BG_COLOR     :: rl.Color{55,  55,  80,  255}
TITLE_TEXT_COLOR   :: rl.RAYWHITE
BORDER_COLOR       :: rl.Color{80,  80, 110,  255}
CONTENT_TEXT_COLOR :: rl.Color{200, 210, 220, 255}
ACCENT_COLOR       :: rl.Color{100, 180, 255, 255}
DONE_COLOR         :: rl.Color{100, 220, 120, 255}

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

// clamp_panel_to_screen keeps the panel inside the window bounds (e.g. after window resize).
clamp_panel_to_screen :: proc(panel: ^FloatingPanel, screen_w, screen_h: f32) {
    if !panel.visible { return }
    sw := screen_w
    sh := screen_h
    r := &panel.rect
    if r.x < 0 { r.x = 0 }
    if r.y < 0 { r.y = 0 }
    if r.width < panel.min_size.x { r.width = panel.min_size.x }
    if r.height < panel.min_size.y { r.height = panel.min_size.y }
    if r.x + r.width > sw { r.x = sw - r.width }
    if r.y + r.height > sh { r.y = sh - r.height }
    if r.x < 0 { r.x = 0 }
    if r.y < 0 { r.y = 0 }
}

draw_panel_chrome :: proc(panel: FloatingPanel) -> rl.Rectangle {
    if !panel.visible {
        return rl.Rectangle{}
    }

    style := DEFAULT_PANEL_STYLE
    if panel.style != nil {
        style = panel.style^
    }

    rl.DrawRectangleRec(panel.rect, style.bg_color)
    rl.DrawRectangleLinesEx(panel.rect, 1, style.border_color)

    title_rect := rl.Rectangle{panel.rect.x, panel.rect.y, panel.rect.width, style.title_bar_height}
    rl.DrawRectangleRec(title_rect, style.title_bg_color)
    rl.DrawText(panel.title, i32(panel.rect.x) + 6, i32(panel.rect.y) + 5, 14, style.title_text_color)

    mouse := rl.GetMousePosition()

    // Close button [X] — rightmost
    if panel.closeable {
        close_rect  := rl.Rectangle{ panel.rect.x + panel.rect.width - 22, panel.rect.y + 4, 16, 16 }
        close_hover := rl.CheckCollisionPointRec(mouse, close_rect)
        close_color := close_hover ? rl.RED : style.title_text_color
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
        detach_color := detach_hover ? style.accent_color : style.title_text_color
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
        gs := style.resize_grip_size
        rl.DrawLineEx(
            rl.Vector2{gx - gs,       gy},
            rl.Vector2{gx,       gy - gs},
            2, style.border_color,
        )
        rl.DrawLineEx(
            rl.Vector2{gx - gs*0.55, gy},
            rl.Vector2{gx,       gy - gs*0.55},
            2, style.border_color,
        )
    }

    return rl.Rectangle{
        panel.rect.x,
        panel.rect.y + style.title_bar_height,
        panel.rect.width,
        panel.rect.height - style.title_bar_height,
    }
}

draw_dim_overlay :: proc() {
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    rl.DrawRectangle(0, 0, sw, sh, rl.Color{0, 0, 0, 140})
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

// screen_to_render_ray maps a screen-space position to an rl.Ray through the
// corresponding point in the 3D scene. Returns ok=false when the panel is hidden,
// the session is nil, or the position is outside the letterboxed image.
screen_to_render_ray :: proc(app: ^App, pos: rl.Vector2) -> (r: rl.Ray, ok: bool) {
    render_panel := app_find_panel(app, PANEL_ID_RENDER)
    if render_panel == nil || !render_panel.visible || app.session == nil {
        return {}, false
    }

    panel   := render_panel^
    content := rl.Rectangle{
        panel.rect.x,
        panel.rect.y + TITLE_BAR_HEIGHT,
        panel.rect.width,
        panel.rect.height - TITLE_BAR_HEIGHT,
    }

    dest := render_dest_rect(app, content)
    if !rl.CheckCollisionPointRec(pos, dest) {
        return {}, false
    }

    u := (pos.x - dest.x) / dest.width
    v := (pos.y - dest.y) / dest.height

    cam := app.session.camera
    internal_ray := rt.pixel_to_ray(cam, u * f32(cam.image_width), v * f32(cam.image_height))

    dir := rt.unit_vector(internal_ray.dir)
    return rl.Ray{
        position  = rl.Vector3{internal_ray.orig[0], internal_ray.orig[1], internal_ray.orig[2]},
        direction = rl.Vector3{dir[0], dir[1], dir[2]},
    }, true
}

draw_panel :: proc(panel: ^FloatingPanel, app: ^App) {
    content := draw_panel_chrome(panel^)
    if !panel.visible { return }
    if panel.draw_content != nil {
        panel.draw_content(app, content)
    }
}
