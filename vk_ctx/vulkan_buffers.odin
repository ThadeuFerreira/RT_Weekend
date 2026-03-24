package vk_ctx

import "core:fmt"
import "core:mem"

import vk "vendor:vulkan"

// VulkanBuffer pairs a Vulkan buffer with its backing device memory.
VulkanBuffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	size:   vk.DeviceSize,
	mapped: rawptr, // non-nil when persistently mapped
}

// create_buffer allocates a device-local buffer (not mapped).
create_buffer :: proc(
	device: vk.Device,
	phys: vk.PhysicalDevice,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	mem_props: vk.MemoryPropertyFlags,
) -> (buf: VulkanBuffer, ok: bool) {
	ci := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	if vk.CreateBuffer(device, &ci, nil, &buf.buffer) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateBuffer failed")
		return buf, false
	}
	buf.size = size

	mem_req: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buf.buffer, &mem_req)

	mem_type, mt_ok := find_memory_type(phys, mem_req.memoryTypeBits, mem_props)
	if !mt_ok {
		fmt.eprintln("vk_ctx: no suitable memory type for buffer")
		vk.DestroyBuffer(device, buf.buffer, nil)
		return buf, false
	}

	alloc := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_req.size,
		memoryTypeIndex = mem_type,
	}
	if vk.AllocateMemory(device, &alloc, nil, &buf.memory) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkAllocateMemory failed")
		vk.DestroyBuffer(device, buf.buffer, nil)
		return buf, false
	}
	if vk.BindBufferMemory(device, buf.buffer, buf.memory, 0) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkBindBufferMemory failed")
		vk.FreeMemory(device, buf.memory, nil)
		vk.DestroyBuffer(device, buf.buffer, nil)
		return buf, false
	}
	return buf, true
}

// create_host_visible_buffer allocates a HOST_VISIBLE|HOST_COHERENT buffer and persistently maps it.
create_host_visible_buffer :: proc(
	device: vk.Device,
	phys: vk.PhysicalDevice,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
) -> (buf: VulkanBuffer, ok: bool) {
	buf, ok = create_buffer(device, phys, size, usage, {.HOST_VISIBLE, .HOST_COHERENT})
	if !ok { return }
	if vk.MapMemory(device, buf.memory, 0, size, {}, &buf.mapped) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkMapMemory failed")
		destroy_buffer(device, &buf)
		return buf, false
	}
	return buf, true
}

// create_buffer_staged uploads data to a device-local buffer via a staging copy.
create_buffer_staged :: proc(
	ctx: ^VulkanContext,
	data: rawptr,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
) -> (buf: VulkanBuffer, ok: bool) {
	// Create staging buffer (host-visible).
	staging, s_ok := create_host_visible_buffer(
		ctx.device, ctx.physical_device, size,
		{.TRANSFER_SRC},
	)
	if !s_ok { return buf, false }
	defer destroy_buffer(ctx.device, &staging)

	mem.copy(staging.mapped, data, int(size))

	// Create device-local destination buffer.
	buf, ok = create_buffer(
		ctx.device, ctx.physical_device, size,
		usage + {.TRANSFER_DST},
		{.DEVICE_LOCAL},
	)
	if !ok { return }

	// Record and submit a one-shot copy command.
	cmd_alloc := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	cmd: vk.CommandBuffer
	if vk.AllocateCommandBuffers(ctx.device, &cmd_alloc, &cmd) != .SUCCESS {
		destroy_buffer(ctx.device, &buf)
		return buf, false
	}
	defer vk.FreeCommandBuffers(ctx.device, ctx.command_pool, 1, &cmd)

	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if vk.BeginCommandBuffer(cmd, &begin) != .SUCCESS {
		destroy_buffer(ctx.device, &buf)
		return buf, false
	}

	region := vk.BufferCopy { size = size }
	vk.CmdCopyBuffer(cmd, staging.buffer, buf.buffer, 1, &region)

	if vk.EndCommandBuffer(cmd) != .SUCCESS {
		destroy_buffer(ctx.device, &buf)
		return buf, false
	}

	fence_info := vk.FenceCreateInfo { sType = .FENCE_CREATE_INFO }
	fence: vk.Fence
	if vk.CreateFence(ctx.device, &fence_info, nil, &fence) != .SUCCESS {
		destroy_buffer(ctx.device, &buf)
		return buf, false
	}
	defer vk.DestroyFence(ctx.device, fence, nil)

	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd,
	}
	if vk.QueueSubmit(ctx.compute_queue, 1, &submit, fence) != .SUCCESS {
		destroy_buffer(ctx.device, &buf)
		return buf, false
	}
	vk.WaitForFences(ctx.device, 1, &fence, true, ~u64(0))

	return buf, true
}

// destroy_buffer unmaps, frees memory, and destroys the buffer.
destroy_buffer :: proc(device: vk.Device, buf: ^VulkanBuffer) {
	if buf.mapped != nil {
		vk.UnmapMemory(device, buf.memory)
		buf.mapped = nil
	}
	if buf.memory != vk.DeviceMemory(0) {
		vk.FreeMemory(device, buf.memory, nil)
		buf.memory = {}
	}
	if buf.buffer != vk.Buffer(0) {
		vk.DestroyBuffer(device, buf.buffer, nil)
		buf.buffer = {}
	}
	buf.size = 0
}

// update_buffer_data writes to a persistently mapped host-visible buffer.
update_buffer_data :: proc(buf: ^VulkanBuffer, offset: int, data: rawptr, size: int) {
	dst := rawptr(uintptr(buf.mapped) + uintptr(offset))
	mem.copy(dst, data, size)
}

// read_buffer_data reads from a persistently mapped host-visible buffer.
read_buffer_data :: proc(buf: ^VulkanBuffer, offset: int, dst: rawptr, size: int) {
	src := rawptr(uintptr(buf.mapped) + uintptr(offset))
	mem.copy(dst, src, size)
}
