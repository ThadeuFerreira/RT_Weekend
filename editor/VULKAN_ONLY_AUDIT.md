# Editor Vulkan-Only Audit

## Scope

- Editor startup/runtime now treats Vulkan render as mandatory in active flow.
- ImGui bindings were audited for duplicate package imports.
- Legacy Raylib modal and stale panel code paths were removed.

## Findings

- Single ImGui binding package is used across editor code: `RT_Weekend:vendor/odin-imgui`.
- No second binding package (`cimgui`, `rlImGui`, alternate Odin binding root) is imported in app code.
- `imgui_rl.odin` delegates to `imgui_vk_*` in `imgui_vk_backend.odin` (Vulkan + GLFW), not OpenGL.
- Legacy draw/update modal functions and stale panel handlers removed:
  - `panel_file_modal.odin`: removed `file_modal_update`, `file_modal_draw`, and Raylib-only button helpers.
  - `panel_confirm_modal.odin`: removed Raylib-only modal update/draw/button helpers.
  - `panel_stats.odin`: removed inactive GPU mode toggle/restart handler.
  - `app.odin`: removed unused `upload_render_texture`.
  - `panel_camera_preview.odin`: removed unused `draw_camera_preview_content`.

## Resource Ownership Changes

- App shutdown now calls `app_clear_image_texture_cache` so each cached `Texture_Image` is destroyed before freeing the map.
- Render session startup uses a shared helper (`app_start_render_session`) and logs deterministic Vulkan init failures instead of silently dropping to CPU.

## Raylib + ImGui + Vulkan Conflict Checklist

- Keep one owner for each GPU context path:
  - Raylib owns window + GL draw loop.
  - Vulkan compute backend owns its own Vulkan context and compute queue.
- **Startup order:** initialize the hidden Raylib window **before** `imgui_vk_init`. On some setups, creating the Raylib GL context after the Vulkan/GLFW window invalidated swapchain/WSI and led to faults in `vkAcquireNextImageKHR`.
- Avoid double lifetime ownership of image caches and render sessions.
- Do not assume GPU mode switching via legacy `GpuRenderer` mode APIs; active path is backend-driven.

## `imgui_vk_backend` / swapchain notes

- Call `imgui_impl_vulkan.LoadFunctions` before `ImGui_ImplVulkan_Init` (required when using `VK_NO_PROTOTYPES` / no static Vulkan linkage in the ImGui C++ layer).
- **Global Vulkan dispatch (`vendor:vulkan`):** `vk.load_proc_addresses_device(device)` overwrites *package-wide* function pointers. The headless compute context uses `create_logical_device(..., nil)` (no `VK_KHR_swapchain`), so `vkAcquireNextImageKHR` resolves to **null** and clobbers the UI device’s entry points. UI code must call `vk.load_proc_addresses_device(_vk.ctx.device)` before swapchain calls; compute dispatch calls `vk.load_proc_addresses_device(b.ctx.device)` at the start of `_vk_dispatch` / destroy.
- `vkAcquireNextImageKHR` must use the same conventions as `vk_ctx` (`~u64(0)` timeout, `vk.Fence(0)` for unused fence), not `max(u64)` / `{}` which can misbehave or differ from the working `vulkan_triangle` path.
- **Reset fence after a successful acquire** and before `vkQueueSubmit`. Do not reset the frame fence before `AcquireNextImageKHR` if you might return early without submitting — that leaves the fence unsignaled and the next `WaitForFences` can deadlock.
- ImGui frame order: `imgui_impl_glfw.NewFrame` → `imgui_impl_vulkan.NewFrame` → `ImGui::NewFrame`. Always call `ImGui::Render()` in `imgui_vk_end_frame` **before** any path that can return early (swapchain errors), or the next `NewFrame()` will assert.

## Remaining Integration Gap

- UI path uses `imgui_impl_vulkan` + GLFW + `vk_ctx` swapchain; ray-trace compute uses a separate headless Vulkan context in `raytrace`. Two Vulkan instances/devices by design until unified.
