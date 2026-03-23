// Standalone smoke test for vk_ctx: Vulkan instance/device/queues/pool + optional clear-image submit.
//
// Dependencies: system Vulkan loader (libvulkan), GLFW (linked via vendor/glfw).
// Optional: validation layers (vulkan-validation-layers / LunarG SDK) when built with -debug.
// After init, prints GPU name, limits, memory heaps, and queue families (see vk_ctx.print_vulkan_context_gpu_info).
//
// Usage:
//   ./build/vk_smoke --headless [--clear]
//   ./build/vk_smoke --window
package main

import "core:c"
import "core:fmt"
import "core:os"

import glfw "vendor:glfw"
import "RT_Weekend:vk_ctx"

main :: proc() {
	mode := "headless"
	do_clear := false
	for arg in os.args[1:] {
		switch arg {
		case "--headless":
			mode = "headless"
		case "--window":
			mode = "window"
		case "--clear":
			do_clear = true
		case:
			fmt.eprintf("Unknown argument: %s\n", arg)
			os.exit(2)
		}
	}

	if mode == "headless" {
		ctx, ok := vk_ctx.vulkan_context_init_headless()
		defer vk_ctx.vulkan_context_destroy(&ctx)
		if !ok {
			fmt.eprintln("vk_smoke: headless init failed")
			os.exit(1)
		}
		fmt.println("vk_smoke: headless Vulkan context OK")
		vk_ctx.print_vulkan_context_gpu_info(&ctx)
		if do_clear {
			if vk_ctx.headless_submit_clear_color_test(&ctx) {
				fmt.println("vk_smoke: clear-color submit OK")
			} else {
				fmt.eprintln("vk_smoke: clear-color submit failed")
				os.exit(1)
			}
		}
		return
	}

	// window mode
	ctx, ok := vk_ctx.vulkan_context_init_window(cstring("vk_smoke"), c.int(640), c.int(480))
	defer vk_ctx.vulkan_context_destroy(&ctx)
	if !ok {
		fmt.eprintln("vk_smoke: window init failed")
		os.exit(1)
	}
	fmt.println("vk_smoke: window + surface OK")
	vk_ctx.print_vulkan_context_gpu_info(&ctx)
	fmt.println("(close window to exit)")
	for !glfw.WindowShouldClose(ctx.glfw_window) {
		glfw.PollEvents()
	}
}
