package vk_ctx

import "core:fmt"

import vk "vendor:vulkan"

// vulkan_context_init_headless creates an instance without a window or surface (GLFW is used only
// to load Vulkan entry points). Suitable for offscreen / compute-only work.
//
// use_null_platform=true is ideal for standalone headless tools.
// use_null_platform=false avoids forcing GLFW's null platform in GUI apps that share the process.
vulkan_context_init_headless :: proc(use_null_platform := true, use_glfw_loader := true) -> (ctx: VulkanContext, ok: bool) {
	ctx = {}
	if use_glfw_loader {
		if !vk_load_vulkan(headless = use_null_platform) {
			fmt.eprintln("vk_ctx: vk_load_vulkan failed")
			return ctx, false
		}
		ctx.glfw_owned = true
	} else {
		if !vk_load_vulkan_direct() {
			fmt.eprintln("vk_ctx: vk_load_vulkan_direct failed")
			return ctx, false
		}
		ctx.glfw_owned = false
	}

	use_validation := VK_VALIDATION && validation_layer_available()

	exts: [dynamic]cstring
	defer delete(exts)
	if use_validation {
		append_cstring_unique(&exts, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}
	inst, inst_ok := create_instance(cstring("vk_ctx headless"), exts[:], use_validation)
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

	phys, gfam, pfam, picked := pick_physical_device(inst, vk.SurfaceKHR(0))
	if !picked {
		fmt.eprintln("vk_ctx: no suitable physical device")
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
	dev, dev_ok := create_logical_device(phys, families[:], nil)
	if !dev_ok {
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

find_memory_type :: proc(
	phys: vk.PhysicalDevice,
	type_filter: u32,
	props_wanted: vk.MemoryPropertyFlags,
) -> (u32, bool) {
	mem_props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(phys, &mem_props)
	for i in 0 ..< mem_props.memoryTypeCount {
		if (type_filter & (u32(1) << u32(i))) == 0 {
			continue
		}
		if (mem_props.memoryTypes[i].propertyFlags & props_wanted) == props_wanted {
			return u32(i), true
		}
	}
	return 0, false
}

// headless_submit_clear_color_test records a one-shot command buffer that transitions a small 2D
// image and clears it, then waits on the context fence. Use to verify queue submission.
headless_submit_clear_color_test :: proc(ctx: ^VulkanContext) -> bool {
	W :: u32(64)
	H :: u32(64)

	img_info := vk.ImageCreateInfo {
		sType     = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format    = .R8G8B8A8_UNORM,
		extent    = {width = W, height = H, depth = 1},
		mipLevels = 1,
		arrayLayers = 1,
		samples   = {._1},
		tiling    = .OPTIMAL,
		usage     = {.TRANSFER_DST},
		sharingMode = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	image: vk.Image
	if vk.CreateImage(ctx.device, &img_info, nil, &image) != .SUCCESS {
		return false
	}
	defer vk.DestroyImage(ctx.device, image, nil)

	mem_req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(ctx.device, image, &mem_req)

	mem_type, mt_ok := find_memory_type(
		ctx.physical_device,
		mem_req.memoryTypeBits,
		{.DEVICE_LOCAL},
	)
	if !mt_ok {
		return false
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_req.size,
		memoryTypeIndex = mem_type,
	}
	mem: vk.DeviceMemory
	if vk.AllocateMemory(ctx.device, &alloc_info, nil, &mem) != .SUCCESS {
		return false
	}
	defer vk.FreeMemory(ctx.device, mem, nil)

	if vk.BindImageMemory(ctx.device, image, mem, 0) != .SUCCESS {
		return false
	}

	cmd_alloc := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	cmd: vk.CommandBuffer
	if vk.AllocateCommandBuffers(ctx.device, &cmd_alloc, &cmd) != .SUCCESS {
		return false
	}
	defer vk.FreeCommandBuffers(ctx.device, ctx.command_pool, 1, &cmd)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if vk.BeginCommandBuffer(cmd, &begin_info) != .SUCCESS {
		return false
	}

	subresource := vk.ImageSubresourceRange {
		aspectMask     = {.COLOR},
		baseMipLevel   = 0,
		levelCount     = 1,
		baseArrayLayer = 0,
		layerCount     = 1,
	}
	barrier_to_transfer := vk.ImageMemoryBarrier {
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {},
		dstAccessMask       = {.TRANSFER_WRITE},
		oldLayout           = .UNDEFINED,
		newLayout           = .TRANSFER_DST_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = image,
		subresourceRange    = subresource,
	}
	vk.CmdPipelineBarrier(
		cmd,
		{.TOP_OF_PIPE},
		{.TRANSFER},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier_to_transfer,
	)

	clear_val: vk.ClearColorValue
	clear_val.float32 = {0.2, 0.4, 0.8, 1.0}
	vk.CmdClearColorImage(
		cmd,
		image,
		.TRANSFER_DST_OPTIMAL,
		&clear_val,
		1,
		&subresource,
	)

	if vk.EndCommandBuffer(cmd) != .SUCCESS {
		return false
	}

	if vk.ResetFences(ctx.device, 1, &ctx.fence) != .SUCCESS {
		return false
	}

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd,
	}
	if vk.QueueSubmit(ctx.graphics_queue, 1, &submit_info, ctx.fence) != .SUCCESS {
		return false
	}

	if vk.WaitForFences(ctx.device, 1, &ctx.fence, true, ~u64(0)) != .SUCCESS {
		return false
	}

	return true
}
