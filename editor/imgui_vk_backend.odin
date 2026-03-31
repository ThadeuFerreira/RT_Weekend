package editor

// imgui_vk_backend.odin — Vulkan ImGui rendering backend.
//
// Manages a GLFW+Vulkan window, swapchain, render pass, and framebuffers
// for ImGui presentation.  Provides texture upload utilities for displaying
// Raylib offscreen renders and ray-trace pixel buffers via ImGui::Image().

import "core:c"
import "core:fmt"
import "core:mem"

import glfw "vendor:glfw"
import vk   "vendor:vulkan"
import rl   "vendor:raylib"

import imgui      "RT_Weekend:vendor/odin-imgui"
import imgui_glfw "RT_Weekend:vendor/odin-imgui/imgui_impl_glfw"
import imgui_vk   "RT_Weekend:vendor/odin-imgui/imgui_impl_vulkan"
import vk_ctx     "RT_Weekend:vk_ctx"

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

ImguiVkTexture :: struct {
	image:   vk.Image,
	memory:  vk.DeviceMemory,
	view:    vk.ImageView,
	sampler: vk.Sampler,
	ds:      vk.DescriptorSet,        // from imgui_impl_vulkan.AddTexture
	staging: vk_ctx.VulkanBuffer,     // persistently mapped host-visible
	width:   i32,
	height:  i32,
	valid:   bool,
}

// ---------------------------------------------------------------------------
// Module-private state
// ---------------------------------------------------------------------------

@(private="file")
_vk: struct {
	ctx:          vk_ctx.VulkanContext,
	sc:           vk_ctx.VulkanSwapchain,
	render_pass:  vk.RenderPass,
	framebuffers: []vk.Framebuffer,
	initialized:  bool,
}

@(private="file")
_inp: struct {
	prev_keys:  [512]bool,
	prev_mouse: [8]bool,
	wheel_y:    f32,
	prev_time:  f64,
	frame_dt:   f32,
	cursor:     glfw.CursorHandle,
}

@(private="file")
_idle_wait_timeout_s: f64

@(private="file")
_imgui_vk_loader :: proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
	if function_name == nil || user_data == nil {
		return nil
	}
	instance := (^vk.Instance)(user_data)^
	return cast(vk.ProcVoidFunction)vk.GetInstanceProcAddr(instance, function_name)
}

@(private="file")
_vk_rebind_ui_procs :: proc() {
	// vendor:vulkan uses global proc pointers; other Vulkan contexts in-process can
	// overwrite them. Rebind both instance and device procs to the UI context before
	// any WSI/swapchain operation (resize/acquire/present/surface queries).
	if _vk.ctx.instance != nil {
		vk.load_proc_addresses_instance(_vk.ctx.instance)
	}
	if _vk.ctx.device != nil {
		vk.load_proc_addresses_device(_vk.ctx.device)
	}
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

imgui_vk_init :: proc(title: cstring, width, height: i32) -> bool {
	ctx, ok := vk_ctx.vulkan_context_init_window(title, c.int(width), c.int(height))
	if !ok {
		fmt.eprintln("[imgui_vk] vulkan_context_init_window failed")
		return false
	}
	_vk.ctx = ctx

	glfw.SetWindowSizeLimits(ctx.glfw_window, 640, 360, glfw.DONT_CARE, glfw.DONT_CARE)

	fb_w, fb_h := glfw.GetFramebufferSize(ctx.glfw_window)
	sc, sc_ok := vk_ctx.create_swapchain(&_vk.ctx, u32(fb_w), u32(fb_h))
	if !sc_ok {
		fmt.eprintln("[imgui_vk] create_swapchain failed")
		vk_ctx.vulkan_context_destroy(&_vk.ctx)
		return false
	}
	_vk.sc = sc

	rp, rp_ok := vk_ctx.create_triangle_render_pass(_vk.ctx.device, sc.format)
	if !rp_ok {
		fmt.eprintln("[imgui_vk] create_render_pass failed")
		vk_ctx.destroy_swapchain(_vk.ctx.device, &_vk.sc)
		vk_ctx.vulkan_context_destroy(&_vk.ctx)
		return false
	}
	_vk.render_pass = rp

	fbs, fb_ok := vk_ctx.create_triangle_framebuffers(_vk.ctx.device, rp, sc.image_views, sc.extent)
	if !fb_ok {
		fmt.eprintln("[imgui_vk] create_framebuffers failed")
		vk.DestroyRenderPass(_vk.ctx.device, rp, nil)
		vk_ctx.destroy_swapchain(_vk.ctx.device, &_vk.sc)
		vk_ctx.vulkan_context_destroy(&_vk.ctx)
		return false
	}
	_vk.framebuffers = fbs

	// ImGui context + style
	imgui.CHECKVERSION()
	imgui.CreateContext(nil)
	io := imgui.GetIO()
	io.ConfigFlags |= {.DockingEnable, .NavEnableKeyboard}
	io.ConfigWindowsMoveFromTitleBarOnly = true
	io.IniFilename = "imgui.ini"
	imgui.StyleColorsDark(nil)
	imgui.GetStyle().WindowMinSize = imgui.Vec2{40, 20}

	// Install our scroll callback BEFORE imgui_impl_glfw so it chains.
	glfw.SetScrollCallback(ctx.glfw_window, _scroll_cb)

	// Platform backend (GLFW)
	if !imgui_glfw.InitForVulkan(ctx.glfw_window, true) {
		fmt.eprintln("[imgui_vk] imgui_impl_glfw.InitForVulkan failed")
		return false
	}

	// Renderer backend (Vulkan)
	if !imgui_vk.LoadFunctions(_imgui_vk_loader, &_vk.ctx.instance) {
		fmt.eprintln("[imgui_vk] imgui_impl_vulkan.LoadFunctions failed")
		return false
	}
	init_info := imgui_vk.InitInfo{
		Instance       = ctx.instance,
		PhysicalDevice = ctx.physical_device,
		Device         = ctx.device,
		QueueFamily    = ctx.graphics_queue_family,
		Queue          = ctx.graphics_queue,
		RenderPass     = rp,
		MinImageCount  = sc.image_count,
		ImageCount     = sc.image_count,
		MSAASamples    = ._1,
		DescriptorPoolSize = 64,
	}
	if !imgui_vk.Init(&init_info) {
		fmt.eprintln("[imgui_vk] imgui_impl_vulkan.Init failed")
		return false
	}

	_inp.prev_time = glfw.GetTime()
	_vk.initialized = true
	return true
}

imgui_vk_shutdown :: proc() {
	if !_vk.initialized { return }
	vk.DeviceWaitIdle(_vk.ctx.device)

	imgui_vk.Shutdown()
	imgui_glfw.Shutdown()
	imgui.DestroyContext(nil)

	if _inp.cursor != nil {
		glfw.DestroyCursor(_inp.cursor)
		_inp.cursor = nil
	}

	for fb in _vk.framebuffers {
		if fb != {} { vk.DestroyFramebuffer(_vk.ctx.device, fb, nil) }
	}
	delete(_vk.framebuffers)
	vk.DestroyRenderPass(_vk.ctx.device, _vk.render_pass, nil)
	vk_ctx.destroy_swapchain(_vk.ctx.device, &_vk.sc)
	vk_ctx.vulkan_context_destroy(&_vk.ctx)
	_vk.initialized = false
}

imgui_vk_should_close :: proc() -> bool {
	return bool(glfw.WindowShouldClose(_vk.ctx.glfw_window))
}

imgui_vk_set_idle_wait_timeout :: proc(timeout_s: f64) {
	next := timeout_s
	if next < 0 { next = 0 }
	_idle_wait_timeout_s = next
}

// ---------------------------------------------------------------------------
// Frame lifecycle
// ---------------------------------------------------------------------------

imgui_vk_begin_frame :: proc() {
	if _idle_wait_timeout_s > 0 {
		glfw.WaitEventsTimeout(_idle_wait_timeout_s)
	} else {
		glfw.PollEvents()
	}

	// Delta time
	now := glfw.GetTime()
	_inp.frame_dt = f32(now - _inp.prev_time)
	if _inp.frame_dt <= 0 { _inp.frame_dt = 0.0001 }
	_inp.prev_time = now

	// Match Dear ImGui + GLFW + Vulkan examples: platform, then renderer, then ImGui.
	imgui_glfw.NewFrame()
	imgui_vk.NewFrame()
	imgui.NewFrame()
}

imgui_vk_end_frame :: proc() {
	if !_vk.initialized { return }
	// ImGui: must call Render() after every NewFrame(), even if presentation fails later.
	imgui.Render()
	draw_data := imgui.GetDrawData()

	if _vk.ctx.device == nil || _vk.sc.swapchain == vk.SwapchainKHR(0) {
		fmt.eprintln("[imgui_vk] end_frame skipped: invalid device or swapchain")
		return
	}
	_vk_rebind_ui_procs()
	// vendor:vulkan stores *global* function pointers from the last vk.load_proc_addresses_device().
	// Headless GPU compute uses create_logical_device(..., nil) (no swapchain extension), so
	// GetDeviceProcAddr leaves vkAcquireNextImageKHR null and overwrites the global — breaking UI.
	// Re-bind the GLFW/swapchain device before any KHR swapchain entry points.
	vk.load_proc_addresses_device(_vk.ctx.device)

	dev := _vk.ctx.device

	// During live window resize some compositors stretch the previous swapchain image
	// before Vulkan reports OUT_OF_DATE/SUBOPTIMAL. Recreate proactively when the
	// framebuffer size diverges so UI/text stay at 1:1 instead of being scaled.
	fb_w, fb_h := glfw.GetFramebufferSize(_vk.ctx.glfw_window)
	if fb_w > 0 && fb_h > 0 {
		if u32(fb_w) != _vk.sc.extent.width || u32(fb_h) != _vk.sc.extent.height {
			_ = _recreate_swapchain()
			return
		}
	}

	// Wait for previous frame's submit to complete (fence signaled).
	if vk.WaitForFences(dev, 1, &_vk.ctx.fence, true, ~u64(0)) != .SUCCESS {
		fmt.eprintln("[imgui_vk] WaitForFences failed")
		return
	}

	// Acquire next swapchain image (do not ResetFences before this — if we return early,
	// the fence must stay signaled or the next frame will deadlock in WaitForFences).
	img_idx: u32
	acq := vk.AcquireNextImageKHR(dev, _vk.sc.swapchain, ~u64(0),
		_vk.ctx.semaphore_image_available, vk.Fence(0), &img_idx)
	if acq == .ERROR_OUT_OF_DATE_KHR {
		if !_recreate_swapchain() {
			fmt.eprintln("[imgui_vk] swapchain recreate failed after OUT_OF_DATE")
		}
		return
	}
	if acq != .SUCCESS && acq != .SUBOPTIMAL_KHR {
		fmt.eprintf("[imgui_vk] AcquireNextImageKHR failed: %v\n", acq)
		return
	}
	if int(img_idx) >= len(_vk.sc.cmd_buffers) || int(img_idx) >= len(_vk.framebuffers) {
		fmt.eprintln("[imgui_vk] AcquireNextImageKHR returned out-of-range image index")
		return
	}

	if vk.ResetFences(dev, 1, &_vk.ctx.fence) != .SUCCESS {
		fmt.eprintln("[imgui_vk] ResetFences failed")
		return
	}

	// Record commands
	cmd := _vk.sc.cmd_buffers[img_idx]
	vk.ResetCommandBuffer(cmd, {})
	begin_info := vk.CommandBufferBeginInfo{
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if vk.BeginCommandBuffer(cmd, &begin_info) != .SUCCESS {
		fmt.eprintln("[imgui_vk] BeginCommandBuffer failed")
		return
	}

	clear_val := vk.ClearValue{color = vk.ClearColorValue{float32 = {0.078, 0.078, 0.118, 1.0}}}
	rp_begin := vk.RenderPassBeginInfo{
		sType       = .RENDER_PASS_BEGIN_INFO,
		renderPass  = _vk.render_pass,
		framebuffer = _vk.framebuffers[img_idx],
		renderArea  = {extent = _vk.sc.extent},
		clearValueCount = 1,
		pClearValues    = &clear_val,
	}
	vk.CmdBeginRenderPass(cmd, &rp_begin, .INLINE)

	imgui_vk.RenderDrawData(draw_data, cmd)

	vk.CmdEndRenderPass(cmd)
	if vk.EndCommandBuffer(cmd) != .SUCCESS {
		fmt.eprintln("[imgui_vk] EndCommandBuffer failed")
		return
	}

	// Submit
	wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
	submit := vk.SubmitInfo{
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &_vk.ctx.semaphore_image_available,
		pWaitDstStageMask    = &wait_stage,
		commandBufferCount   = 1,
		pCommandBuffers      = &cmd,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &_vk.ctx.semaphore_render_finished,
	}
	if vk.QueueSubmit(_vk.ctx.graphics_queue, 1, &submit, _vk.ctx.fence) != .SUCCESS {
		fmt.eprintln("[imgui_vk] QueueSubmit failed")
		return
	}

	// Present
	sc_handle := _vk.sc.swapchain
	present := vk.PresentInfoKHR{
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &_vk.ctx.semaphore_render_finished,
		swapchainCount     = 1,
		pSwapchains        = &sc_handle,
		pImageIndices      = &img_idx,
	}
	pres := vk.QueuePresentKHR(_vk.ctx.present_queue, &present)
	if pres == .ERROR_OUT_OF_DATE_KHR || pres == .SUBOPTIMAL_KHR {
		if !_recreate_swapchain() {
			fmt.eprintln("[imgui_vk] swapchain recreate failed after present")
		}
		return
	}
	if pres != .SUCCESS {
		fmt.eprintf("[imgui_vk] QueuePresentKHR failed: %v\n", pres)
		return
	}

	// Save key/mouse state for edge detection
	_input_end_frame()

	// Reset per-frame accumulators
	_inp.wheel_y = 0
}

// ---------------------------------------------------------------------------
// Swapchain recreation (window resize)
// ---------------------------------------------------------------------------

@(private="file")
_recreate_swapchain :: proc() -> bool {
	_vk_rebind_ui_procs()
	w, h := glfw.GetFramebufferSize(_vk.ctx.glfw_window)
	for w == 0 || h == 0 {
		glfw.WaitEvents()
		w, h = glfw.GetFramebufferSize(_vk.ctx.glfw_window)
	}
	if vk.DeviceWaitIdle(_vk.ctx.device) != .SUCCESS {
		return false
	}

	for fb in _vk.framebuffers {
		if fb != {} { vk.DestroyFramebuffer(_vk.ctx.device, fb, nil) }
	}
	delete(_vk.framebuffers)
	vk_ctx.destroy_swapchain(_vk.ctx.device, &_vk.sc)

	sc, ok := vk_ctx.create_swapchain(&_vk.ctx, u32(w), u32(h))
	if !ok {
		fmt.eprintln("[imgui_vk] swapchain recreation failed")
		_vk.sc = {}
		return false
	}
	_vk.sc = sc

	fbs, fb_ok := vk_ctx.create_triangle_framebuffers(_vk.ctx.device, _vk.render_pass, sc.image_views, sc.extent)
	if !fb_ok {
		fmt.eprintln("[imgui_vk] framebuffer recreation failed")
		vk_ctx.destroy_swapchain(_vk.ctx.device, &_vk.sc)
		_vk.sc = {}
		return false
	}
	_vk.framebuffers = fbs

	imgui_vk.SetMinImageCount(sc.image_count)
	return true
}

// ---------------------------------------------------------------------------
// Texture management
// ---------------------------------------------------------------------------

imgui_vk_create_texture :: proc(width, height: i32) -> (tex: ImguiVkTexture, ok: bool) {
	dev  := _vk.ctx.device
	phys := _vk.ctx.physical_device
	size := vk.DeviceSize(width * height * 4)

	// Staging buffer (persistently mapped)
	staging, s_ok := vk_ctx.create_host_visible_buffer(dev, phys, size, {.TRANSFER_SRC})
	if !s_ok { return tex, false }

	// Image — sRGB: readback stores display-ready (gamma-encoded) RGBA bytes; UNORM would
	// treat them as linear and the sRGB swapchain pass makes mid-tones too bright.
	img_ci := vk.ImageCreateInfo{
		sType       = .IMAGE_CREATE_INFO,
		imageType   = .D2,
		format      = .R8G8B8A8_SRGB,
		extent      = {u32(width), u32(height), 1},
		mipLevels   = 1,
		arrayLayers = 1,
		samples     = {._1},
		tiling      = .OPTIMAL,
		usage       = {.SAMPLED, .TRANSFER_DST},
		initialLayout = .UNDEFINED,
	}
	image: vk.Image
	if vk.CreateImage(dev, &img_ci, nil, &image) != .SUCCESS {
		vk_ctx.destroy_buffer(dev, &staging)
		return tex, false
	}

	mem_req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(dev, image, &mem_req)
	mem_type, mt_ok := vk_ctx.find_memory_type(phys, mem_req.memoryTypeBits, {.DEVICE_LOCAL})
	if !mt_ok {
		vk.DestroyImage(dev, image, nil)
		vk_ctx.destroy_buffer(dev, &staging)
		return tex, false
	}

	memory: vk.DeviceMemory
	alloc := vk.MemoryAllocateInfo{
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_req.size,
		memoryTypeIndex = mem_type,
	}
	if vk.AllocateMemory(dev, &alloc, nil, &memory) != .SUCCESS {
		vk.DestroyImage(dev, image, nil)
		vk_ctx.destroy_buffer(dev, &staging)
		return tex, false
	}
	vk.BindImageMemory(dev, image, memory, 0)

	// Image view
	view: vk.ImageView
	view_ci := vk.ImageViewCreateInfo{
		sType    = .IMAGE_VIEW_CREATE_INFO,
		image    = image,
		viewType = .D2,
		format   = .R8G8B8A8_SRGB,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	if vk.CreateImageView(dev, &view_ci, nil, &view) != .SUCCESS {
		vk.FreeMemory(dev, memory, nil)
		vk.DestroyImage(dev, image, nil)
		vk_ctx.destroy_buffer(dev, &staging)
		return tex, false
	}

	// Sampler
	sampler: vk.Sampler
	samp_ci := vk.SamplerCreateInfo{
		sType        = .SAMPLER_CREATE_INFO,
		magFilter    = .LINEAR,
		minFilter    = .LINEAR,
		addressModeU = .CLAMP_TO_EDGE,
		addressModeV = .CLAMP_TO_EDGE,
		addressModeW = .CLAMP_TO_EDGE,
	}
	if vk.CreateSampler(dev, &samp_ci, nil, &sampler) != .SUCCESS {
		vk.DestroyImageView(dev, view, nil)
		vk.FreeMemory(dev, memory, nil)
		vk.DestroyImage(dev, image, nil)
		vk_ctx.destroy_buffer(dev, &staging)
		return tex, false
	}

	// Transition to SHADER_READ_ONLY so AddTexture has a valid layout.
	_transition_image_layout(image, .UNDEFINED, .SHADER_READ_ONLY_OPTIMAL)

	// Register with ImGui
	ds := imgui_vk.AddTexture(sampler, view, .SHADER_READ_ONLY_OPTIMAL)

	return ImguiVkTexture{
		image   = image,
		memory  = memory,
		view    = view,
		sampler = sampler,
		ds      = ds,
		staging = staging,
		width   = width,
		height  = height,
		valid   = true,
	}, true
}

imgui_vk_update_texture :: proc(tex: ^ImguiVkTexture, pixels: rawptr) {
	if !tex.valid { return }
	dev  := _vk.ctx.device
	size := int(tex.width * tex.height * 4)

	mem.copy(tex.staging.mapped, pixels, size)

	cmd, cmd_ok := vk_ctx.begin_one_shot(dev, _vk.ctx.command_pool)
	if !cmd_ok { return }

	// SHADER_READ_ONLY → TRANSFER_DST
	barrier1 := vk.ImageMemoryBarrier{
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {.SHADER_READ},
		dstAccessMask       = {.TRANSFER_WRITE},
		oldLayout           = .SHADER_READ_ONLY_OPTIMAL,
		newLayout           = .TRANSFER_DST_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = tex.image,
		subresourceRange    = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	vk.CmdPipelineBarrier(cmd, {.FRAGMENT_SHADER}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier1)

	// Copy staging → image
	region := vk.BufferImageCopy{
		imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		imageExtent      = {u32(tex.width), u32(tex.height), 1},
	}
	vk.CmdCopyBufferToImage(cmd, tex.staging.buffer, tex.image, .TRANSFER_DST_OPTIMAL, 1, &region)

	// TRANSFER_DST → SHADER_READ_ONLY
	barrier2 := vk.ImageMemoryBarrier{
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {.TRANSFER_WRITE},
		dstAccessMask       = {.SHADER_READ},
		oldLayout           = .TRANSFER_DST_OPTIMAL,
		newLayout           = .SHADER_READ_ONLY_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = tex.image,
		subresourceRange    = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier2)

	vk_ctx.end_one_shot_and_submit(dev, _vk.ctx.command_pool, _vk.ctx.graphics_queue, cmd)
}

imgui_vk_destroy_texture :: proc(tex: ^ImguiVkTexture) {
	if !tex.valid { return }
	dev := _vk.ctx.device
	vk.DeviceWaitIdle(dev)
	imgui_vk.RemoveTexture(tex.ds)
	vk.DestroySampler(dev, tex.sampler, nil)
	vk.DestroyImageView(dev, tex.view, nil)
	vk.FreeMemory(dev, tex.memory, nil)
	vk.DestroyImage(dev, tex.image, nil)
	vk_ctx.destroy_buffer(dev, &tex.staging)
	tex^ = {}
}

imgui_vk_texture_id :: proc(tex: ^ImguiVkTexture) -> imgui.TextureID {
	if !tex.valid { return {} }
	return transmute(imgui.TextureID)tex.ds
}

// imgui_vk_ensure_texture resizes the Vulkan texture if dimensions changed.
// Returns false only on allocation failure.
imgui_vk_ensure_texture :: proc(tex: ^ImguiVkTexture, w, h: i32) -> bool {
	if tex.valid && tex.width == w && tex.height == h { return true }
	if tex.valid { imgui_vk_destroy_texture(tex) }
	t, ok := imgui_vk_create_texture(w, h)
	if !ok { return false }
	tex^ = t
	return true
}

// ---------------------------------------------------------------------------
// Image layout transition helper
// ---------------------------------------------------------------------------

@(private="file")
_transition_image_layout :: proc(image: vk.Image, old_layout, new_layout: vk.ImageLayout) {
	cmd, ok := vk_ctx.begin_one_shot(_vk.ctx.device, _vk.ctx.command_pool)
	if !ok { return }

	src_access: vk.AccessFlags
	dst_access: vk.AccessFlags
	src_stage:  vk.PipelineStageFlags
	dst_stage:  vk.PipelineStageFlags

	if old_layout == .UNDEFINED && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		dst_access = {.SHADER_READ}
		src_stage  = {.TOP_OF_PIPE}
		dst_stage  = {.FRAGMENT_SHADER}
	} else if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
		dst_access = {.TRANSFER_WRITE}
		src_stage  = {.TOP_OF_PIPE}
		dst_stage  = {.TRANSFER}
	}

	barrier := vk.ImageMemoryBarrier{
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = src_access,
		dstAccessMask       = dst_access,
		oldLayout           = old_layout,
		newLayout           = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = image,
		subresourceRange    = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	vk.CmdPipelineBarrier(cmd, src_stage, dst_stage, {}, 0, nil, 0, nil, 1, &barrier)

	vk_ctx.end_one_shot_and_submit(_vk.ctx.device, _vk.ctx.command_pool, _vk.ctx.graphics_queue, cmd)
}

// ---------------------------------------------------------------------------
// Input helpers — package-private, used by other editor files
// ---------------------------------------------------------------------------

// Scroll callback (GLFW "c" calling convention).
@(private="file")
_scroll_cb :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	_inp.wheel_y += f32(yoffset)
}

// Save current frame key/mouse state for edge detection next frame.
@(private="file")
_glfw_key_is_queryable :: proc(key: int) -> bool {
	if key >= int(glfw.KEY_SPACE) && key <= int(glfw.KEY_WORLD_2) { return true }
	if key >= int(glfw.KEY_ESCAPE) && key <= int(glfw.KEY_LAST) { return true }
	return false
}

// Save current frame key/mouse state for edge detection next frame.
@(private="file")
_input_end_frame :: proc() {
	win := _vk.ctx.glfw_window
	for i in 0..<len(_inp.prev_keys) {
		// GLFW key enums are sparse; only query documented key ranges.
		if _glfw_key_is_queryable(i) {
			_inp.prev_keys[i] = glfw.GetKey(win, c.int(i)) == glfw.PRESS
		} else {
			_inp.prev_keys[i] = false
		}
	}
	for i in 0..<8 {
		_inp.prev_mouse[i] = glfw.GetMouseButton(win, c.int(i)) == glfw.PRESS
	}
}

vk_is_key_down :: proc(key: c.int) -> bool {
	if !_glfw_key_is_queryable(int(key)) { return false }
	return glfw.GetKey(_vk.ctx.glfw_window, key) == glfw.PRESS
}

vk_is_key_pressed :: proc(key: c.int) -> bool {
	if !_glfw_key_is_queryable(int(key)) { return false }
	down := glfw.GetKey(_vk.ctx.glfw_window, key) == glfw.PRESS
	return down && !_inp.prev_keys[key]
}

vk_is_mouse_down :: proc(button: c.int) -> bool {
	return glfw.GetMouseButton(_vk.ctx.glfw_window, button) == glfw.PRESS
}

vk_is_mouse_pressed :: proc(button: c.int) -> bool {
	if button < 0 || button >= 8 { return false }
	down := glfw.GetMouseButton(_vk.ctx.glfw_window, button) == glfw.PRESS
	return down && !_inp.prev_mouse[button]
}

vk_is_mouse_released :: proc(button: c.int) -> bool {
	if button < 0 || button >= 8 { return false }
	down := glfw.GetMouseButton(_vk.ctx.glfw_window, button) == glfw.PRESS
	return !down && _inp.prev_mouse[button]
}

vk_get_mouse_pos :: proc() -> rl.Vector2 {
	x, y := glfw.GetCursorPos(_vk.ctx.glfw_window)
	return rl.Vector2{f32(x), f32(y)}
}

vk_get_wheel_delta :: proc() -> f32 {
	return _inp.wheel_y
}

vk_get_frame_time :: proc() -> f32 {
	return _inp.frame_dt
}

vk_get_window_size :: proc() -> (i32, i32) {
	w, h := glfw.GetWindowSize(_vk.ctx.glfw_window)
	return i32(w), i32(h)
}

// CursorShape mirrors Raylib's MouseCursor enum values used in the editor.
CursorShape :: enum {
	Default,
	ResizeEW,
	ResizeNS,
	ResizeAll,
	Crosshair,
}

vk_set_cursor :: proc(shape: CursorShape) {
	glfw_shape: c.int
	switch shape {
	case .Default:   glfw_shape = glfw.ARROW_CURSOR
	case .ResizeEW:  glfw_shape = glfw.RESIZE_EW_CURSOR
	case .ResizeNS:  glfw_shape = glfw.RESIZE_NS_CURSOR
	case .ResizeAll: glfw_shape = glfw.RESIZE_ALL_CURSOR
	case .Crosshair: glfw_shape = glfw.CROSSHAIR_CURSOR
	}

	if _inp.cursor != nil {
		glfw.DestroyCursor(_inp.cursor)
	}
	_inp.cursor = glfw.CreateStandardCursor(glfw_shape)
	glfw.SetCursor(_vk.ctx.glfw_window, _inp.cursor)
}
