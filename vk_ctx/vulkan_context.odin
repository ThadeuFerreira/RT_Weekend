package vk_ctx

import "base:runtime"
import "core:c"
import "core:fmt"

import glfw "vendor:glfw"
import vk "vendor:vulkan"

// When true (default in debug builds), enable validation layers and VK_EXT_debug_utils.
VK_VALIDATION :: #config(VK_VALIDATION, ODIN_DEBUG)

// VulkanContext holds instance, device, queues, pools, and basic sync objects used by both
// headless and windowed bootstrap paths.
VulkanContext :: struct {
	instance:                vk.Instance,
	physical_device:         vk.PhysicalDevice,
	device:                  vk.Device,
	graphics_queue_family:   u32,
	present_queue_family:    u32,
	compute_queue_family:    u32,
	graphics_queue:          vk.Queue,
	present_queue:           vk.Queue,
	compute_queue:           vk.Queue,
	command_pool:            vk.CommandPool,
	surface:                 vk.SurfaceKHR,
	fence:                   vk.Fence,
	semaphore_image_available: vk.Semaphore,
	semaphore_render_finished: vk.Semaphore,
	debug_messenger:         vk.DebugUtilsMessengerEXT,
	glfw_window:             glfw.WindowHandle, // nil if headless
	glfw_owned:              bool, // true if this context called glfw.Init
}

VALIDATION_LAYER_KHRONOS :: cstring("VK_LAYER_KHRONOS_validation")

vk_zstring_from_byte_array :: proc(buf: []byte) -> string {
	n := len(buf)
	for i in 0 ..< len(buf) {
		if buf[i] == 0 {
			n = i
			break
		}
	}
	return string(buf[:n])
}

vk_zstring_from_fixed_name :: proc(name: [vk.MAX_EXTENSION_NAME_SIZE]byte) -> string {
	nk := name
	return vk_zstring_from_byte_array(nk[:])
}

// instance_extension_available reports whether an instance extension is advertised by the loader
// (after vk_load_vulkan). Used for VK_KHR_portability_enumeration and similar.
instance_extension_available :: proc(extension_name: cstring) -> bool {
	count: u32
	if vk.EnumerateInstanceExtensionProperties(nil, &count, nil) != .SUCCESS {
		return false
	}
	if count == 0 {
		return false
	}
	props := make([]vk.ExtensionProperties, count, context.temp_allocator)
	if vk.EnumerateInstanceExtensionProperties(nil, &count, raw_data(props)) != .SUCCESS {
		return false
	}
	want := string(extension_name)
	for p in props {
		if vk_zstring_from_fixed_name(p.extensionName) == want {
			return true
		}
	}
	return false
}

// device_extension_available reports whether a device extension exists on the given GPU.
device_extension_available :: proc(physical_device: vk.PhysicalDevice, extension_name: cstring) -> bool {
	count: u32
	if vk.EnumerateDeviceExtensionProperties(physical_device, nil, &count, nil) != .SUCCESS {
		return false
	}
	if count == 0 {
		return false
	}
	props := make([]vk.ExtensionProperties, count, context.temp_allocator)
	if vk.EnumerateDeviceExtensionProperties(physical_device, nil, &count, raw_data(props)) !=
	   .SUCCESS {
		return false
	}
	want := string(extension_name)
	for p in props {
		if vk_zstring_from_fixed_name(p.extensionName) == want {
			return true
		}
	}
	return false
}

// validation_layer_available is true when the standard Khronos validation layer is installed.
validation_layer_available :: proc() -> bool {
	count: u32
	if vk.EnumerateInstanceLayerProperties(&count, nil) != .SUCCESS || count == 0 {
		return false
	}
	layers := make([]vk.LayerProperties, count, context.temp_allocator)
	if vk.EnumerateInstanceLayerProperties(&count, raw_data(layers)) != .SUCCESS {
		return false
	}
	want :: "VK_LAYER_KHRONOS_validation"
	for l in layers {
		name := vk_zstring_from_fixed_name(l.layerName)
		if name == want {
			return true
		}
	}
	return false
}

// vk_load_vulkan initializes GLFW (for Vulkan entry points) and loads global Vulkan procs.
// Call once before creating an instance. Fails cleanly if GLFW cannot use Vulkan or the loader
// does not respond (missing libvulkan / ICD, broken install).
// When headless is true, GLFW is initialized with PLATFORM_NULL so no display server is required.
// For window mode, pass a GLFW platform hint (ANY/X11/WAYLAND/etc.) when needed.
vk_load_vulkan :: proc(headless := false, window_platform: c.int = glfw.ANY_PLATFORM) -> bool {
	if headless {
		glfw.InitHint(glfw.PLATFORM, glfw.PLATFORM_NULL)
	} else {
		glfw.InitHint(glfw.PLATFORM, window_platform)
	}
	if !glfw.Init() {
		desc, _ := glfw.GetError()
		if len(desc) > 0 {
			fmt.eprintf("vk_ctx: glfw.Init failed: %s\n", desc)
		} else {
			fmt.eprintln("vk_ctx: glfw.Init failed")
		}
		return false
	}
	if !glfw.VulkanSupported() {
		fmt.eprintln("vk_ctx: glfw.VulkanSupported() is false (no Vulkan loader or ICD)")
		glfw.Terminate()
		return false
	}
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	if vk.GetInstanceProcAddr == nil {
		fmt.eprintln("vk_ctx: vkGetInstanceProcAddr is null after load_proc_addresses_global")
		glfw.Terminate()
		return false
	}
	ext_count: u32
	if vk.EnumerateInstanceExtensionProperties(nil, &ext_count, nil) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkEnumerateInstanceExtensionProperties failed (Vulkan loader broken?)")
		glfw.Terminate()
		return false
	}
	return true
}

vk_unload_glfw :: proc() {
	glfw.Terminate()
}

vk_assert :: proc(res: vk.Result, loc := #caller_location) -> bool {
	if res != .SUCCESS {
		fmt.eprintf("[%s:%d] Vulkan error: %v\n", loc.file_path, loc.line, res)
		return false
	}
	return true
}

append_cstring_unique :: proc(dst: ^[dynamic]cstring, s: cstring) {
	for existing in dst {
		if existing == s {
			return
		}
	}
	append(dst, s)
}

// find_graphics_queue_family returns the first queue family with GRAPHICS_BIT.
find_graphics_queue_family :: proc(phys: vk.PhysicalDevice) -> (u32, bool) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(phys, &count, nil)
	if count == 0 {
		return 0, false
	}
	props := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(phys, &count, raw_data(props))
	for i in 0 ..< count {
		if .GRAPHICS in props[i].queueFlags {
			return u32(i), true
		}
	}
	return 0, false
}

// find_compute_queue_family returns the first queue family with COMPUTE_BIT.
// Prefers a dedicated compute family (without GRAPHICS) for async compute; falls back to
// any family with COMPUTE.
find_compute_queue_family :: proc(phys: vk.PhysicalDevice) -> (u32, bool) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(phys, &count, nil)
	if count == 0 {
		return 0, false
	}
	props := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(phys, &count, raw_data(props))
	// First pass: dedicated compute (COMPUTE but not GRAPHICS).
	for i in 0 ..< count {
		if .COMPUTE in props[i].queueFlags && .GRAPHICS not_in props[i].queueFlags {
			return u32(i), true
		}
	}
	// Second pass: any family with COMPUTE.
	for i in 0 ..< count {
		if .COMPUTE in props[i].queueFlags {
			return u32(i), true
		}
	}
	return 0, false
}

// find_present_queue_family returns a family index that can present to surface, or false.
find_present_queue_family :: proc(
	phys: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> (u32, bool) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(phys, &count, nil)
	if count == 0 {
		return 0, false
	}
	for i in 0 ..< count {
		supported: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(phys, u32(i), surface, &supported)
		if supported {
			return u32(i), true
		}
	}
	return 0, false
}

// score_physical_device prefers discrete GPUs; higher is better.
score_physical_device :: proc(phys: vk.PhysicalDevice) -> i32 {
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(phys, &props)
	#partial switch props.deviceType {
	case .DISCRETE_GPU:
		return 1000
	case .INTEGRATED_GPU:
		return 100
	case .VIRTUAL_GPU:
		return 50
	case:
		return 10
	}
}

pick_physical_device :: proc(
	instance: vk.Instance,
	surface: vk.SurfaceKHR,
) -> (vk.PhysicalDevice, u32, u32, bool) {
	dev_count: u32
	if vk.EnumeratePhysicalDevices(instance, &dev_count, nil) != .SUCCESS || dev_count == 0 {
		return nil, 0, 0, false
	}
	devices := make([]vk.PhysicalDevice, dev_count, context.temp_allocator)
	if vk.EnumeratePhysicalDevices(instance, &dev_count, raw_data(devices)) != .SUCCESS {
		return nil, 0, 0, false
	}
	best_phys: vk.PhysicalDevice
	best_score: i32 = -1
	best_g: u32
	best_p: u32
	for d in devices {
		gq, gok := find_graphics_queue_family(d)
		if !gok {
			continue
		}
		pq := gq
		if surface != vk.SurfaceKHR(0) {
			pq2, pok := find_present_queue_family(d, surface)
			if !pok {
				continue
			}
			pq = pq2
		}
		sc := score_physical_device(d)
		if sc > best_score {
			best_score = sc
			best_phys = d
			best_g = gq
			best_p = pq
		}
	}
	if best_score < 0 {
		return nil, 0, 0, false
	}
	return best_phys, best_g, best_p, true
}

setup_debug_messenger :: proc(instance: vk.Instance, out_messenger: ^vk.DebugUtilsMessengerEXT) -> bool {
	ci := vk.DebugUtilsMessengerCreateInfoEXT {
		sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = {.WARNING, .ERROR},
		messageType = {.GENERAL, .VALIDATION},
		pfnUserCallback = debug_utils_callback,
	}
	res := vk.CreateDebugUtilsMessengerEXT(instance, &ci, nil, out_messenger)
	return res == .SUCCESS
}

create_logical_device :: proc(
	phys: vk.PhysicalDevice,
	queue_families: []u32,
	device_extensions: []cstring,
) -> (vk.Device, bool) {
	merged: [dynamic]cstring
	defer delete(merged)
	if device_extensions != nil {
		for e in device_extensions {
			append_cstring_unique(&merged, e)
		}
	}
	if device_extension_available(phys, vk.KHR_PORTABILITY_SUBSET_EXTENSION_NAME) {
		append_cstring_unique(&merged, vk.KHR_PORTABILITY_SUBSET_EXTENSION_NAME)
	}

	// Collect unique queue families.
	priorities := [1]f32{1.0}
	queue_infos: [4]vk.DeviceQueueCreateInfo
	queue_count: int
	for fam in queue_families {
		already := false
		for j in 0 ..< queue_count {
			if queue_infos[j].queueFamilyIndex == fam {
				already = true
				break
			}
		}
		if !already {
			queue_infos[queue_count] = {
				sType            = .DEVICE_QUEUE_CREATE_INFO,
				queueFamilyIndex = fam,
				queueCount       = 1,
				pQueuePriorities = raw_data(priorities[:]),
			}
			queue_count += 1
		}
	}
	features: vk.PhysicalDeviceFeatures
	dci := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(queue_count),
		pQueueCreateInfos       = raw_data(queue_infos[:queue_count]),
		enabledExtensionCount   = u32(len(merged)),
		ppEnabledExtensionNames = raw_data(merged[:]) if len(merged) > 0 else nil,
		pEnabledFeatures        = &features,
	}
	device: vk.Device
	if res := vk.CreateDevice(phys, &dci, nil, &device); res != .SUCCESS {
		fmt.eprintf("vk_ctx: vkCreateDevice failed: %v\n", res)
		return nil, false
	}
	vk.load_proc_addresses_device(device)
	return device, true
}

create_command_pool_and_sync :: proc(
	device: vk.Device,
	graphics_family: u32,
	out_ctx: ^VulkanContext,
) -> bool {
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = graphics_family,
	}
	if vk.CreateCommandPool(device, &pool_info, nil, &out_ctx.command_pool) != .SUCCESS {
		return false
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		// Start signaled so the first frame wait does not deadlock.
		flags = {.SIGNALED},
	}
	if vk.CreateFence(device, &fence_info, nil, &out_ctx.fence) != .SUCCESS {
		return false
	}
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	if vk.CreateSemaphore(device, &sem_info, nil, &out_ctx.semaphore_image_available) != .SUCCESS {
		return false
	}
	if vk.CreateSemaphore(device, &sem_info, nil, &out_ctx.semaphore_render_finished) != .SUCCESS {
		return false
	}
	return true
}

// create_instance builds a VkInstance with the given extensions and optional validation layers.
// Enables VK_KHR_portability_enumeration + ENUMERATE_PORTABILITY_KHR when the loader advertises
// the extension (required to see MoltenVK and other portability ICDs).
create_instance :: proc(
	app_name: cstring,
	instance_extensions: []cstring,
	enable_validation: bool,
) -> (vk.Instance, bool) {
	merged: [dynamic]cstring
	defer delete(merged)
	for e in instance_extensions {
		append_cstring_unique(&merged, e)
	}
	portability_enum := instance_extension_available(vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	if portability_enum {
		append_cstring_unique(&merged, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	// Negotiate API version: use the highest the loader supports, falling back to 1.0.
	api_version: u32 = vk.API_VERSION_1_0
	if vk.EnumerateInstanceVersion != nil {
		loader_version: u32
		if vk.EnumerateInstanceVersion(&loader_version) == .SUCCESS {
			api_version = loader_version
		}
	}
	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = app_name,
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = cstring("vk_ctx"),
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = api_version,
	}
	layer_names: [dynamic]cstring
	defer delete(layer_names)
	if enable_validation {
		append(&layer_names, VALIDATION_LAYER_KHRONOS)
	}

	ici := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		flags                   = portability_enum ? vk.InstanceCreateFlags{.ENUMERATE_PORTABILITY_KHR} : {},
		pApplicationInfo        = &app_info,
		enabledLayerCount       = u32(len(layer_names)),
		ppEnabledLayerNames     = raw_data(layer_names),
		enabledExtensionCount   = u32(len(merged)),
		ppEnabledExtensionNames = raw_data(merged[:]) if len(merged) > 0 else nil,
	}
	inst: vk.Instance
	if res := vk.CreateInstance(&ici, nil, &inst); res != .SUCCESS {
		fmt.eprintf("vk_ctx: vkCreateInstance failed: %v\n", res)
		return nil, false
	}
	vk.load_proc_addresses_instance(inst)
	return inst, true
}

vulkan_context_destroy :: proc(ctx: ^VulkanContext) {
	if ctx.device != nil {
		vk.DeviceWaitIdle(ctx.device)
	}
	if ctx.semaphore_render_finished != vk.Semaphore(0) {
		vk.DestroySemaphore(ctx.device, ctx.semaphore_render_finished, nil)
		ctx.semaphore_render_finished = {}
	}
	if ctx.semaphore_image_available != vk.Semaphore(0) {
		vk.DestroySemaphore(ctx.device, ctx.semaphore_image_available, nil)
		ctx.semaphore_image_available = {}
	}
	if ctx.fence != vk.Fence(0) {
		vk.DestroyFence(ctx.device, ctx.fence, nil)
		ctx.fence = {}
	}
	if ctx.command_pool != vk.CommandPool(0) {
		vk.DestroyCommandPool(ctx.device, ctx.command_pool, nil)
		ctx.command_pool = {}
	}
	if ctx.device != nil {
		vk.DestroyDevice(ctx.device, nil)
		ctx.device = nil
	}
	if ctx.surface != vk.SurfaceKHR(0) && ctx.instance != nil {
		vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
		ctx.surface = {}
	}
	if ctx.debug_messenger != vk.DebugUtilsMessengerEXT(0) && ctx.instance != nil {
		vk.DestroyDebugUtilsMessengerEXT(ctx.instance, ctx.debug_messenger, nil)
		ctx.debug_messenger = {}
	}
	if ctx.instance != nil {
		vk.DestroyInstance(ctx.instance, nil)
		ctx.instance = nil
	}
	if ctx.glfw_window != nil {
		glfw.DestroyWindow(glfw.WindowHandle(ctx.glfw_window))
		ctx.glfw_window = nil
	}
	if ctx.glfw_owned {
		vk_unload_glfw()
		ctx.glfw_owned = false
	}
}

debug_utils_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()
	if pCallbackData != nil && pCallbackData.pMessage != nil {
		fmt.eprintf("[Vulkan] %s\n", pCallbackData.pMessage)
	}
	return b32(false)
}
