package vk_ctx

import "core:fmt"

import vk "vendor:vulkan"

// ─── Compute command pool ────────────────────────────────────────────────────
//
// When the compute queue family differs from the graphics family, a separate
// command pool is required.  create_compute_command_pool creates one; the pool
// handle is stored in VulkanContext.compute_command_pool and destroyed by
// vulkan_context_destroy.

create_compute_command_pool :: proc(ctx: ^VulkanContext) -> bool {
	// If compute uses the same family as graphics, reuse the existing pool.
	if ctx.compute_queue_family == ctx.graphics_queue_family {
		ctx.compute_command_pool = ctx.command_pool
		return true
	}
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = ctx.compute_queue_family,
	}
	if vk.CreateCommandPool(ctx.device, &pool_info, nil, &ctx.compute_command_pool) != .SUCCESS {
		fmt.eprintln("vk_ctx: compute command pool creation failed")
		return false
	}
	return true
}

// ─── One-shot command helpers ────────────────────────────────────────────────

// begin_one_shot allocates and begins a primary command buffer for single-use
// recording.  Use with end_one_shot_and_submit.
begin_one_shot :: proc(
	device: vk.Device,
	pool: vk.CommandPool,
) -> (cmd: vk.CommandBuffer, ok: bool) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	if vk.AllocateCommandBuffers(device, &alloc_info, &cmd) != .SUCCESS {
		return {}, false
	}
	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if vk.BeginCommandBuffer(cmd, &begin) != .SUCCESS {
		vk.FreeCommandBuffers(device, pool, 1, &cmd)
		return {}, false
	}
	return cmd, true
}

// end_one_shot_and_submit ends the command buffer, submits it to the given
// queue, waits for completion via a temporary fence, and frees the buffer.
end_one_shot_and_submit :: proc(
	device: vk.Device,
	pool: vk.CommandPool,
	queue: vk.Queue,
	cmd: vk.CommandBuffer,
) -> bool {
	cmd_mut := cmd
	if vk.EndCommandBuffer(cmd) != .SUCCESS {
		vk.FreeCommandBuffers(device, pool, 1, &cmd_mut)
		return false
	}
	fence_ci := vk.FenceCreateInfo { sType = .FENCE_CREATE_INFO }
	fence: vk.Fence
	if vk.CreateFence(device, &fence_ci, nil, &fence) != .SUCCESS {
		vk.FreeCommandBuffers(device, pool, 1, &cmd_mut)
		return false
	}
	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd_mut,
	}
	res := vk.QueueSubmit(queue, 1, &submit, fence)
	if res != .SUCCESS {
		vk.DestroyFence(device, fence, nil)
		vk.FreeCommandBuffers(device, pool, 1, &cmd_mut)
		return false
	}
	vk.WaitForFences(device, 1, &fence, true, ~u64(0))
	vk.DestroyFence(device, fence, nil)
	vk.FreeCommandBuffers(device, pool, 1, &cmd_mut)
	return true
}

// ─── Buffer memory barriers ─────────────────────────────────────────────────

// barrier_compute_write_to_host_read inserts a pipeline barrier that makes
// compute-shader SSBO writes visible to host reads (e.g. vkMapMemory / CPU
// readback).  Use after the last dispatch before readback.
barrier_compute_write_to_host_read :: proc(cmd: vk.CommandBuffer, buffer: vk.Buffer, size: vk.DeviceSize) {
	barrier := vk.BufferMemoryBarrier {
		sType               = .BUFFER_MEMORY_BARRIER,
		srcAccessMask       = {.SHADER_WRITE},
		dstAccessMask       = {.HOST_READ},
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		buffer              = buffer,
		offset              = 0,
		size                = size,
	}
	vk.CmdPipelineBarrier(
		cmd,
		{.COMPUTE_SHADER},  // src stage
		{.HOST},             // dst stage
		{},                  // dependency flags
		0, nil,              // memory barriers
		1, &barrier,         // buffer barriers
		0, nil,              // image barriers
	)
}

// barrier_compute_write_to_compute_read inserts a barrier between two compute
// dispatches on the same queue so that SSBO writes from the first dispatch are
// visible to shader reads in the next.  Essential for multi-sample accumulation.
barrier_compute_write_to_compute_read :: proc(cmd: vk.CommandBuffer, buffer: vk.Buffer, size: vk.DeviceSize) {
	barrier := vk.BufferMemoryBarrier {
		sType               = .BUFFER_MEMORY_BARRIER,
		srcAccessMask       = {.SHADER_WRITE},
		dstAccessMask       = {.SHADER_READ, .SHADER_WRITE},
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		buffer              = buffer,
		offset              = 0,
		size                = size,
	}
	vk.CmdPipelineBarrier(
		cmd,
		{.COMPUTE_SHADER},  // src stage
		{.COMPUTE_SHADER},  // dst stage
		{},
		0, nil,
		1, &barrier,
		0, nil,
	)
}

// barrier_compute_write_to_transfer_read inserts a barrier so that compute-shader
// SSBO writes are visible to a subsequent transfer (vkCmdCopyBuffer) for readback
// to a staging buffer or presentation path.
barrier_compute_write_to_transfer_read :: proc(cmd: vk.CommandBuffer, buffer: vk.Buffer, size: vk.DeviceSize) {
	barrier := vk.BufferMemoryBarrier {
		sType               = .BUFFER_MEMORY_BARRIER,
		srcAccessMask       = {.SHADER_WRITE},
		dstAccessMask       = {.TRANSFER_READ},
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		buffer              = buffer,
		offset              = 0,
		size                = size,
	}
	vk.CmdPipelineBarrier(
		cmd,
		{.COMPUTE_SHADER},
		{.TRANSFER},
		{},
		0, nil,
		1, &barrier,
		0, nil,
	)
}

// barrier_transfer_write_to_host_read inserts a barrier so that a transfer write
// (vkCmdCopyBuffer into a staging buffer) is visible to host reads.
barrier_transfer_write_to_host_read :: proc(cmd: vk.CommandBuffer, buffer: vk.Buffer, size: vk.DeviceSize) {
	barrier := vk.BufferMemoryBarrier {
		sType               = .BUFFER_MEMORY_BARRIER,
		srcAccessMask       = {.TRANSFER_WRITE},
		dstAccessMask       = {.HOST_READ},
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		buffer              = buffer,
		offset              = 0,
		size                = size,
	}
	vk.CmdPipelineBarrier(
		cmd,
		{.TRANSFER},
		{.HOST},
		{},
		0, nil,
		1, &barrier,
		0, nil,
	)
}

// ─── Queue family ownership transfers ────────────────────────────────────────
//
// When the compute and graphics queue families differ, exclusive-mode buffers
// require an ownership transfer: a release barrier on the source queue followed
// by an acquire barrier on the destination queue.

// barrier_queue_release records a release barrier that transfers ownership of a
// buffer from src_family to dst_family.  Record into a command buffer submitted
// on the source queue.
barrier_queue_release :: proc(
	cmd: vk.CommandBuffer,
	buffer: vk.Buffer,
	size: vk.DeviceSize,
	src_access: vk.AccessFlags,
	src_stage: vk.PipelineStageFlags,
	src_family: u32,
	dst_family: u32,
) {
	if src_family == dst_family { return }
	barrier := vk.BufferMemoryBarrier {
		sType               = .BUFFER_MEMORY_BARRIER,
		srcAccessMask       = src_access,
		dstAccessMask       = {},
		srcQueueFamilyIndex = src_family,
		dstQueueFamilyIndex = dst_family,
		buffer              = buffer,
		offset              = 0,
		size                = size,
	}
	vk.CmdPipelineBarrier(
		cmd,
		src_stage,
		{.BOTTOM_OF_PIPE},
		{},
		0, nil,
		1, &barrier,
		0, nil,
	)
}

// barrier_queue_acquire records an acquire barrier that completes ownership
// transfer of a buffer from src_family to dst_family.  Record into a command
// buffer submitted on the destination queue.
barrier_queue_acquire :: proc(
	cmd: vk.CommandBuffer,
	buffer: vk.Buffer,
	size: vk.DeviceSize,
	dst_access: vk.AccessFlags,
	dst_stage: vk.PipelineStageFlags,
	src_family: u32,
	dst_family: u32,
) {
	if src_family == dst_family { return }
	barrier := vk.BufferMemoryBarrier {
		sType               = .BUFFER_MEMORY_BARRIER,
		srcAccessMask       = {},
		dstAccessMask       = dst_access,
		srcQueueFamilyIndex = src_family,
		dstQueueFamilyIndex = dst_family,
		buffer              = buffer,
		offset              = 0,
		size                = size,
	}
	vk.CmdPipelineBarrier(
		cmd,
		{.TOP_OF_PIPE},
		dst_stage,
		{},
		0, nil,
		1, &barrier,
		0, nil,
	)
}

// ─── Semaphore helpers ───────────────────────────────────────────────────────

// create_semaphore creates a binary semaphore for inter-queue synchronization.
create_semaphore :: proc(device: vk.Device) -> (vk.Semaphore, bool) {
	ci := vk.SemaphoreCreateInfo { sType = .SEMAPHORE_CREATE_INFO }
	sem: vk.Semaphore
	if vk.CreateSemaphore(device, &ci, nil, &sem) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateSemaphore failed")
		return {}, false
	}
	return sem, true
}

// create_fence creates a fence, optionally pre-signaled.
create_fence :: proc(device: vk.Device, signaled: bool = false) -> (vk.Fence, bool) {
	flags: vk.FenceCreateFlags
	if signaled { flags = {.SIGNALED} }
	ci := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = flags,
	}
	fence: vk.Fence
	if vk.CreateFence(device, &ci, nil, &fence) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateFence failed")
		return {}, false
	}
	return fence, true
}

// ─── Compute dispatch with synchronization ──────────────────────────────────

// DispatchSyncConfig describes a compute dispatch with all required barriers.
DispatchSyncConfig :: struct {
	ctx:             ^VulkanContext,
	pipeline:        ^VulkanComputePipeline,
	groups_x:        u32,
	groups_y:        u32,
	groups_z:        u32,
	// Buffer that is written by the compute shader (e.g. output accumulation).
	output_buffer:   vk.Buffer,
	output_size:     vk.DeviceSize,
	// If true, insert a compute→compute barrier after dispatch for multi-sample
	// accumulation (next dispatch reads the same buffer).
	accumulate:      bool,
	// If true, insert a compute→host barrier after dispatch for CPU readback.
	readback_host:   bool,
	// If true, insert a compute→transfer barrier for staging-buffer copy readback.
	readback_staged: bool,
}

// dispatch_compute_synced records a compute dispatch with appropriate post-dispatch
// barriers into the given command buffer.  Does NOT submit — the caller controls
// batching and submission.
dispatch_compute_synced :: proc(cmd: vk.CommandBuffer, cfg: DispatchSyncConfig) {
	vk.CmdBindPipeline(cmd, .COMPUTE, cfg.pipeline.pipeline)
	vk.CmdBindDescriptorSets(
		cmd, .COMPUTE, cfg.pipeline.pipeline_layout,
		0, 1, &cfg.pipeline.descriptor_set, 0, nil,
	)
	vk.CmdDispatch(cmd, cfg.groups_x, cfg.groups_y, cfg.groups_z)

	if cfg.accumulate {
		barrier_compute_write_to_compute_read(cmd, cfg.output_buffer, cfg.output_size)
	}
	if cfg.readback_host {
		barrier_compute_write_to_host_read(cmd, cfg.output_buffer, cfg.output_size)
	}
	if cfg.readback_staged {
		barrier_compute_write_to_transfer_read(cmd, cfg.output_buffer, cfg.output_size)
	}
}
