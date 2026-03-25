package editor

// imgui_rl.odin — Thin delegation wrapper.
//
// All ImGui lifecycle is handled by imgui_vk_backend.odin (Vulkan).
// These procs exist so callers don't need to know which backend is active.

import rl "vendor:raylib"
import imgui "RT_Weekend:vendor/odin-imgui"

// imgui_rl_setup is a no-op: ImGui context and backends are initialised
// by imgui_vk_init() in imgui_vk_backend.odin, called from app.odin.
imgui_rl_setup :: proc() {}

imgui_rl_shutdown :: proc() {
    imgui_vk_shutdown()
}

imgui_rl_new_frame :: proc() {
    imgui_vk_begin_frame()
}

imgui_rl_render :: proc() {
    imgui_vk_end_frame()
}

imgui_rl_want_capture_mouse :: proc() -> bool {
    return imgui.GetIO().WantCaptureMouse
}

imgui_rl_want_capture_keyboard :: proc() -> bool {
    return imgui.GetIO().WantCaptureKeyboard
}

imgui_rl_mouse_pos :: proc() -> rl.Vector2 {
    mp := imgui.GetMousePos()
    return rl.Vector2{mp.x, mp.y}
}
