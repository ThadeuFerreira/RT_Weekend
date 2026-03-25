# Raytrace Vulkan-Only Audit

## Policy Changes

- `start_render_auto` no longer falls back to CPU on GPU init failure.
- Vulkan init failure now returns `nil` for deterministic caller handling.
- Runtime callsites were updated to treat this as a hard failure in active editor/headless flow.

## Allocation and Resource Simplifications

- Removed redundant GPU-session CPU pixel buffer allocation in `start_render_auto`.
- Added direct PNG write path for already gamma-corrected RGB bytes:
  - `write_rgb8_to_png(width, height, file_name, rgb_data)`.
- Headless path now performs backend final readback to RGBA8, converts to RGB8, and writes PNG directly.

## Backend Surface Notes

- Legacy comments and behavior implying CPU fallback were updated/removed.
- Active startup paths use Vulkan rendering policy by default.

## Risks

- Callers must handle `nil` sessions from failed Vulkan init.
- Any downstream code expecting `session.pixel_buffer` in GPU path must avoid that assumption.
