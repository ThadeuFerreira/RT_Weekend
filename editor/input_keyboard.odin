// input_keyboard.odin — Singleton-style keyboard state for the app.
// GLFW key state is read once per frame in keyboard_update; the rest of the app
// uses KeyboardState only, so key handling is centralized and reusable.

package editor

import glfw "vendor:glfw"

// KeyboardState holds the current frame's key state. Updated once per frame by keyboard_update.
// Use this instead of calling vk_is_key_down directly so all keyboard handling
// goes through one place and can be reused (nudge, shortcuts, etc.).
KeyboardState :: struct {
	// Nudge (object move/radius): W/S, A/D, Q/E, +/- (and arrow/numpad aliases)
	nudge_neg_z: bool, // W, UP
	nudge_pos_z: bool, // S, DOWN
	nudge_neg_x: bool, // A, LEFT
	nudge_pos_x: bool, // D, RIGHT
	nudge_neg_y: bool, // Q
	nudge_pos_y: bool, // E
	nudge_radius_inc: bool, // EQUAL, KP_ADD
	nudge_radius_dec: bool, // MINUS, KP_SUBTRACT

	// Derived: true if any nudge key is down (avoids repeating long OR in callers).
	any_nudge: bool,
}

// keyboard_update reads GLFW key state and fills state. Call once per frame at the start of the input phase.
keyboard_update :: proc(state: ^KeyboardState) {
	if state == nil { return }
	state.nudge_neg_z      = vk_is_key_down(glfw.KEY_W) || vk_is_key_down(glfw.KEY_UP)
	state.nudge_pos_z     = vk_is_key_down(glfw.KEY_S) || vk_is_key_down(glfw.KEY_DOWN)
	state.nudge_neg_x     = vk_is_key_down(glfw.KEY_A) || vk_is_key_down(glfw.KEY_LEFT)
	state.nudge_pos_x     = vk_is_key_down(glfw.KEY_D) || vk_is_key_down(glfw.KEY_RIGHT)
	state.nudge_neg_y     = vk_is_key_down(glfw.KEY_Q)
	state.nudge_pos_y     = vk_is_key_down(glfw.KEY_E)
	state.nudge_radius_inc = vk_is_key_down(glfw.KEY_EQUAL) || vk_is_key_down(glfw.KEY_KP_ADD)
	state.nudge_radius_dec = vk_is_key_down(glfw.KEY_MINUS) || vk_is_key_down(glfw.KEY_KP_SUBTRACT)
	state.any_nudge = state.nudge_neg_z || state.nudge_pos_z ||
		state.nudge_neg_x || state.nudge_pos_x ||
		state.nudge_neg_y || state.nudge_pos_y ||
		state.nudge_radius_inc || state.nudge_radius_dec
}
