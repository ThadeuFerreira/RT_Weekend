// edit_view_nudge.odin — Keyboard nudge for selected scene entities.

package editor

import "core:strings"
import "RT_Weekend:core"

MOVE_SPEED   :: f32(0.05)
RADIUS_SPEED :: f32(0.02)
MIN_RADIUS   :: f32(0.05)

// update_sphere_nudge runs nudge logic for the selected sphere, quad, or volume.
update_sphere_nudge :: proc(app: ^App, ev: ^EditViewState) {
	if app == nil || ev == nil { return }
	if ev.nav_keys_consumed {
		ev.nudge_active = false
		return
	}
	kb := &app.keyboard
	sk := ev.selection_kind
	if (sk != .Sphere && sk != .Quad && sk != .Volume) ||
	   ev.selected_idx < 0 ||
	   ev.selected_idx >= SceneManagerLen(ev.scene_mgr) {
		ev.nudge_active = false
		return
	}

	if kb.any_nudge && !ev.nudge_active {
		ev.nudge_active = true
		if e, ok := GetSceneEntity(ev.scene_mgr, ev.selected_idx); ok {
			ev.nudge_before = e
		}
		ui_log_drag_start(app, "EntityNudge")
	}

	if e, ok := GetSceneEntity(ev.scene_mgr, ev.selected_idx); ok {
		delta := [3]f32{0, 0, 0}
		if kb.nudge_neg_z { delta[2] -= MOVE_SPEED }
		if kb.nudge_pos_z { delta[2] += MOVE_SPEED }
		if kb.nudge_neg_x { delta[0] -= MOVE_SPEED }
		if kb.nudge_pos_x { delta[0] += MOVE_SPEED }
		if kb.nudge_neg_y { delta[1] -= MOVE_SPEED }
		if kb.nudge_pos_y { delta[1] += MOVE_SPEED }

		#partial switch &ent in e {
		case core.SceneSphere:
			ent.center += delta
			if ent.is_moving {
				ent.center1 += delta
			}
			if kb.nudge_radius_inc {
				ent.radius += RADIUS_SPEED
			}
			if kb.nudge_radius_dec {
				ent.radius -= RADIUS_SPEED
				if ent.radius < MIN_RADIUS { ent.radius = MIN_RADIUS }
			}
		case core.SceneQuad:
			ent.Q += delta
		case core.SceneVolume:
			ent.translate += delta
		}
		SetSceneEntity(ev.scene_mgr, ev.selected_idx, e)
		mark_viewport_visual_dirty(ev)
	}

	if !kb.any_nudge && ev.nudge_active {
		ev.nudge_active = false
		if e, ok := GetSceneEntity(ev.scene_mgr, ev.selected_idx); ok {
			ui_log_drag_end(app, "EntityNudge")
			edit_history_push(&app.edit_history, ModifyEntityAction{
				idx    = ev.selected_idx,
				before = ev.nudge_before,
				after  = e,
			})
			mark_scene_dirty(app)
			app_push_log(app, "Nudge object")
			app.r_render_pending = true
		}
	}
}
