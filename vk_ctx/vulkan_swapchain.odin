package vk_ctx

import "core:fmt"

import vk "vendor:vulkan"

// VulkanSwapchain holds swapchain handles and per-image command buffers for a
// window-mode VulkanContext.
VulkanSwapchain :: struct {
	swapchain:    vk.SwapchainKHR,
	format:       vk.Format,
	extent:       vk.Extent2D,
	images:       []vk.Image,
	image_views:  []vk.ImageView,
	cmd_buffers:  []vk.CommandBuffer,
	image_count:  u32,
}

// create_swapchain queries surface capabilities and creates a swapchain with FIFO
// present mode (always supported). Also allocates one command buffer per image.
create_swapchain :: proc(ctx: ^VulkanContext, width, height: u32) -> (sc: VulkanSwapchain, ok: bool) {
	sc = {}

	// Query surface capabilities.
	caps: vk.SurfaceCapabilitiesKHR
	if vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.physical_device, ctx.surface, &caps) != .SUCCESS {
		fmt.eprintln("vk_ctx: GetPhysicalDeviceSurfaceCapabilitiesKHR failed")
		return sc, false
	}

	// Pick format: prefer B8G8R8A8_SRGB + SRGB_NONLINEAR, fall back to first available.
	fmt_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.physical_device, ctx.surface, &fmt_count, nil)
	if fmt_count == 0 {
		fmt.eprintln("vk_ctx: no surface formats")
		return sc, false
	}
	formats := make([]vk.SurfaceFormatKHR, fmt_count, context.temp_allocator)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.physical_device, ctx.surface, &fmt_count, raw_data(formats))

	chosen_fmt := formats[0]
	for f in formats {
		if f.format == .B8G8R8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR {
			chosen_fmt = f
			break
		}
	}
	sc.format = chosen_fmt.format

	// Extent.
	if caps.currentExtent.width != max(u32) {
		sc.extent = caps.currentExtent
	} else {
		sc.extent = {
			width  = clamp(width, caps.minImageExtent.width, caps.maxImageExtent.width),
			height = clamp(height, caps.minImageExtent.height, caps.maxImageExtent.height),
		}
	}

	// Image count: prefer min+1, capped by max (0 = unlimited).
	img_count := caps.minImageCount + 1
	if caps.maxImageCount > 0 && img_count > caps.maxImageCount {
		img_count = caps.maxImageCount
	}

	ci := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = ctx.surface,
		minImageCount    = img_count,
		imageFormat      = chosen_fmt.format,
		imageColorSpace  = chosen_fmt.colorSpace,
		imageExtent      = sc.extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT, .TRANSFER_DST},
		imageSharingMode = .EXCLUSIVE,
		preTransform     = caps.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = .FIFO,
		clipped          = true,
	}

	// If graphics and present families differ, use concurrent sharing.
	families := [2]u32{ctx.graphics_queue_family, ctx.present_queue_family}
	if ctx.graphics_queue_family != ctx.present_queue_family {
		ci.imageSharingMode = .CONCURRENT
		ci.queueFamilyIndexCount = 2
		ci.pQueueFamilyIndices = raw_data(families[:])
	}

	if vk.CreateSwapchainKHR(ctx.device, &ci, nil, &sc.swapchain) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateSwapchainKHR failed")
		return sc, false
	}

	// Get swapchain images.
	vk.GetSwapchainImagesKHR(ctx.device, sc.swapchain, &sc.image_count, nil)
	sc.images = make([]vk.Image, sc.image_count)
	vk.GetSwapchainImagesKHR(ctx.device, sc.swapchain, &sc.image_count, raw_data(sc.images))

	// Create image views.
	sc.image_views = make([]vk.ImageView, sc.image_count)
	for i in 0 ..< sc.image_count {
		iv_ci := vk.ImageViewCreateInfo {
			sType    = .IMAGE_VIEW_CREATE_INFO,
			image    = sc.images[i],
			viewType = .D2,
			format   = sc.format,
			components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = {
				aspectMask     = {.COLOR},
				baseMipLevel   = 0,
				levelCount     = 1,
				baseArrayLayer = 0,
				layerCount     = 1,
			},
		}
		if vk.CreateImageView(ctx.device, &iv_ci, nil, &sc.image_views[i]) != .SUCCESS {
			fmt.eprintf("vk_ctx: vkCreateImageView failed for image %d\n", i)
			destroy_swapchain(ctx.device, &sc)
			return sc, false
		}
	}

	// Allocate command buffers (one per image).
	sc.cmd_buffers = make([]vk.CommandBuffer, sc.image_count)
	cmd_ai := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = sc.image_count,
	}
	if vk.AllocateCommandBuffers(ctx.device, &cmd_ai, raw_data(sc.cmd_buffers)) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkAllocateCommandBuffers failed for swapchain")
		destroy_swapchain(ctx.device, &sc)
		return sc, false
	}

	return sc, true
}

// destroy_swapchain destroys image views, frees command buffers, and destroys the swapchain.
// Does NOT free sc.images (owned by the swapchain).
destroy_swapchain :: proc(device: vk.Device, sc: ^VulkanSwapchain) {
	if sc.image_views != nil {
		for iv in sc.image_views {
			if iv != vk.ImageView(0) {
				vk.DestroyImageView(device, iv, nil)
			}
		}
		delete(sc.image_views)
		sc.image_views = nil
	}
	if sc.images != nil {
		delete(sc.images)
		sc.images = nil
	}
	if sc.cmd_buffers != nil {
		// Command buffers are freed when the pool is destroyed or reset.
		delete(sc.cmd_buffers)
		sc.cmd_buffers = nil
	}
	if sc.swapchain != vk.SwapchainKHR(0) {
		vk.DestroySwapchainKHR(device, sc.swapchain, nil)
		sc.swapchain = {}
	}
}

// swapchain_present_clear acquires a swapchain image, records a clear-color command,
// submits, and presents. Returns false on fatal error; SUBOPTIMAL is tolerated.
swapchain_present_clear :: proc(ctx: ^VulkanContext, sc: ^VulkanSwapchain, r, g, b: f32) -> bool {
	// Wait for previous frame's fence.
	vk.WaitForFences(ctx.device, 1, &ctx.fence, true, ~u64(0))
	vk.ResetFences(ctx.device, 1, &ctx.fence)

	// Acquire next image.
	img_idx: u32
	acq_res := vk.AcquireNextImageKHR(
		ctx.device, sc.swapchain, ~u64(0),
		ctx.semaphore_image_available, 0, &img_idx,
	)
	if acq_res != .SUCCESS && acq_res != .SUBOPTIMAL_KHR {
		return false
	}

	cmd := sc.cmd_buffers[img_idx]
	vk.ResetCommandBuffer(cmd, {})

	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if vk.BeginCommandBuffer(cmd, &begin) != .SUCCESS { return false }

	// Transition image: UNDEFINED → TRANSFER_DST_OPTIMAL.
	subresource := vk.ImageSubresourceRange {
		aspectMask     = {.COLOR},
		baseMipLevel   = 0,
		levelCount     = 1,
		baseArrayLayer = 0,
		layerCount     = 1,
	}
	barrier_to_clear := vk.ImageMemoryBarrier {
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {},
		dstAccessMask       = {.TRANSFER_WRITE},
		oldLayout           = .UNDEFINED,
		newLayout           = .TRANSFER_DST_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = sc.images[img_idx],
		subresourceRange    = subresource,
	}
	vk.CmdPipelineBarrier(cmd, {.TOP_OF_PIPE}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier_to_clear)

	// Clear to color.
	clear_val: vk.ClearColorValue
	clear_val.float32 = {r, g, b, 1.0}
	vk.CmdClearColorImage(cmd, sc.images[img_idx], .TRANSFER_DST_OPTIMAL, &clear_val, 1, &subresource)

	// Transition image: TRANSFER_DST_OPTIMAL → PRESENT_SRC_KHR.
	barrier_to_present := vk.ImageMemoryBarrier {
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {.TRANSFER_WRITE},
		dstAccessMask       = {},
		oldLayout           = .TRANSFER_DST_OPTIMAL,
		newLayout           = .PRESENT_SRC_KHR,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = sc.images[img_idx],
		subresourceRange    = subresource,
	}
	vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.BOTTOM_OF_PIPE}, {}, 0, nil, 0, nil, 1, &barrier_to_present)

	if vk.EndCommandBuffer(cmd) != .SUCCESS { return false }

	// Submit.
	wait_stage := vk.PipelineStageFlags{.TRANSFER}
	submit := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &ctx.semaphore_image_available,
		pWaitDstStageMask    = &wait_stage,
		commandBufferCount   = 1,
		pCommandBuffers      = &cmd,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &ctx.semaphore_render_finished,
	}
	if vk.QueueSubmit(ctx.graphics_queue, 1, &submit, ctx.fence) != .SUCCESS { return false }

	// Present.
	present := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &ctx.semaphore_render_finished,
		swapchainCount     = 1,
		pSwapchains        = &sc.swapchain,
		pImageIndices      = &img_idx,
	}
	pres_res := vk.QueuePresentKHR(ctx.present_queue, &present)
	if pres_res != .SUCCESS && pres_res != .SUBOPTIMAL_KHR {
		return false
	}

	return true
}
