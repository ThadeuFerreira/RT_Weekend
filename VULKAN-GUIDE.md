# Vulkan Guide

This document explains what was implemented to make the Vulkan bootstrap robust and to get a working Vulkan Hello Triangle in `vk_smoke`.

## Goals

1. Make Vulkan initialization fail cleanly when runtime components are missing.
2. Support both headless and windowed bootstrap paths.
3. Make windowed smoke tests work on Linux Wayland and X11.
4. Replace the old "clear-only" window smoke with a real graphics pipeline (Hello Triangle).

## Final Result

- `./build/vk_smoke --headless` creates instance/device/queues/sync and prints device info.
- `./build/vk_smoke --window` creates a GLFW window + Vulkan surface + swapchain and renders a triangle each frame.
- Window backend is selectable with:
  - `--platform=auto`
  - `--platform=x11`
  - `--platform=wayland`
- Deterministic frame budgeting is supported with `--frames=N`.

## High-Level Architecture

The implementation is split into focused modules:

- `vk_ctx/vulkan_context.odin`
  - Vulkan/GLFW loader init and safety checks
  - Instance creation (validation + portability support)
  - Physical device and queue-family selection
  - Logical device, queue acquisition, command pool/sync creation
  - Context teardown
- `vk_ctx/vulkan_context_window.odin`
  - Window-mode context creation (GLFW window, Vulkan surface, queues, device)
- `vk_ctx/vulkan_context_headless.odin`
  - Headless context creation
- `vk_ctx/vulkan_swapchain.odin`
  - Swapchain creation, image views, command buffer allocation
  - Present path for clear test
- `vk_ctx/vulkan_triangle.odin`
  - Hello Triangle render pass, pipeline, framebuffers
  - Per-frame acquire/record/submit/present for triangle
- `tools/vk_smoke/main.odin`
  - Smoke test CLI and mode dispatch (`--headless`, `--window`)
- `assets/shaders/hello_triangle_vk.vert(.spv)`
  - Vertex shader for triangle positions/colors
- `assets/shaders/hello_triangle_vk.frag(.spv)`
  - Fragment shader for color output

## What Was Implemented and Why

## 1) Runtime-safe Vulkan loading

Implemented in `vk_ctx/vulkan_context.odin` (`vk_load_vulkan`).

What it does:
- Initializes GLFW with a selected platform hint.
- Uses `glfw.VulkanSupported()` before relying on Vulkan symbols.
- Loads global Vulkan proc addresses from `glfw.GetInstanceProcAddress`.
- Checks `vk.GetInstanceProcAddr != nil`.
- Calls `vk.EnumerateInstanceExtensionProperties` to verify the loader is functional.

Why this matters:
- Prevents null function pointer crashes when Vulkan runtime/ICD is missing.
- Converts loader/runtime failures into explicit errors with clear messages.

## 2) Headless path that does not require a desktop server

Implemented via `vk_load_vulkan(headless=true)` with `glfw.PLATFORM_NULL`.

Why this matters:
- CI and server environments should be able to run headless bootstrap without X11/Wayland.

## 3) Portability ICD support and API version negotiation

Implemented in `create_instance` in `vk_ctx/vulkan_context.odin`.

What it does:
- Detects and enables `VK_KHR_portability_enumeration` when available.
- Sets `INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR` when required.
- Negotiates API version from loader with fallback to `VK_API_VERSION_1_0`.

Why this matters:
- Makes MoltenVK/portability stacks visible to device enumeration.
- Avoids forcing Vulkan 1.2 in bootstrap code that only needs core features.

## 4) Deterministic window backend selection

Implemented in:
- `vulkan_context_init_window(..., window_platform: c.int = glfw.ANY_PLATFORM)`
- `vk_load_vulkan(..., window_platform=...)`
- CLI options in `tools/vk_smoke/main.odin`:
  - `--platform=auto|x11|wayland`

Why this matters:
- Makes backend behavior explicit and reproducible during debugging.
- Lets you force X11 or Wayland for platform-specific validation.

## 5) Swapchain bootstrap for window mode

Implemented in `vk_ctx/vulkan_swapchain.odin`.

What it does:
- Queries surface capabilities/formats.
- Picks `B8G8R8A8_SRGB` + `SRGB_NONLINEAR` when possible.
- Uses FIFO present mode.
- Creates image views and one primary command buffer per swapchain image.
- Handles different graphics/present queue families.

Why this matters:
- Wayland compositors map windows only after the app commits/presents a buffer.
- Without swapchain + present, you can get a process and taskbar icon but no visible mapped surface.

## 6) First-frame synchronization fix (critical)

Implemented in `create_command_pool_and_sync` (`vk_ctx/vulkan_context.odin`):
- Fence is created in signaled state: `flags = {.SIGNALED}`.

Why this matters:
- Frame loop waits on the fence before first submit.
- If the first wait uses an unsignaled fence, the app can stall before first present.
- Signaled-on-create avoids first-frame deadlock.

## 7) Robust per-frame error handling

Implemented in both present paths:
- `swapchain_present_clear`
- `swapchain_present_triangle`

Behavior:
- Treats `VK_ERROR_OUT_OF_DATE_KHR` as non-fatal and returns to loop.
- Accepts `VK_SUBOPTIMAL_KHR`.

Why this matters:
- Avoids hard failures during transient surface/swapchain state changes.

## 8) Hello Triangle graphics path (new)

Implemented in `vk_ctx/vulkan_triangle.odin`.

### Resources created

`VulkanTriangleRenderer` contains:
- `VkRenderPass`
- `VkPipelineLayout`
- `VkPipeline`
- Vertex and fragment shader modules
- One framebuffer per swapchain image view

### Render pass

- One color attachment (swapchain format)
- `loadOp = CLEAR`, `storeOp = STORE`
- `initialLayout = UNDEFINED`, `finalLayout = PRESENT_SRC_KHR`
- Single graphics subpass with one color attachment reference
- External subpass dependency for color attachment output synchronization

### Graphics pipeline

- Shader stages: vertex + fragment
- No vertex buffers (vertex positions/colors generated from `gl_VertexIndex` in shader)
- Input assembly: triangle list
- Static viewport/scissor from swapchain extent
- Rasterization: fill, no culling
- Multisampling: 1 sample
- Color blend: disabled, RGBA write enabled

### Framebuffers

- One framebuffer per swapchain image view
- Each framebuffer has one color attachment (the image view)

### Per-frame draw flow

`swapchain_present_triangle` executes:
1. Wait and reset fence.
2. Acquire next image (signal `semaphore_image_available`).
3. Reset and begin command buffer.
4. Begin render pass with clear color.
5. Bind graphics pipeline.
6. `vkCmdDraw(3, 1, 0, 0)`.
7. End render pass and command buffer.
8. Submit to graphics queue:
   - Wait semaphore: `image_available`
   - Wait stage: `COLOR_ATTACHMENT_OUTPUT`
   - Signal semaphore: `render_finished`
9. Present on present queue waiting on `render_finished`.

## 9) Shader assets and SPIR-V pipeline

Added:
- `assets/shaders/hello_triangle_vk.vert`
- `assets/shaders/hello_triangle_vk.frag`
- committed SPIR-V:
  - `hello_triangle_vk.vert.spv`
  - `hello_triangle_vk.frag.spv`

Updated `Makefile` target `shaders` to compile all Vulkan shaders:
- existing `raytrace_vk.comp`
- new hello-triangle vertex/fragment shaders

## 10) `vk_smoke` CLI and run-loop improvements

Implemented in `tools/vk_smoke/main.odin`.

New options:
- `--platform=auto|x11|wayland`
- `--frames=N` (`0` means run until close)

Wayland stdin edge case handling:
- If running on Wayland and stdin is not a TTY, `PollEvents` can be skipped and a deterministic frame budget is used.
- This avoids relying on interactive stdin behavior in launcher/redirected environments.

## Build and Run

From repo root:

```bash
make shaders
make vk-smoke
```

Headless:

```bash
./build/vk_smoke --headless
./build/vk_smoke --headless --clear
./build/vk_smoke --headless --compute
```

Windowed triangle:

```bash
./build/vk_smoke --window
./build/vk_smoke --window --platform=x11
./build/vk_smoke --window --platform=wayland
./build/vk_smoke --window --frames=300
```

Non-interactive stdin test:

```bash
./build/vk_smoke --window --platform=wayland --frames=300 < /dev/null
```

## Notes and Tradeoffs

- Current swapchain recreation is intentionally minimal:
  - `OUT_OF_DATE` is tolerated, but full rebuild-on-resize is not yet wired.
- Pipeline uses static viewport/scissor based on initial swapchain extent:
  - acceptable for fixed-size smoke test window.
- No vertex/index buffers are used:
  - keeps the example minimal and focused on WSI + graphics pipeline correctness.

## Quick Troubleshooting

`glfw.Init failed: Wayland: Failed to connect to display`
- No Wayland compositor reachable in current environment.
- Try `--platform=x11` or run from a desktop session.

`glfw.Init failed: X11: Failed to open display`
- X server not reachable or `DISPLAY` invalid.

`glfw.VulkanSupported() is false`
- Vulkan loader or ICD missing/broken.

`vkCreateInstance failed: VK_ERROR_INCOMPATIBLE_DRIVER`
- Driver/loader mismatch; verify Vulkan install and ICD.

`no suitable physical device`
- No Vulkan-capable GPU exposed to the process (common in restricted/container environments).

## Summary

The Vulkan path is now a complete bootstrap + render loop:
- robust loader and instance setup,
- explicit platform control,
- swapchain and synchronization wiring,
- and an actual Vulkan graphics pipeline rendering a triangle every frame.

This moved `vk_smoke --window` from "window+surface smoke" to a true end-to-end WSI + graphics validation tool.
