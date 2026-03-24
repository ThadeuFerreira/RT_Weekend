package vk_ctx

import "core:fmt"

import vk "vendor:vulkan"

vk_api_version_string :: proc(v: u32) -> string {
	major := (v >> 22) & 0xff
	minor := (v >> 12) & 0x3ff
	patch := v & 0xfff
	return fmt.tprintf("%d.%d.%d", major, minor, patch)
}

// print_vulkan_context_gpu_info prints device name, type, versions, selected limits, memory heaps,
// and queue families for the given context. Core Vulkan does not report SM/CU counts; that line
// is noted explicitly.
print_vulkan_context_gpu_info :: proc(ctx: ^VulkanContext) {
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(ctx.physical_device, &props)

	dn := props.deviceName
	device_name := vk_zstring_from_byte_array(dn[:])

	fmt.printf("GPU deviceName: %s\n", device_name)
	fmt.printf("  deviceType: %v\n", props.deviceType)
	fmt.printf("  apiVersion: %s\n", vk_api_version_string(props.apiVersion))
	fmt.printf("  driverVersion: 0x%x\n", props.driverVersion)
	fmt.printf("  vendorID: 0x%x  deviceID: 0x%x\n", props.vendorID, props.deviceID)

	limits := props.limits
	fmt.printf(
		"  limits: maxImageDimension2D=%d maxImageDimension3D=%d\n",
		limits.maxImageDimension2D,
		limits.maxImageDimension3D,
	)
	fmt.printf(
		"  limits: maxComputeWorkGroupCount=(%d,%d,%d) maxComputeWorkGroupInvocations=%d\n",
		limits.maxComputeWorkGroupCount[0],
		limits.maxComputeWorkGroupCount[1],
		limits.maxComputeWorkGroupCount[2],
		limits.maxComputeWorkGroupInvocations,
	)
	fmt.printf(
		"  limits: maxComputeSharedMemorySize=%d maxUniformBufferRange=%d maxStorageBufferRange=%d\n",
		limits.maxComputeSharedMemorySize,
		limits.maxUniformBufferRange,
		limits.maxStorageBufferRange,
	)
	fmt.printf(
		"  limits: maxPushConstantsSize=%d maxSamplerAllocationCount=%d\n",
		limits.maxPushConstantsSize,
		limits.maxSamplerAllocationCount,
	)

	mem_props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(ctx.physical_device, &mem_props)
	fmt.printf(
		"  memory: memoryTypes=%d memoryHeaps=%d\n",
		mem_props.memoryTypeCount,
		mem_props.memoryHeapCount,
	)
	for i in 0 ..< mem_props.memoryHeapCount {
		h := mem_props.memoryHeaps[i]
		size_mib := h.size / (1024 * 1024)
		fmt.printf("    heap %d: size=%d MiB flags=%v\n", i, size_mib, h.flags)
	}

	qf_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(ctx.physical_device, &qf_count, nil)
	qf_props := make([]vk.QueueFamilyProperties, qf_count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(ctx.physical_device, &qf_count, raw_data(qf_props))
	if ctx.graphics_queue_family < qf_count {
		q := qf_props[ctx.graphics_queue_family]
		fmt.printf(
			"  queue family %d (graphics): queueCount=%d queueFlags=%v timestampValidBits=%d\n",
			ctx.graphics_queue_family,
			q.queueCount,
			q.queueFlags,
			q.timestampValidBits,
		)
	}
	if ctx.present_queue_family != ctx.graphics_queue_family && ctx.present_queue_family < qf_count {
		q := qf_props[ctx.present_queue_family]
		fmt.printf(
			"  queue family %d (present): queueCount=%d queueFlags=%v\n",
			ctx.present_queue_family,
			q.queueCount,
			q.queueFlags,
		)
	}

	fmt.println("  note: core Vulkan has no standard SM/CU count; use vendor extensions for that.")
}
