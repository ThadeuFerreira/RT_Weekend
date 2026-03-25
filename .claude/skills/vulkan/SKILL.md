---
name: vulkan
description: Vulkan bootstrap, compute pipeline, swapchain, and rendering infrastructure for this Odin ray tracer. Use when working on Vulkan-related code in vk_ctx/, tools/vk_smoke/, or the Vulkan backend.
---

# Vulkan Infrastructure Skill

This skill covers the Vulkan bootstrap, compute pipeline, swapchain, and rendering infrastructure in this project. Use it when modifying or extending any Vulkan-related code.

## Package Layout

All Vulkan code lives in the `vk_ctx` package (`vk_ctx/` directory), imported as `"RT_Weekend:vk_ctx"`.

| File | Purpose |
|------|---------|
| `vk_ctx/vulkan_context.odin` | Loader init, instance creation, device/queue selection, command pool/sync, teardown |
| `vk_ctx/vulkan_context_headless.odin` | Headless context (no window/surface, uses `PLATFORM_NULL`) |
| `vk_ctx/vulkan_context_window.odin` | Window context (GLFW window, Vulkan surface, queues, device) |
| `vk_ctx/vulkan_swapchain.odin` | Swapchain creation, image views, command buffers, present paths |
| `vk_ctx/vulkan_triangle.odin` | Hello Triangle render pass, graphics pipeline, framebuffers, per-frame draw |
| `vk_ctx/vulkan_pipeline.odin` | Compute pipeline: descriptor set layout, pipeline layout, shader modules, descriptor pool/set |
| `vk_ctx/vulkan_buffers.odin` | Buffer helpers: host-visible, device-local, staged upload, read/write |

Smoke test: `tools/vk_smoke/main.odin` — CLI-driven headless/window Vulkan test.

Shaders: `assets/shaders/raytrace_vk.comp` (compute), `hello_triangle_vk.vert`/`.frag` (graphics). Pre-compiled SPIR-V (`.spv`) is committed and embedded via `#load`.

## Runtime-Safe Vulkan Loading

`vk_load_vulkan(headless: bool, window_platform: c.int)` in `vulkan_context.odin`:

1. Initializes GLFW with platform hint (`PLATFORM_NULL` for headless, `ANY_PLATFORM`/`PLATFORM_X11`/`PLATFORM_WAYLAND` for window)
2. Checks `glfw.VulkanSupported()` before touching Vulkan symbols
3. Loads global Vulkan proc addresses from `glfw.GetInstanceProcAddress`
4. Verifies `vk.GetInstanceProcAddr != nil`
5. Calls `vk.EnumerateInstanceExtensionProperties` to confirm loader is functional

**Critical:** Always check return values. Null function pointers crash; convert failures to explicit error messages.

## Instance Creation

`create_instance` in `vulkan_context.odin`:

- Negotiates API version via `vk.EnumerateInstanceVersion` with fallback to `VK_API_VERSION_1_0`
- Detects and enables `VK_KHR_portability_enumeration` when available (needed for MoltenVK)
- Sets `INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR` when portability extension is present
- Enables validation layers when `VK_VALIDATION` is true and layers are available

## Queue Family Selection

Three queue families are tracked in `VulkanContext`:
- `graphics_queue_family` — must support GRAPHICS
- `present_queue_family` — must support present to the surface (window mode only)
- `compute_queue_family` — prefers a dedicated async compute family; falls back to any COMPUTE-capable family

`find_compute_queue_family(phys)` in `vulkan_context.odin` handles the selection.

## Logical Device Creation

`create_logical_device(phys, families: []u32, extensions: []cstring)`:
- Accepts a slice of queue family indices (deduplicates internally)
- Creates one queue per unique family
- Extensions: `VK_KHR_swapchain` for window mode; none required for headless

## Headless Path

`vulkan_context_init_headless()` in `vulkan_context_headless.odin`:
- Uses `vk_load_vulkan(headless = true)` → `PLATFORM_NULL` (no display server needed)
- No surface, no swapchain, no present queue
- Good for CI, compute-only testing, and server environments

## Window Path

`vulkan_context_init_window(title, width, height, window_platform)` in `vulkan_context_window.odin`:
- Creates GLFW window with `CLIENT_API = NO_API`
- Creates Vulkan surface via `glfw.CreateWindowSurface`
- Requests `VK_KHR_swapchain` device extension
- `window_platform` parameter: `glfw.ANY_PLATFORM` (default), `glfw.PLATFORM_X11`, `glfw.PLATFORM_WAYLAND`

## Synchronization

`create_command_pool_and_sync` creates:
- Command pool for the graphics queue family
- Two semaphores: `semaphore_image_available`, `semaphore_render_finished`
- One fence: **created in SIGNALED state** (`flags = {.SIGNALED}`)

**Critical:** The fence MUST be created signaled. The frame loop waits on the fence before first submit; an unsignaled fence causes first-frame deadlock.

## Swapchain

`create_swapchain(ctx, width, height)` in `vulkan_swapchain.odin`:
- Queries surface capabilities and formats
- Prefers `B8G8R8A8_SRGB` + `SRGB_NONLINEAR`; falls back to first available
- Uses FIFO present mode (always supported)
- Handles different graphics/present queue families (concurrent sharing)
- Creates image views and one primary command buffer per swapchain image

**Wayland note:** Wayland compositors only map windows after the app commits a buffer. Without swapchain + present, you get a process/taskbar icon but no visible window.

## Present Paths

Both present procs follow the same pattern:
1. `WaitForFences` + `ResetFences`
2. `AcquireNextImageKHR` (signal `semaphore_image_available`)
3. Reset + record command buffer
4. `QueueSubmit` (wait on `image_available`, signal `render_finished`, signal fence)
5. `QueuePresentKHR` (wait on `render_finished`)

**Error handling:**
- `VK_ERROR_OUT_OF_DATE_KHR` on acquire/present → return true (non-fatal, loop continues)
- `VK_SUBOPTIMAL_KHR` → accepted, continue

## Compute Pipeline

`create_vulkan_compute_pipeline(device, spv_data)` in `vulkan_pipeline.odin` creates the full pipeline:

### Descriptor Layout (7 bindings, all COMPUTE stage)
| Binding | Type | Purpose |
|---------|------|---------|
| 0 | UNIFORM_BUFFER | Camera uniforms (UBO, std140) |
| 1 | STORAGE_BUFFER | Spheres SSBO |
| 2 | STORAGE_BUFFER | BVH nodes SSBO |
| 3 | STORAGE_BUFFER | Output image SSBO (W×H vec4) |
| 4 | STORAGE_BUFFER | Quads SSBO |
| 5 | STORAGE_BUFFER | Volumes SSBO |
| 6 | STORAGE_BUFFER | Volume quads SSBO |

Vulkan is the sole GPU compute backend.

### Pipeline Components
- `VulkanComputePipeline` struct holds: shader_module, descriptor_set_layout, pipeline_layout, pipeline, descriptor_pool, descriptor_set
- Entry point: `"main"`
- Workgroup size: 8×8×1 (defined in shader)
- Dispatch: `ceil(W/8) × ceil(H/8) × 1`

## Buffer Helpers

In `vulkan_buffers.odin`:

| Proc | Description |
|------|-------------|
| `create_host_visible_buffer` | HOST_VISIBLE + HOST_COHERENT, persistently mapped |
| `create_buffer` | Device-local allocation |
| `create_buffer_staged` | Staging copy to device-local via one-shot command buffer |
| `destroy_buffer` | Unmaps + frees memory + destroys buffer |
| `update_buffer_data` | memcpy to mapped pointer |
| `read_buffer_data` | memcpy from mapped pointer |

## Shader Compilation

```bash
make shaders
```

Compiles all Vulkan shaders via `glslangValidator -V`:
- `raytrace_vk.comp` → `raytrace_vk.comp.spv`
- `hello_triangle_vk.vert` → `hello_triangle_vk.vert.spv`
- `hello_triangle_vk.frag` → `hello_triangle_vk.frag.spv`

SPIR-V files are committed and embedded in Odin via `#load("path.spv")`.

## vk_smoke CLI

```bash
./build/vk_smoke --headless              # Instance/device/queues/sync
./build/vk_smoke --headless --clear      # + clear-color submit
./build/vk_smoke --headless --compute    # + full compute pipeline test
./build/vk_smoke --window                # GLFW window + triangle render
./build/vk_smoke --window --platform=x11
./build/vk_smoke --window --platform=wayland
./build/vk_smoke --window --frames=300   # Deterministic frame budget
```

Build: `make vk-smoke`

## Odin-Specific Patterns

- **Cannot take address of proc parameters:** Copy to a local variable first (`sl := set_layout; ... &sl`).
- **Imports:** `import vk "vendor:vulkan"`, `import glfw "vendor:glfw"`, `import "RT_Weekend:vk_ctx"`.
- **Deferred cleanup:** Use `defer vk_ctx.vulkan_context_destroy(&ctx)` and similar.
- **Temp allocator:** Use `context.temp_allocator` for transient arrays (e.g., surface format queries).
- **Dynamic arrays:** `[dynamic]cstring` with `defer delete(exts)` for extension lists.
- **`when ODIN_OS == .JS`:** Compile-time platform check for unsupported targets.

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `glfw.Init failed: Wayland: Failed to connect to display` | No Wayland compositor | Try `--platform=x11` or run from desktop session |
| `glfw.Init failed: X11: Failed to open display` | X server not reachable | Check `DISPLAY` env var |
| `glfw.VulkanSupported() is false` | Vulkan loader/ICD missing | Install Vulkan runtime |
| `vkCreateInstance failed: VK_ERROR_INCOMPATIBLE_DRIVER` | Driver/loader mismatch | Verify Vulkan install and ICD |
| `no suitable physical device` | No Vulkan GPU exposed | Check drivers, containers may lack GPU access |
| Window shows only taskbar icon (Wayland) | No buffer presented | Ensure swapchain + present loop runs |
| First-frame hang | Fence created unsignaled | Create fence with `.SIGNALED` flag |

## Integration with Ray Tracer Backend

The Vulkan compute path implements the `RenderBackendApi` vtable as the sole GPU backend:
- `RenderBackendKind.Vulkan_Compute` enum value in `raytrace/render_backend.odin`
- Backend label: `"GPU (Vulkan)"`
- `gpu_backend_vulkan.odin` contains `VulkanGPUBackend` struct and `VULKAN_RENDERER_API` vtable
- `gpu_backend_adapter.odin` wraps `GpuRendererApi` as `RenderBackendApi`
- System Info panel shows the active backend name
