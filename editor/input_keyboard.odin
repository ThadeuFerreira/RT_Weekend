// input_keyboard.odin — Singleton-style keyboard state for the app.
// Raylib key state is read once per frame in keyboard_update; the rest of the app
// uses KeyboardState only, so key handling is centralized and reusable.

package editor

import rl "vendor:raylib"

// KeyboardState holds the current frame's key state. Updated once per frame by keyboard_update.
// Use this instead of calling rl.IsKeyDown / rl.IsKeyPressed directly so all keyboard handling
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

// keyboard_update reads Raylib key state and fills state. Call once per frame at the start of the input phase.
keyboard_update :: proc(state: ^KeyboardState) {
	if state == nil { return }
	state.nudge_neg_z      = rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)
	state.nudge_pos_z     = rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)
	state.nudge_neg_x     = rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)
	state.nudge_pos_x     = rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT)
	state.nudge_neg_y     = rl.IsKeyDown(.Q)
	state.nudge_pos_y     = rl.IsKeyDown(.E)
	state.nudge_radius_inc = rl.IsKeyDown(.EQUAL) || rl.IsKeyDown(.KP_ADD)
	state.nudge_radius_dec = rl.IsKeyDown(.MINUS) || rl.IsKeyDown(.KP_SUBTRACT)
	state.any_nudge = state.nudge_neg_z || state.nudge_pos_z ||
		state.nudge_neg_x || state.nudge_pos_x ||
		state.nudge_neg_y || state.nudge_pos_y ||
		state.nudge_radius_inc || state.nudge_radius_dec
}
