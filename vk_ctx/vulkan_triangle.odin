package vk_ctx

import "core:fmt"

import vk "vendor:vulkan"

// VulkanTriangleRenderer owns graphics resources used by the vk_smoke hello-triangle path.
VulkanTriangleRenderer :: struct {
	render_pass:         vk.RenderPass,
	pipeline_layout:     vk.PipelineLayout,
	pipeline:            vk.Pipeline,
	vertex_shader:       vk.ShaderModule,
	fragment_shader:     vk.ShaderModule,
	framebuffers:        []vk.Framebuffer,
}

create_triangle_render_pass :: proc(device: vk.Device, color_format: vk.Format) -> (vk.RenderPass, bool) {
	color_attachment := vk.AttachmentDescription {
		format         = color_format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_ref,
	}

	// External dependency for color attachment writes + layout transition to be
	// synchronized with acquire/present.
	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	rp_ci := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	render_pass: vk.RenderPass
	if vk.CreateRenderPass(device, &rp_ci, nil, &render_pass) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateRenderPass failed for triangle")
		return {}, false
	}

	return render_pass, true
}

create_triangle_pipeline_layout :: proc(device: vk.Device) -> (vk.PipelineLayout, bool) {
	ci := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}
	layout: vk.PipelineLayout
	if vk.CreatePipelineLayout(device, &ci, nil, &layout) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreatePipelineLayout failed for triangle")
		return {}, false
	}
	return layout, true
}

create_triangle_graphics_pipeline :: proc(
	device: vk.Device,
	render_pass: vk.RenderPass,
	pipeline_layout: vk.PipelineLayout,
	extent: vk.Extent2D,
	vertex_shader: vk.ShaderModule,
	fragment_shader: vk.ShaderModule,
) -> (vk.Pipeline, bool) {
	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.VERTEX},
			module = vertex_shader,
			pName  = "main",
		},
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.FRAGMENT},
			module = fragment_shader,
			pName  = "main",
		},
	}

	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(extent.width),
		height   = f32(extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}
	scissor := vk.Rect2D {
		offset = {x = 0, y = 0},
		extent = extent,
	}
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		pViewports    = &viewport,
		scissorCount  = 1,
		pScissors     = &scissor,
	}

	rasterization := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode             = .FILL,
		cullMode                = vk.CullModeFlags_NONE,
		frontFace               = .COUNTER_CLOCKWISE,
		lineWidth               = 1.0,
	}

	multisample := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}

	blend_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable    = false,
		colorWriteMask = {.R, .G, .B, .A},
	}
	color_blend := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &blend_attachment,
	}

	pipeline_ci := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = u32(len(stages)),
		pStages             = raw_data(stages[:]),
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterization,
		pMultisampleState   = &multisample,
		pColorBlendState    = &color_blend,
		layout              = pipeline_layout,
		renderPass          = render_pass,
		subpass             = 0,
	}

	pipeline: vk.Pipeline
	if vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_ci, nil, &pipeline) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateGraphicsPipelines failed for triangle")
		return {}, false
	}

	return pipeline, true
}

create_triangle_framebuffers :: proc(
	device: vk.Device,
	render_pass: vk.RenderPass,
	image_views: []vk.ImageView,
	extent: vk.Extent2D,
) -> ([]vk.Framebuffer, bool) {
	fbs := make([]vk.Framebuffer, len(image_views))
	for i in 0 ..< len(image_views) {
		attachment := image_views[i]
		fb_ci := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = render_pass,
			attachmentCount = 1,
			pAttachments    = &attachment,
			width           = extent.width,
			height          = extent.height,
			layers          = 1,
		}
		if vk.CreateFramebuffer(device, &fb_ci, nil, &fbs[i]) != .SUCCESS {
			fmt.eprintf("vk_ctx: vkCreateFramebuffer failed for image %d\n", i)
			for j in 0 ..< i {
				if fbs[j] != vk.Framebuffer(0) {
					vk.DestroyFramebuffer(device, fbs[j], nil)
					fbs[j] = {}
				}
			}
			delete(fbs)
			return nil, false
		}
	}
	return fbs, true
}

create_triangle_renderer :: proc(
	ctx: ^VulkanContext,
	sc: ^VulkanSwapchain,
	vertex_spv: []u8,
	fragment_spv: []u8,
) -> (r: VulkanTriangleRenderer, ok: bool) {
	r = {}

	render_pass, rp_ok := create_triangle_render_pass(ctx.device, sc.format)
	if !rp_ok {
		return r, false
	}
	r.render_pass = render_pass

	layout, pl_ok := create_triangle_pipeline_layout(ctx.device)
	if !pl_ok {
		destroy_triangle_renderer(ctx.device, &r)
		return r, false
	}
	r.pipeline_layout = layout

	vs, vs_ok := create_shader_module(ctx.device, vertex_spv)
	if !vs_ok {
		destroy_triangle_renderer(ctx.device, &r)
		return r, false
	}
	r.vertex_shader = vs

	fs, fs_ok := create_shader_module(ctx.device, fragment_spv)
	if !fs_ok {
		destroy_triangle_renderer(ctx.device, &r)
		return r, false
	}
	r.fragment_shader = fs

	pipeline, pipe_ok := create_triangle_graphics_pipeline(
		ctx.device,
		r.render_pass,
		r.pipeline_layout,
		sc.extent,
		r.vertex_shader,
		r.fragment_shader,
	)
	if !pipe_ok {
		destroy_triangle_renderer(ctx.device, &r)
		return r, false
	}
	r.pipeline = pipeline

	framebuffers, fb_ok := create_triangle_framebuffers(
		ctx.device,
		r.render_pass,
		sc.image_views,
		sc.extent,
	)
	if !fb_ok {
		destroy_triangle_renderer(ctx.device, &r)
		return r, false
	}
	r.framebuffers = framebuffers

	return r, true
}

destroy_triangle_renderer :: proc(device: vk.Device, r: ^VulkanTriangleRenderer) {
	if r.framebuffers != nil {
		for fb in r.framebuffers {
			if fb != vk.Framebuffer(0) {
				vk.DestroyFramebuffer(device, fb, nil)
			}
		}
		delete(r.framebuffers)
		r.framebuffers = nil
	}
	if r.pipeline != vk.Pipeline(0) {
		vk.DestroyPipeline(device, r.pipeline, nil)
		r.pipeline = {}
	}
	if r.pipeline_layout != vk.PipelineLayout(0) {
		vk.DestroyPipelineLayout(device, r.pipeline_layout, nil)
		r.pipeline_layout = {}
	}
	if r.render_pass != vk.RenderPass(0) {
		vk.DestroyRenderPass(device, r.render_pass, nil)
		r.render_pass = {}
	}
	if r.fragment_shader != vk.ShaderModule(0) {
		vk.DestroyShaderModule(device, r.fragment_shader, nil)
		r.fragment_shader = {}
	}
	if r.vertex_shader != vk.ShaderModule(0) {
		vk.DestroyShaderModule(device, r.vertex_shader, nil)
		r.vertex_shader = {}
	}
}

// swapchain_present_triangle acquires a swapchain image, records a render pass
// that draws a single triangle, submits, and presents.
swapchain_present_triangle :: proc(ctx: ^VulkanContext, sc: ^VulkanSwapchain, tri: ^VulkanTriangleRenderer) -> bool {
	vk.WaitForFences(ctx.device, 1, &ctx.fence, true, ~u64(0))
	vk.ResetFences(ctx.device, 1, &ctx.fence)

	img_idx: u32
	acq_res := vk.AcquireNextImageKHR(
		ctx.device, sc.swapchain, ~u64(0),
		ctx.semaphore_image_available, 0, &img_idx,
	)
	if acq_res == .ERROR_OUT_OF_DATE_KHR {
		return true
	}
	if acq_res != .SUCCESS && acq_res != .SUBOPTIMAL_KHR {
		return false
	}

	cmd := sc.cmd_buffers[img_idx]
	vk.ResetCommandBuffer(cmd, {})

	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if vk.BeginCommandBuffer(cmd, &begin) != .SUCCESS {
		return false
	}

	clear_value: vk.ClearValue
	clear_value.color.float32 = {0.05, 0.07, 0.10, 1.0}

	render_begin := vk.RenderPassBeginInfo {
		sType           = .RENDER_PASS_BEGIN_INFO,
		renderPass      = tri.render_pass,
		framebuffer     = tri.framebuffers[img_idx],
		renderArea      = {offset = {x = 0, y = 0}, extent = sc.extent},
		clearValueCount = 1,
		pClearValues    = &clear_value,
	}
	vk.CmdBeginRenderPass(cmd, &render_begin, .INLINE)
	vk.CmdBindPipeline(cmd, .GRAPHICS, tri.pipeline)
	vk.CmdDraw(cmd, 3, 1, 0, 0)
	vk.CmdEndRenderPass(cmd)

	if vk.EndCommandBuffer(cmd) != .SUCCESS {
		return false
	}

	wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
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
	if vk.QueueSubmit(ctx.graphics_queue, 1, &submit, ctx.fence) != .SUCCESS {
		return false
	}

	present := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &ctx.semaphore_render_finished,
		swapchainCount     = 1,
		pSwapchains        = &sc.swapchain,
		pImageIndices      = &img_idx,
	}
	pres_res := vk.QueuePresentKHR(ctx.present_queue, &present)
	if pres_res == .ERROR_OUT_OF_DATE_KHR {
		return true
	}
	if pres_res != .SUCCESS && pres_res != .SUBOPTIMAL_KHR {
		return false
	}

	return true
}
