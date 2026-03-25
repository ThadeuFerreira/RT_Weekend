package vk_ctx

import "core:c"
import "core:fmt"

import glfw "vendor:glfw"
import vk "vendor:vulkan"

// vulkan_context_init_window creates a GLFW window (NO_API), a Vulkan surface, and a full
// VulkanContext with separate present queue when required. Linux / Windows / macOS when GLFW + WSI
// are available; swapchain is not created here.
vulkan_context_init_window :: proc(
	title: cstring,
	width, height: c.int,
	window_platform: c.int = glfw.ANY_PLATFORM,
) -> (ctx: VulkanContext, ok: bool) {
	ctx = {}
	when ODIN_OS == .JS {
		fmt.eprintln("vk_ctx: window mode unsupported on JS")
		return ctx, false
	}

	if !vk_load_vulkan(window_platform = window_platform) {
		fmt.eprintln("vk_ctx: vk_load_vulkan failed")
		return ctx, false
	}
	ctx.glfw_owned = true

	glfw.DefaultWindowHints()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, true)
	glfw.WindowHint(glfw.SCALE_TO_MONITOR, true)
	glfw.WindowHint(glfw.VISIBLE, true)
	glfw.WindowHint(glfw.FOCUSED, true)
	win := glfw.CreateWindow(width, height, title, nil, nil)
	if win == nil {
		desc, _ := glfw.GetError()
		fmt.eprintf("vk_ctx: glfw.CreateWindow failed: %s\n", desc)
		vulkan_context_destroy(&ctx)
		return ctx, false
	}
	ctx.glfw_window = win

	exts: [dynamic]cstring
	defer delete(exts)
	glfw_exts := glfw.GetRequiredInstanceExtensions()
	for e in glfw_exts {
		append_cstring_unique(&exts, e)
	}
	use_validation := VK_VALIDATION && validation_layer_available()

	if use_validation {
		append_cstring_unique(&exts, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	inst, inst_ok := create_instance(cstring("vk_ctx window"), exts[:], use_validation)
	if !inst_ok {
		fmt.eprintln("vk_ctx: create_instance failed")
		vulkan_context_destroy(&ctx)
		return ctx, false
	}
	ctx.instance = inst

	if use_validation {
		success: bool
		when VK_VERBOSE {
			success = setup_debug_messenger_verbose(inst, &ctx.debug_messenger)
		} else {
			success = setup_debug_messenger(inst, &ctx.debug_messenger)
		}
		if !success {
			fmt.eprintln("vk_ctx: setup_debug_messenger failed")
		}
	}

	surf: vk.SurfaceKHR
	if glfw.CreateWindowSurface(inst, win, nil, &surf) != .SUCCESS {
		fmt.eprintln("vk_ctx: glfw.CreateWindowSurface failed")
		vulkan_context_destroy(&ctx)
		return ctx, false
	}
	ctx.surface = surf

	phys, gfam, pfam, dev_ok := pick_physical_device(inst, surf)
	if !dev_ok {
		fmt.eprintln("vk_ctx: no suitable physical device for surface")
		vulkan_context_destroy(&ctx)
		return ctx, false
	}
	ctx.physical_device = phys
	ctx.graphics_queue_family = gfam
	ctx.present_queue_family = pfam

	cfam, cfam_ok := find_compute_queue_family(phys)
	if !cfam_ok {
		fmt.eprintln("vk_ctx: no compute queue family")
		vulkan_context_destroy(&ctx)
		return ctx, false
	}
	ctx.compute_queue_family = cfam

	families := [?]u32{gfam, pfam, cfam}
	dev_exts := [?]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
	dev, d_ok := create_logical_device(phys, families[:], dev_exts[:])
	if !d_ok {
		vulkan_context_destroy(&ctx)
		return ctx, false
	}
	ctx.device = dev

	vk.GetDeviceQueue(dev, gfam, 0, &ctx.graphics_queue)
	vk.GetDeviceQueue(dev, pfam, 0, &ctx.present_queue)
	vk.GetDeviceQueue(dev, cfam, 0, &ctx.compute_queue)

	if !create_command_pool_and_sync(dev, gfam, &ctx) {
		vulkan_context_destroy(&ctx)
		return ctx, false
	}

	if !create_compute_command_pool(&ctx) {
		vulkan_context_destroy(&ctx)
		return ctx, false
	}

	label_context_objects(&ctx)
	return ctx, true
}
