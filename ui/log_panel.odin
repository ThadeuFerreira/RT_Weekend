package ui

import "core:fmt"

import rl "vendor:raylib"

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
