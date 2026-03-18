package editor

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
