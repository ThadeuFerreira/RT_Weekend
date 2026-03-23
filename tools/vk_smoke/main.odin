// Standalone smoke test for vk_ctx: Vulkan instance/device/queues/pool, optional clear-image submit,
// and optional compute pipeline dispatch.
//
// Dependencies: system Vulkan loader (libvulkan), GLFW (linked via vendor/glfw).
// Optional: validation layers (vulkan-validation-layers / LunarG SDK) when built with -debug.
// After init, prints GPU name, limits, memory heaps, and queue families (see vk_ctx.print_vulkan_context_gpu_info).
//
// Usage:
//   ./build/vk_smoke --headless [--clear] [--compute]
//   ./build/vk_smoke --window
package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"

import glfw "vendor:glfw"
import vk "vendor:vulkan"
import "RT_Weekend:vk_ctx"

RAYTRACE_VK_SPV :: #load("../../assets/shaders/raytrace_vk.comp.spv")

main :: proc() {
	mode := "headless"
	do_clear := false
	do_compute := false
	for arg in os.args[1:] {
		switch arg {
		case "--headless":
			mode = "headless"
		case "--window":
			mode = "window"
		case "--clear":
			do_clear = true
		case "--compute":
			do_compute = true
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
		if do_compute {
			if !run_compute_test(&ctx) {
				fmt.eprintln("vk_smoke: compute pipeline test failed")
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
	platform := glfw.GetPlatform()
	switch platform {
	case glfw.PLATFORM_WAYLAND: fmt.println("  GLFW platform: Wayland")
	case glfw.PLATFORM_X11:     fmt.println("  GLFW platform: X11")
	case glfw.PLATFORM_WIN32:   fmt.println("  GLFW platform: Win32")
	case glfw.PLATFORM_COCOA:   fmt.println("  GLFW platform: Cocoa")
	case glfw.PLATFORM_NULL:    fmt.println("  GLFW platform: Null")
	case:                       fmt.printf("  GLFW platform: unknown (0x%x)\n", platform)
	}
	vk_ctx.print_vulkan_context_gpu_info(&ctx)

	sc, sc_ok := vk_ctx.create_swapchain(&ctx, 640, 480)
	defer vk_ctx.destroy_swapchain(ctx.device, &sc)
	if !sc_ok {
		fmt.eprintln("vk_smoke: swapchain creation failed")
		os.exit(1)
	}
	fmt.println("vk_smoke: swapchain OK")
	fmt.println("(close window to exit)")

	for !glfw.WindowShouldClose(ctx.glfw_window) {
		glfw.PollEvents()
		// Clear to cornflower blue.
		if !vk_ctx.swapchain_present_clear(&ctx, &sc, 0.39, 0.58, 0.93) {
			break
		}
	}
	vk.DeviceWaitIdle(ctx.device)
}

// run_compute_test exercises the full pipeline: create pipeline, allocate buffers,
// write descriptors, dispatch 1 sample, read back, verify the blue stub output.
run_compute_test :: proc(ctx: ^vk_ctx.VulkanContext) -> bool {
	W :: u32(16)
	H :: u32(16)
	PIXEL_COUNT :: int(W * H)

	// 1. Create compute pipeline from embedded SPIR-V.
	spv := RAYTRACE_VK_SPV
	pipeline, pipe_ok := vk_ctx.create_vulkan_compute_pipeline(ctx.device, spv[:])
	if !pipe_ok {
		fmt.eprintln("  compute: pipeline creation failed")
		return false
	}
	defer vk_ctx.destroy_vulkan_compute_pipeline(ctx.device, &pipeline)
	fmt.println("  compute: pipeline created OK")

	// 2. Allocate buffers.
	// UBO: camera uniforms (128 bytes, std140).
	CameraUBO :: struct #packed {
		origin:         [3]f32, _pad0: f32,
		pixel00_loc:    [3]f32, _pad1: f32,
		pixel_delta_u:  [3]f32, _pad2: f32,
		pixel_delta_v:  [3]f32, _pad3: f32,
		defocus_disk_u: [3]f32, _pad4: f32,
		defocus_disk_v: [3]f32, _pad5: f32,
		background:     [3]f32, _pad6: f32,
		width:          i32,
		height:         i32,
		max_depth:      i32,
		total_samples:  i32,
		current_sample: i32,
		defocus_angle:  f32,
		shutter_open:   f32,
		shutter_close:  f32,
	}
	cam := CameraUBO{
		width          = i32(W),
		height         = i32(H),
		max_depth      = 10,
		total_samples  = 1,
		current_sample = 1,
		background     = {1, 1, 1},
	}
	ubo, ubo_ok := vk_ctx.create_host_visible_buffer(
		ctx.device, ctx.physical_device,
		vk.DeviceSize(size_of(CameraUBO)),
		{.UNIFORM_BUFFER},
	)
	if !ubo_ok { fmt.eprintln("  compute: UBO alloc failed"); return false }
	defer vk_ctx.destroy_buffer(ctx.device, &ubo)
	mem.copy(ubo.mapped, &cam, size_of(CameraUBO))

	// Empty SSBOs for scene data (header only: 16 bytes with count=0).
	EmptyHeader :: struct { count: i32, _pad: [3]i32 }
	empty_hdr := EmptyHeader{}
	HEADER_SIZE :: vk.DeviceSize(size_of(EmptyHeader))

	spheres, s1 := vk_ctx.create_host_visible_buffer(ctx.device, ctx.physical_device, HEADER_SIZE, {.STORAGE_BUFFER})
	if !s1 { return false }
	defer vk_ctx.destroy_buffer(ctx.device, &spheres)
	mem.copy(spheres.mapped, &empty_hdr, int(HEADER_SIZE))

	bvh, s2 := vk_ctx.create_host_visible_buffer(ctx.device, ctx.physical_device, HEADER_SIZE, {.STORAGE_BUFFER})
	if !s2 { return false }
	defer vk_ctx.destroy_buffer(ctx.device, &bvh)
	mem.copy(bvh.mapped, &empty_hdr, int(HEADER_SIZE))

	quads, s3 := vk_ctx.create_host_visible_buffer(ctx.device, ctx.physical_device, HEADER_SIZE, {.STORAGE_BUFFER})
	if !s3 { return false }
	defer vk_ctx.destroy_buffer(ctx.device, &quads)
	mem.copy(quads.mapped, &empty_hdr, int(HEADER_SIZE))

	volumes, s4 := vk_ctx.create_host_visible_buffer(ctx.device, ctx.physical_device, HEADER_SIZE, {.STORAGE_BUFFER})
	if !s4 { return false }
	defer vk_ctx.destroy_buffer(ctx.device, &volumes)
	mem.copy(volumes.mapped, &empty_hdr, int(HEADER_SIZE))

	vol_quads, s5 := vk_ctx.create_host_visible_buffer(ctx.device, ctx.physical_device, HEADER_SIZE, {.STORAGE_BUFFER})
	if !s5 { return false }
	defer vk_ctx.destroy_buffer(ctx.device, &vol_quads)
	mem.copy(vol_quads.mapped, &empty_hdr, int(HEADER_SIZE))

	// Output buffer: W*H vec4 (zeroed by host-visible init).
	OUT_SIZE :: vk.DeviceSize(PIXEL_COUNT * size_of([4]f32))
	output, o_ok := vk_ctx.create_host_visible_buffer(ctx.device, ctx.physical_device, OUT_SIZE, {.STORAGE_BUFFER})
	if !o_ok { return false }
	defer vk_ctx.destroy_buffer(ctx.device, &output)
	mem.set(output.mapped, 0, int(OUT_SIZE))

	// 3. Write descriptors.
	buffers := [7]vk_ctx.VulkanBuffer{ubo, spheres, bvh, output, quads, volumes, vol_quads}
	vk_ctx.write_raytrace_descriptors(ctx.device, pipeline.descriptor_set, buffers)
	fmt.println("  compute: buffers + descriptors OK")

	// 4. Record and submit a compute dispatch.
	cmd_alloc := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	cmd: vk.CommandBuffer
	if vk.AllocateCommandBuffers(ctx.device, &cmd_alloc, &cmd) != .SUCCESS { return false }
	defer vk.FreeCommandBuffers(ctx.device, ctx.command_pool, 1, &cmd)

	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if vk.BeginCommandBuffer(cmd, &begin) != .SUCCESS { return false }

	vk.CmdBindPipeline(cmd, .COMPUTE, pipeline.pipeline)
	vk.CmdBindDescriptorSets(cmd, .COMPUTE, pipeline.pipeline_layout, 0, 1, &pipeline.descriptor_set, 0, nil)
	vk.CmdDispatch(cmd, u32(math.ceil(f32(W) / 8.0)), u32(math.ceil(f32(H) / 8.0)), 1)

	if vk.EndCommandBuffer(cmd) != .SUCCESS { return false }

	if vk.ResetFences(ctx.device, 1, &ctx.fence) != .SUCCESS { return false }
	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd,
	}
	if vk.QueueSubmit(ctx.compute_queue, 1, &submit, ctx.fence) != .SUCCESS { return false }
	vk.WaitForFences(ctx.device, 1, &ctx.fence, true, ~u64(0))
	fmt.println("  compute: dispatch OK")

	// 5. Read back and verify.
	pixels := (^[PIXEL_COUNT][4]f32)(output.mapped)
	// The stub shader writes vec4(0.2, 0.4, 0.8, 0.0) to every pixel.
	pass := true
	for i in 0 ..< PIXEL_COUNT {
		p := pixels[i]
		if abs(p[0] - 0.2) > 0.01 || abs(p[1] - 0.4) > 0.01 || abs(p[2] - 0.8) > 0.01 {
			fmt.eprintf("  compute: pixel %d mismatch: (%.3f, %.3f, %.3f)\n", i, p[0], p[1], p[2])
			pass = false
			break
		}
	}
	if pass {
		fmt.println("  compute: readback verified OK — all pixels match expected blue")
	}
	return pass
}
