package vk_ctx

import "base:runtime"
import "core:fmt"

import vk "vendor:vulkan"

// ─── Compile-time configuration flags ────────────────────────────────────────
//
// VK_VALIDATION (vulkan_context.odin)   — enables validation layers + debug messenger.
// VK_VERBOSE                            — includes INFO severity and PERFORMANCE messages.
// VK_DEBUG_NAMES                        — enables object naming via VK_EXT_debug_utils.
// VK_ASSERT_RESULTS                     — panics on unexpected VkResult in debug helpers.
//
// Defaults: VK_VALIDATION = ODIN_DEBUG, others = false.  Override with:
//   odin build ... -define:VK_VERBOSE=true -define:VK_DEBUG_NAMES=true -define:VK_ASSERT_RESULTS=true

VK_VERBOSE        :: #config(VK_VERBOSE, false)
VK_DEBUG_NAMES    :: #config(VK_DEBUG_NAMES, false)
VK_ASSERT_RESULTS :: #config(VK_ASSERT_RESULTS, ODIN_DEBUG)

// ─── Verbose debug messenger ─────────────────────────────────────────────────

// setup_debug_messenger_verbose creates a messenger that additionally includes
// INFO severity and PERFORMANCE message types.  Use when VK_VERBOSE is true.
setup_debug_messenger_verbose :: proc(instance: vk.Instance, out_messenger: ^vk.DebugUtilsMessengerEXT) -> bool {
	ci := vk.DebugUtilsMessengerCreateInfoEXT {
		sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = {.INFO, .WARNING, .ERROR},
		messageType = {.GENERAL, .VALIDATION, .PERFORMANCE},
		pfnUserCallback = debug_utils_callback_verbose,
	}
	res := vk.CreateDebugUtilsMessengerEXT(instance, &ci, nil, out_messenger)
	return res == .SUCCESS
}

debug_utils_callback_verbose :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()
	if pCallbackData == nil || pCallbackData.pMessage == nil { return b32(false) }

	severity_tag: string
	if .ERROR in messageSeverity {
		severity_tag = "ERROR"
	} else if .WARNING in messageSeverity {
		severity_tag = "WARN"
	} else if .INFO in messageSeverity {
		severity_tag = "INFO"
	} else {
		severity_tag = "VERBOSE"
	}

	type_tag: string
	if .PERFORMANCE in messageTypes {
		type_tag = "PERF"
	} else if .VALIDATION in messageTypes {
		type_tag = "VALID"
	} else {
		type_tag = "GEN"
	}

	fmt.eprintf("[Vulkan/%s/%s] %s\n", severity_tag, type_tag, pCallbackData.pMessage)
	return b32(false)
}

// ─── Debug object naming ─────────────────────────────────────────────────────
//
// When VK_DEBUG_NAMES is true and validation layers are active, these procs
// assign human-readable names to Vulkan objects.  Names appear in validation
// messages and tools like RenderDoc.

// set_debug_name labels a Vulkan object for debug tooling.  No-op when
// VK_DEBUG_NAMES is false or the device is nil.
set_debug_name :: proc(device: vk.Device, object_type: vk.ObjectType, handle: u64, name: cstring) {
	when !VK_DEBUG_NAMES { return }
	if device == nil { return }
	if vk.SetDebugUtilsObjectNameEXT == nil { return }
	info := vk.DebugUtilsObjectNameInfoEXT {
		sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
		objectType   = object_type,
		objectHandle = handle,
		pObjectName  = name,
	}
	vk.SetDebugUtilsObjectNameEXT(device, &info)
}

// Convenience wrappers for common object types.

set_buffer_name :: proc(device: vk.Device, buffer: vk.Buffer, name: cstring) {
	set_debug_name(device, .BUFFER, u64(uintptr(buffer)), name)
}

set_pipeline_name :: proc(device: vk.Device, pipeline: vk.Pipeline, name: cstring) {
	set_debug_name(device, .PIPELINE, u64(uintptr(pipeline)), name)
}

set_descriptor_set_name :: proc(device: vk.Device, set: vk.DescriptorSet, name: cstring) {
	set_debug_name(device, .DESCRIPTOR_SET, u64(uintptr(set)), name)
}

set_command_pool_name :: proc(device: vk.Device, pool: vk.CommandPool, name: cstring) {
	set_debug_name(device, .COMMAND_POOL, u64(uintptr(pool)), name)
}

set_queue_name :: proc(device: vk.Device, queue: vk.Queue, name: cstring) {
	set_debug_name(device, .QUEUE, u64(uintptr(queue)), name)
}

set_fence_name :: proc(device: vk.Device, fence: vk.Fence, name: cstring) {
	set_debug_name(device, .FENCE, u64(uintptr(fence)), name)
}

set_semaphore_name :: proc(device: vk.Device, semaphore: vk.Semaphore, name: cstring) {
	set_debug_name(device, .SEMAPHORE, u64(uintptr(semaphore)), name)
}

set_image_name :: proc(device: vk.Device, image: vk.Image, name: cstring) {
	set_debug_name(device, .IMAGE, u64(uintptr(image)), name)
}

set_image_view_name :: proc(device: vk.Device, view: vk.ImageView, name: cstring) {
	set_debug_name(device, .IMAGE_VIEW, u64(uintptr(view)), name)
}

// ─── Command buffer debug labels ─────────────────────────────────────────────
//
// Insert named regions into a command buffer for RenderDoc / validation output.

// cmd_begin_label starts a debug label region in a command buffer.
cmd_begin_label :: proc(cmd: vk.CommandBuffer, name: cstring, color: [4]f32 = {1, 1, 1, 1}) {
	when !VK_DEBUG_NAMES { return }
	if vk.CmdBeginDebugUtilsLabelEXT == nil { return }
	label := vk.DebugUtilsLabelEXT {
		sType      = .DEBUG_UTILS_LABEL_EXT,
		pLabelName = name,
		color      = color,
	}
	vk.CmdBeginDebugUtilsLabelEXT(cmd, &label)
}

// cmd_end_label ends the most recent debug label region.
cmd_end_label :: proc(cmd: vk.CommandBuffer) {
	when !VK_DEBUG_NAMES { return }
	if vk.CmdEndDebugUtilsLabelEXT == nil { return }
	vk.CmdEndDebugUtilsLabelEXT(cmd)
}

// cmd_insert_label inserts a single-point debug label (marker).
cmd_insert_label :: proc(cmd: vk.CommandBuffer, name: cstring, color: [4]f32 = {1, 1, 1, 1}) {
	when !VK_DEBUG_NAMES { return }
	if vk.CmdInsertDebugUtilsLabelEXT == nil { return }
	label := vk.DebugUtilsLabelEXT {
		sType      = .DEBUG_UTILS_LABEL_EXT,
		pLabelName = name,
		color      = color,
	}
	vk.CmdInsertDebugUtilsLabelEXT(cmd, &label)
}

// ─── Checked VkResult helper ─────────────────────────────────────────────────

// vk_check logs and optionally panics on a non-SUCCESS VkResult.
// When VK_ASSERT_RESULTS is true, non-SUCCESS results cause a panic.
// When false, they are logged to stderr and the caller can handle them.
vk_check :: proc(result: vk.Result, message: string = "", loc := #caller_location) -> bool {
	if result == .SUCCESS { return true }
	if len(message) > 0 {
		fmt.eprintf("vk_ctx: %s: %v (at %s:%d)\n", message, result, loc.file_path, loc.line)
	} else {
		fmt.eprintf("vk_ctx: VkResult %v (at %s:%d)\n", result, loc.file_path, loc.line)
	}
	when VK_ASSERT_RESULTS {
		panic("vk_ctx: fatal Vulkan error", loc)
	}
	return false
}

// ─── Context debug labeling ──────────────────────────────────────────────────

// label_context_objects assigns debug names to standard VulkanContext objects
// (queues, pools, sync primitives).  Call after full context init.
label_context_objects :: proc(ctx: ^VulkanContext) {
	when !VK_DEBUG_NAMES { return }
	set_queue_name(ctx.device, ctx.graphics_queue, "queue/graphics")
	if ctx.present_queue != ctx.graphics_queue {
		set_queue_name(ctx.device, ctx.present_queue, "queue/present")
	}
	if ctx.compute_queue != ctx.graphics_queue {
		set_queue_name(ctx.device, ctx.compute_queue, "queue/compute")
	}
	set_command_pool_name(ctx.device, ctx.command_pool, "pool/graphics")
	if ctx.compute_command_pool != ctx.command_pool {
		set_command_pool_name(ctx.device, ctx.compute_command_pool, "pool/compute")
	}
	set_fence_name(ctx.device, ctx.fence, "fence/frame")
	if ctx.semaphore_image_available != vk.Semaphore(0) {
		set_semaphore_name(ctx.device, ctx.semaphore_image_available, "sem/image_available")
	}
	if ctx.semaphore_render_finished != vk.Semaphore(0) {
		set_semaphore_name(ctx.device, ctx.semaphore_render_finished, "sem/render_finished")
	}
}

// ─── Configuration summary ──────────────────────────────────────────────────

// print_vk_debug_config prints the active debug/validation settings to stdout.
print_vk_debug_config :: proc() {
	fmt.println("  Vulkan debug config:")
	fmt.printf("    VK_VALIDATION      = %v\n", VK_VALIDATION)
	fmt.printf("    VK_VERBOSE         = %v\n", VK_VERBOSE)
	fmt.printf("    VK_DEBUG_NAMES     = %v\n", VK_DEBUG_NAMES)
	fmt.printf("    VK_ASSERT_RESULTS  = %v\n", VK_ASSERT_RESULTS)
}
