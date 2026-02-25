package ui

import "core:fmt"
import "RT_Weekend:util"
import rl "vendor:raylib"

draw_system_info_content :: proc(app: ^App, content: rl.Rectangle) {

    x    := i32(content.x) + 8
    y    := i32(content.y) + 6
    fs   := i32(12)
    lh   := i32(16)
    max_lines := int((content.height - 10) / f32(lh))
    if max_lines <= 0 { return }


    system_info := util.get_system_info()

    draw_ui_text(app, fmt.ctprintf("Odin:      %v", system_info.OdinVersion), x+10, y+10, 12, rl.WHITE)
    draw_ui_text(app, fmt.ctprintf("OS:        %v", system_info.OS.Name), x+10, y+30, 12, rl.WHITE)
    draw_ui_text(app, fmt.ctprintf("CPU:       %v", system_info.CPU.Name), x+10, y+50, 12, rl.WHITE)
    draw_ui_text(app, fmt.ctprintf("CPU cores: %vc/%vt", system_info.CPU.Cores, system_info.CPU.LogicalCores), x+10, y+70, 12, rl.WHITE)
    draw_ui_text(app, fmt.ctprintf("RAM:       %#.1M", system_info.RAM.Total), x+10, y+90, 12, rl.WHITE)
    for gpu in system_info.GPUs {
        draw_ui_text(app, fmt.ctprintf("GPU:       %v", gpu.Model), x+10, y+110, 12, rl.WHITE)
        draw_ui_text(app, fmt.ctprintf("GPU Vendor: %v", gpu.Vendor), x+10, y+130, 12, rl.WHITE)
        draw_ui_text(app, fmt.ctprintf("GPU VRAM:  %#.1M", gpu.VRAM), x+10, y+130, 12, rl.WHITE)
    }
}