package editor

import "core:fmt"
import "core:sync"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

// Checkbox rect for "Use GPU (next render)" — draw the small box.
_stats_gpu_checkbox_rect :: proc(content: rl.Rectangle) -> rl.Rectangle {
    return rl.Rectangle{ content.x + 10, content.y + 6, 14, 14 }
}
// Full clickable row (checkbox + label) so the whole line toggles.
_stats_gpu_row_rect :: proc(content: rl.Rectangle) -> rl.Rectangle {
    return rl.Rectangle{ content.x + 10, content.y + 4, 120, 20 }
}
// Y position of the Continuous/Restart row:
//   base(8) + Next-render-row(20) + Mode-row(20) = 48 below content.y
_stats_gpu_controls_y :: proc(content: rl.Rectangle) -> i32 {
    return i32(content.y) + 48
}
_stats_continuous_checkbox_rect :: proc(content: rl.Rectangle) -> rl.Rectangle {
    y := f32(_stats_gpu_controls_y(content))
    return rl.Rectangle{ content.x + 10, y + 2, 14, 14 }
}
_stats_continuous_row_rect :: proc(content: rl.Rectangle) -> rl.Rectangle {
    y := f32(_stats_gpu_controls_y(content))
    return rl.Rectangle{ content.x + 10, y, 100, 20 }
}
_stats_restart_btn_rect :: proc(content: rl.Rectangle) -> rl.Rectangle {
    y := f32(_stats_gpu_controls_y(content))
    return rl.Rectangle{ content.x + 115, y + 1, 54, 18 }
}

draw_stats_content :: proc(app: ^App, content: rl.Rectangle) {
    x := i32(content.x) + 10
    y := i32(content.y) + 8
    line_h := i32(20)
    fs := i32(14)

    // "Use GPU (next render)" toggle — always visible so user can change preference.
    draw_ui_text(app, "Next render:", x, y, fs, CONTENT_TEXT_COLOR)
    box := _stats_gpu_checkbox_rect(content)
    rl.DrawRectangleLinesEx(box, 1, BORDER_COLOR)
    if app.prefer_gpu {
        rl.DrawRectangle(i32(box.x) + 2, i32(box.y) + 2, i32(box.width) - 4, i32(box.height) - 4, ACCENT_COLOR)
    }
    draw_ui_text(app, app.prefer_gpu ? cstring(" GPU") : cstring(" CPU"), i32(box.x + box.width + 4), y, fs, CONTENT_TEXT_COLOR)
    y += line_h

    session := app.r_session
    if session == nil { return }

    elapsed := app.elapsed_secs

    progress_color := CONTENT_TEXT_COLOR
    if app.finished {
        progress_color = DONE_COLOR
    }

    // Current session mode — GPU or CPU.
    mode := session.use_gpu ? cstring("GPU") : cstring("CPU")
    draw_ui_text(app, fmt.ctprintf("Mode:     %s", mode), x, y, fs, CONTENT_TEXT_COLOR)
    y += line_h

    // GPU-only controls: Continuous toggle + Restart button.
    // Show even after SingleShot completes (gpu_renderer becomes nil after finish_render).
    if session.use_gpu {
        gpu_rend := session.gpu_renderer // may be nil after SingleShot completion
        is_continuous := gpu_rend != nil && gpu_rend.mode == .Continuous

        // Continuous checkbox.
        cont_box := _stats_continuous_checkbox_rect(content)
        rl.DrawRectangleLinesEx(cont_box, 1, BORDER_COLOR)
        if is_continuous {
            rl.DrawRectangle(
                i32(cont_box.x) + 2, i32(cont_box.y) + 2,
                i32(cont_box.width) - 4, i32(cont_box.height) - 4,
                ACCENT_COLOR,
            )
        }
        draw_ui_text(app, " Continuous", i32(cont_box.x + cont_box.width + 2), y + 2, 12, CONTENT_TEXT_COLOR)

        // Restart button.
        restart_rect := _stats_restart_btn_rect(content)
        rl.DrawRectangleRec(restart_rect, rl.Color{45, 50, 70, 200})
        rl.DrawRectangleLinesEx(restart_rect, 1, BORDER_COLOR)
        draw_ui_text(app, "Restart", i32(restart_rect.x) + 5, i32(restart_rect.y) + 2, 11, CONTENT_TEXT_COLOR)

        y += line_h
    }

    // Progress line: GPU shows sample count; CPU shows tile count.
    progress_frac := f32(0)
    if session.use_gpu {
        gpu_rend := session.gpu_renderer
        cur, tot := 0, 0
        if gpu_rend != nil { cur, tot = rt.gpu_renderer_get_samples(gpu_rend) }
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
        fmt.ctprintf("Size:     %dx%d", session.r_camera.image_width, session.r_camera.image_height),
        x, y, fs, CONTENT_TEXT_COLOR,
    )
    y += line_h

    draw_ui_text(app,
        fmt.ctprintf("Samples:  %d/px", session.r_camera.samples_per_pixel),
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
    y = bar_y + i32(bar_h) + line_h

    // Performance: per-step times when render is complete (CLI and UI share same summary).
    content_bottom := i32(content.y + content.height)
    if app.finished {
        profile := rt.get_render_profile(app.r_session)
        if profile != nil && profile.total_seconds > 0 {
            if y >= content_bottom { return }
            draw_ui_text(app, "Performance:", x, y, fs, CONTENT_TEXT_COLOR)
            y += line_h
            if y >= content_bottom { return }
            draw_ui_text(app, fmt.ctprintf("  Total: %.2fs", profile.total_seconds), x, y, fs, CONTENT_TEXT_COLOR)
            y += line_h
            for i in 0..<profile.phase_count {
                if y >= content_bottom { break }
                phase := profile.phases[i]
                if phase.seconds <= 0 { continue }
                draw_ui_text(app, fmt.ctprintf("  %s: %.2fs (%.1f%%)", phase.name, phase.seconds, phase.percent), x, y, fs, CONTENT_TEXT_COLOR)
                y += line_h
            }
            if profile.has_sample_breakdown {
                if y >= content_bottom { return }
                draw_ui_text(app, "  Sample: Ray/Int/Scat/BG/Pix %", x, y, fs, CONTENT_TEXT_COLOR)
                y += line_h
                if y >= content_bottom { return }
                draw_ui_text(app, fmt.ctprintf("  %.1f / %.1f / %.1f / %.1f / %.1f",
                    profile.sample_get_ray_pct, profile.sample_intersection_pct, profile.sample_scatter_pct,
                    profile.sample_background_pct, profile.sample_pixel_setup_pct), x, y, fs, CONTENT_TEXT_COLOR)
                y += line_h
            }
            // GPU dispatch / readback timing (only shown in GPU mode).
            if session != nil && session.use_gpu {
                if profile.gpu_dispatch_seconds > 0 {
                    if y >= content_bottom { return }
                    draw_ui_text(app, fmt.ctprintf("  GPU Exec: %.2fs (%.0fms/sample)",
                        profile.gpu_dispatch_seconds,
                        profile.gpu_dispatch_seconds * 1000 / f64(max(session.r_camera.samples_per_pixel, 1))), x, y, fs, CONTENT_TEXT_COLOR)
                    y += line_h
                }
                if profile.gpu_readback_seconds > 0 {
                    if y >= content_bottom { return }
                    draw_ui_text(app, fmt.ctprintf("  GPU Readback: %.2fs", profile.gpu_readback_seconds), x, y, fs, CONTENT_TEXT_COLOR)
                    y += line_h
                }
            }
        }
    }
}

update_stats_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
    if !lmb_pressed { return }

    // "Next render: GPU/CPU" toggle.
    if rl.CheckCollisionPointRec(mouse, _stats_gpu_row_rect(rect)) {
        app.prefer_gpu = !app.prefer_gpu
        if g_app != nil { g_app.input_consumed = true }
        return
    }

    // GPU-only controls: only active when a GPU render session is live.
    session := app.r_session
    if session == nil || !session.use_gpu { return }
    gpu_rend := session.gpu_renderer // may be nil after SingleShot completion

    // Continuous mode toggle (only meaningful when renderer is alive).
    if gpu_rend != nil && rl.CheckCollisionPointRec(mouse, _stats_continuous_row_rect(rect)) {
        new_mode := rt.GpuRenderMode.Continuous if gpu_rend.mode == .SingleShot else rt.GpuRenderMode.SingleShot
        rt.gpu_renderer_set_mode(gpu_rend, new_mode)
        if g_app != nil { g_app.input_consumed = true }
        return
    }

    // Restart button.
    if rl.CheckCollisionPointRec(mouse, _stats_restart_btn_rect(rect)) {
        if gpu_rend != nil {
            // Renderer still alive (e.g. Continuous mode): soft reset.
            rt.gpu_renderer_restart(gpu_rend)
            app.finished = false
        } else {
            // Renderer was destroyed after SingleShot completion: trigger a full re-render.
            cmd_execute(app, CMD_RENDER_RESTART)
        }
        if g_app != nil { g_app.input_consumed = true }
    }
}
