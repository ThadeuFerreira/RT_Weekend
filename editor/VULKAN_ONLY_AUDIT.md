# Editor Vulkan-Only Audit

## Scope

- Editor startup/runtime now treats Vulkan render as mandatory in active flow.
- ImGui bindings were audited for duplicate package imports.
- Legacy Raylib modal and stale panel code paths were removed.

## Findings

- Single ImGui binding package is used across editor code: `RT_Weekend:vendor/odin-imgui`.
- No second binding package (`cimgui`, `rlImGui`, alternate Odin binding root) is imported in app code.
- `imgui_rl.odin` still renders through `imgui_impl_opengl3`, but now uses an explicit backend selector (`ImguiRendererBackend`) to prepare backend switchover.
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
- Avoid double lifetime ownership of image caches and render sessions.
- Do not assume GPU mode switching via legacy `GpuRenderer` mode APIs; active path is backend-driven.

## Remaining Integration Gap

- Full ImGui Vulkan renderer submission (`imgui_impl_vulkan`) requires command buffer/swapchain ownership in the editor frame loop.
- Current bridge has backend-selection scaffolding, but OpenGL3 submission remains the active renderer in this pass.
