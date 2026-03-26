// Standalone smoke test for vk_ctx: Vulkan instance/device/queues/pool, optional clear-image submit,
// and optional compute pipeline dispatch.
//
// Dependencies: system Vulkan loader (libvulkan), GLFW (linked via vendor/glfw).
// Optional: validation layers (vulkan-validation-layers / LunarG SDK) when built with -debug.
// After init, prints GPU name, limits, memory heaps, and queue families (see vk_ctx.print_vulkan_context_gpu_info).
//
// Usage:
//   ./build/vk_smoke --headless [--clear] [--compute]
//   ./build/vk_smoke --window [--platform=auto|x11|wayland] [--frames=N]
package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:terminal"
import "core:time"

import glfw "vendor:glfw"
import vk "vendor:vulkan"
import "RT_Weekend:vk_ctx"

RAYTRACE_VK_SPV :: #load("../../assets/shaders/raytrace_vk.comp.spv")
HELLO_TRIANGLE_VERT_SPV :: #load("../../assets/shaders/hello_triangle_vk.vert.spv")
HELLO_TRIANGLE_FRAG_SPV :: #load("../../assets/shaders/hello_triangle_vk.frag.spv")

main :: proc() {
	mode := "headless"
	do_clear := false
	do_compute := false
	window_platform: c.int = glfw.ANY_PLATFORM
	window_frames := 0 // 0 = run until the user closes the window.
	for arg in os.args[1:] {
		switch arg {
		case "--headless":
			mode = "headless"
		case "--window":
			mode = "window"
		case "--platform=x11":
			window_platform = glfw.PLATFORM_X11
		case "--platform=wayland":
			window_platform = glfw.PLATFORM_WAYLAND
		case "--platform=auto":
			window_platform = glfw.ANY_PLATFORM
		case "--clear":
			do_clear = true
		case "--compute":
			do_compute = true
		case:
			if strings.has_prefix(arg, "--frames=") {
				value := strings.trim_prefix(arg, "--frames=")
				n, parse_ok := strconv.parse_int(value)
				if !parse_ok || n < 0 {
					fmt.eprintf("Invalid --frames value: %s\n", value)
					os.exit(2)
				}
				window_frames = n
				continue
			}
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
		vk_ctx.print_vk_debug_config()
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
	ctx, ok := vk_ctx.vulkan_context_init_window(
		cstring("vk_smoke"),
		c.int(640), c.int(480),
		window_platform,
	)
	defer vk_ctx.vulkan_context_destroy(&ctx)
	if !ok {
		fmt.eprintln("vk_smoke: window init failed")
		os.exit(1)
	}
	fmt.println("vk_smoke: window + surface OK")
	vk_ctx.print_vk_debug_config()
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

	vert_spv := HELLO_TRIANGLE_VERT_SPV
	frag_spv := HELLO_TRIANGLE_FRAG_SPV
	tri, tri_ok := vk_ctx.create_triangle_renderer(
		&ctx,
		&sc,
		vert_spv[:],
		frag_spv[:],
	)
	defer vk_ctx.destroy_triangle_renderer(ctx.device, &tri)
	if !tri_ok {
		fmt.eprintln("vk_smoke: hello-triangle pipeline creation failed")
		os.exit(1)
	}
	fmt.println("vk_smoke: hello-triangle pipeline OK")
	pump_events := true
	if glfw.GetPlatform() == glfw.PLATFORM_WAYLAND && !terminal.is_terminal(os.stdin) {
		// Some launchers run GUI apps with stdin redirected (/dev/null), which can break
		// Wayland event handling in GLFW. Use a deterministic present loop in this case.
		pump_events = false
		if window_frames == 0 {
			window_frames = 300
		}
		fmt.printf(
			"vk_smoke: stdin is not a TTY on Wayland; presenting %d frames without PollEvents\n",
			window_frames,
		)
	}
	if window_frames > 0 {
		fmt.printf("vk_smoke: window frame budget: %d\n", window_frames)
	} else {
		fmt.println("(close window to exit)")
	}

	frame_count := 0
	for {
		if !vk_ctx.swapchain_present_triangle(&ctx, &sc, &tri) {
			fmt.eprintln("vk_smoke: triangle present failed")
			break
		}
		frame_count += 1
		if pump_events {
			glfw.PollEvents()
			if glfw.WindowShouldClose(ctx.glfw_window) {
				break
			}
		} else {
			// Keep frame pacing predictable without depending on GLFW's event loop.
			time.sleep(16 * time.Millisecond)
		}
		if window_frames > 0 && frame_count >= window_frames {
			break
		}
	}
	fmt.printf("vk_smoke: presented frames: %d\n", frame_count)
	vk.DeviceWaitIdle(ctx.device)
}

// run_compute_test exercises the full pipeline: create pipeline, allocate buffers,
// write descriptors, dispatch 1 sample, and verify a non-zero ray-traced output.
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
	vk_ctx.set_pipeline_name(ctx.device, pipeline.pipeline, "pipeline/raytrace_compute")
	vk_ctx.set_descriptor_set_name(ctx.device, pipeline.descriptor_set, "desc/raytrace")
	fmt.println("  compute: pipeline created OK")

	// 2. Allocate buffers.
	// UBO: camera uniforms (128 bytes, std140), must match GPUCameraUniforms.
	CameraUBO :: struct #packed {
		camera_center:  [3]f32, _pad0: f32,
		pixel00_loc:    [3]f32, _pad1: f32,
		pixel_delta_u:  [3]f32, _pad2: f32,
		pixel_delta_v:  [3]f32, _pad3: f32,
		defocus_disk_u: [3]f32, defocus_angle: f32,
		defocus_disk_v: [3]f32, _pad4: f32,
		width:          i32,
		height:         i32,
		max_depth:      i32,
		total_samples:  i32,
		current_sample: i32,
		_pad:           [3]i32,
		background:     [3]f32, _pad5: f32,
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

	// Empty image texture SSBO (no images).
	img_textures, s6 := vk_ctx.create_host_visible_buffer(ctx.device, ctx.physical_device, HEADER_SIZE, {.STORAGE_BUFFER})
	if !s6 { return false }
	defer vk_ctx.destroy_buffer(ctx.device, &img_textures)
	mem.copy(img_textures.mapped, &empty_hdr, int(HEADER_SIZE))

	// 3. Write descriptors.
	buffers := [8]vk_ctx.VulkanBuffer{ubo, spheres, bvh, output, quads, volumes, vol_quads, img_textures}
	vk_ctx.write_raytrace_descriptors(ctx.device, pipeline.descriptor_set, buffers)
	fmt.println("  compute: buffers + descriptors OK")

	// 4. Record and submit a compute dispatch using sync utilities.
	cmd, cmd_ok := vk_ctx.begin_one_shot(ctx.device, ctx.compute_command_pool)
	if !cmd_ok { return false }

	vk_ctx.dispatch_compute_synced(cmd, vk_ctx.DispatchSyncConfig{
		ctx          = ctx,
		pipeline     = &pipeline,
		groups_x     = u32(math.ceil(f32(W) / 8.0)),
		groups_y     = u32(math.ceil(f32(H) / 8.0)),
		groups_z     = 1,
		output_buffer = output.buffer,
		output_size   = OUT_SIZE,
		readback_host = true,
	})

	if !vk_ctx.end_one_shot_and_submit(ctx.device, ctx.compute_command_pool, ctx.compute_queue, cmd) {
		return false
	}
	fmt.println("  compute: dispatch OK (with sync barriers)")

	// 5. Read back and verify.
	pixels := (^[PIXEL_COUNT][4]f32)(output.mapped)
	// Full shader traces against an empty scene and returns background.
	pass := true
	for i in 0 ..< PIXEL_COUNT {
		p := pixels[i]
		if p[0] <= 0.0 || p[1] <= 0.0 || p[2] <= 0.0 {
			fmt.eprintf("  compute: pixel %d mismatch: (%.3f, %.3f, %.3f)\n", i, p[0], p[1], p[2])
			pass = false
			break
		}
	}
	if pass {
		fmt.println("  compute: readback verified OK — output is non-zero")
	}
	return pass
}
