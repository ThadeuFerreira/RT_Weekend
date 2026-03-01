package editor

import "core:fmt"
import "RT_Weekend:util"
import rl "vendor:raylib"

draw_system_info_content :: proc(app: ^App, content: rl.Rectangle) {
    pad     := i32(10)
    x       := i32(content.x) + pad
    line_y  := i32(content.y) + 6
    fs      := i32(12)
    lh      := i32(16)

    // Clip to content area so long text does not overflow and malform the layout.
    rl.BeginScissorMode(i32(content.x), i32(content.y), i32(content.width), i32(content.height))
    defer rl.EndScissorMode()

    system_info := util.get_system_info()
    content_bottom := i32(content.y + content.height)

    draw_line :: proc(app: ^App, x, line_y: i32, text: cstring, fs: i32) {
        draw_ui_text(app, text, x, line_y, fs, CONTENT_TEXT_COLOR)
    }

    // Fixed lines: Odin, OS, CPU, cores, RAM
    draw_line(app, x, line_y, fmt.ctprintf("Odin:      %v", system_info.OdinVersion), fs)
    line_y += lh
    draw_line(app, x, line_y, fmt.ctprintf("OS:        %v", system_info.OS.Name), fs)
    line_y += lh
    draw_line(app, x, line_y, fmt.ctprintf("CPU:       %v", system_info.CPU.Name), fs)
    line_y += lh
    draw_line(app, x, line_y, fmt.ctprintf("CPU cores: %vc/%vt", system_info.CPU.Cores, system_info.CPU.LogicalCores), fs)
    line_y += lh
    draw_line(app, x, line_y, fmt.ctprintf("RAM:       %#.1M", system_info.RAM.Total), fs)
    line_y += lh

    // All GPUs (integrated + dedicated, etc.); each GPU gets 3 lines
    for gpu in system_info.GPUs {
        if line_y + lh * 3 > content_bottom { break }
        draw_line(app, x, line_y, fmt.ctprintf("GPU:       %v", gpu.Model), fs)
        line_y += lh
        draw_line(app, x, line_y, fmt.ctprintf("  Vendor:  %v", gpu.Vendor), fs)
        line_y += lh
        draw_line(app, x, line_y, fmt.ctprintf("  VRAM:    %#.1M", gpu.VRAM), fs)
        line_y += lh
    }
}