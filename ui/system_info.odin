package ui

import "core:fmt"
import "RT_Weekend:util"
import rl "vendor:raylib"

draw_system_info_content :: proc(app: ^App, content: rl.Rectangle) {
    system_info := util.get_system_info()

    rl.DrawText(fmt.ctprintf("Odin:      %v", system_info.OdinVersion), 10, 10, 12, rl.WHITE)
    rl.DrawText(fmt.ctprintf("OS:        %v", system_info.OS.Name), 10, 30, 12, rl.WHITE)
    rl.DrawText(fmt.ctprintf("CPU:       %v", system_info.CPU.Name), 10, 50, 12, rl.WHITE)
    rl.DrawText(fmt.ctprintf("CPU cores: %vc/%vt", system_info.CPU.Cores, system_info.CPU.LogicalCores), 10, 70, 12, rl.WHITE)
    rl.DrawText(fmt.ctprintf("RAM:       %#.1M", system_info.RAM.Total), 10, 90, 12, rl.WHITE)
    for gpu in system_info.GPUs {
        rl.DrawText(fmt.ctprintf("GPU:       %v", gpu.Model), 10, 110, 12, rl.WHITE)
        rl.DrawText(fmt.ctprintf("GPU VRAM:  %#.1M", gpu.VRAM), 10, 130, 12, rl.WHITE)
    }
}