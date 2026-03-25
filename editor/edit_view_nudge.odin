// edit_view_nudge.odin — Keyboard nudge for selected sphere (move and radius).
// Uses app.keyboard so keyboard input is centralized; reusable from any panel that has
// access to App and EditViewState.

package editor

import "core:strings"
import "RT_Weekend:core"

MOVE_SPEED   :: f32(0.05)
RADIUS_SPEED :: f32(0.02)
MIN_RADIUS   :: f32(0.05)

// update_sphere_nudge runs nudge logic for the selected sphere using app.keyboard.
// Call from the Edit View update phase when a sphere is selected. Captures before-state
// on first keydown, applies movement/radius each frame, and pushes undo on key release.
update_sphere_nudge :: proc(app: ^App, ev: ^EditViewState) {
	if app == nil || ev == nil { return }
	if ev.nav_keys_consumed {
		ev.nudge_active = false
		return
	}
	kb := &app.keyboard
	if ev.selection_kind != .Sphere || ev.selected_idx < 0 || ev.selected_idx >= SceneManagerLen(ev.scene_mgr) {
		ev.nudge_active = false
		return
	}

	// Capture before-state on first keydown of a nudge session
	if kb.any_nudge && !ev.nudge_active {
		ev.nudge_active = true
		if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
			ev.nudge_before = sphere
		}
		ui_log_drag_start(app, "SphereNudge")
	}

	if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
		if kb.nudge_neg_z  { sphere.center[2] -= MOVE_SPEED }
		if kb.nudge_pos_z  { sphere.center[2] += MOVE_SPEED }
		if kb.nudge_neg_x  { sphere.center[0] -= MOVE_SPEED }
		if kb.nudge_pos_x  { sphere.center[0] += MOVE_SPEED }
		if kb.nudge_neg_y  { sphere.center[1] -= MOVE_SPEED }
		if kb.nudge_pos_y  { sphere.center[1] += MOVE_SPEED }
		if kb.nudge_radius_inc {
			sphere.radius += RADIUS_SPEED
		}
		if kb.nudge_radius_dec {
			sphere.radius -= RADIUS_SPEED
			if sphere.radius < MIN_RADIUS { sphere.radius = MIN_RADIUS }
		}
		SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
	}

	// Commit nudge to history when all keys released
	if !kb.any_nudge && ev.nudge_active {
		ev.nudge_active = false
		if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
			ui_log_drag_end(app, "SphereNudge")
			edit_history_push(&app.edit_history, ModifySphereAction{
				idx    = ev.selected_idx,
				before = ev.nudge_before,
				after  = sphere,
			})
			mark_scene_dirty(app)
			app_push_log(app, "Nudge sphere")
			app.r_render_pending = true
		}
	}
}
