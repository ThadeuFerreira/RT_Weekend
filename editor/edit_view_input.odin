// edit_view_input.odin — Edit View input handling: phase enum, rects, and per-phase handlers.
// update_viewport_content delegates to get_edit_view_input_phase + switch and these handlers.

package editor

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import glfw "vendor:glfw"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

AABB_MAX_DEPTH_CAP :: 20
RMB_DRAG_THRESHOLD :: f32(5.0)
EDIT_PROPS_H       :: f32(120) // height of properties strip at bottom of legacy edit view

EditViewRects :: struct {
	vp_rect, props_rect: rl.Rectangle,
	btn_add, btn_del, btn_frustum, btn_focal: rl.Rectangle,
	btn_aabb, btn_sel, btn_bvh, btn_d_plus, btn_d_minus: rl.Rectangle,
	btn_bg, swatch_bg, popover_bg: rl.Rectangle,
	btn_fromview, btn_render: rl.Rectangle,
}

edit_view_rects_from_content :: proc(content: rl.Rectangle) -> EditViewRects {
	r: EditViewRects
	r.btn_add      = rl.Rectangle{content.x + 8, content.y + 5, ADD_DROPDOWN_W, 22}
	r.btn_del      = rl.Rectangle{content.x + 106, content.y + 5, 60, 22}
	r.btn_frustum  = rl.Rectangle{content.x + 174, content.y + 5, 56, 22}
	r.btn_focal    = rl.Rectangle{content.x + 234, content.y + 5, 40, 22}
	r.btn_aabb, r.btn_sel, r.btn_bvh, r.btn_d_plus, r.btn_d_minus = edit_view_aabb_toolbar_rects(content)
	r.btn_bg, r.swatch_bg, r.popover_bg = edit_view_background_rects(content)
	r.btn_fromview = rl.Rectangle{content.x + content.width - 178, content.y + 5, 82, 22}
	r.btn_render   = rl.Rectangle{content.x + content.width - 90, content.y + 5, 82, 22}
	r.vp_rect = rl.Rectangle{
		content.x,
		content.y + EDIT_TOOLBAR_H,
		content.width,
		content.height - EDIT_TOOLBAR_H - EDIT_PROPS_H,
	}
	r.props_rect = rl.Rectangle{
		content.x,
		content.y + content.height - EDIT_PROPS_H,
		content.width,
		EDIT_PROPS_H,
	}
	return r
}

EditViewInputPhase :: enum {
	ContextMenu,
	CamRotDrag,
	CamBodyDrag,
	CamPropDrag,
	SpherePropDrag,
	ViewportObjectDrag,
	Toolbar,
	ViewportOrbitAndPick,
}

get_edit_view_input_phase :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb_pressed: bool, rects: ^EditViewRects) -> EditViewInputPhase {
	switch true {
	case ev.ctx_menu_open:
		return .ContextMenu
	case ev.cam_rot_drag_axis >= 0:
		return .CamRotDrag
	case ev.cam_drag_active:
		return .CamBodyDrag
	case ev.cam_prop_drag_idx >= 0:
		return .CamPropDrag
	case ev.prop_drag_idx >= 0:
		return .SpherePropDrag
	case ev.drag_obj_active:
		return .ViewportObjectDrag
	case ev.bg_drag_idx >= 0:
		return .Toolbar
	case lmb_pressed && rl.CheckCollisionPointRec(mouse, rects.btn_bg):
		return .Toolbar
	case lmb_pressed && ev.bg_picker_open && rl.CheckCollisionPointRec(mouse, rects.popover_bg):
		return .Toolbar
	case lmb_pressed && rl.CheckCollisionPointRec(mouse, rects.btn_frustum):
		return .Toolbar
	case lmb_pressed && rl.CheckCollisionPointRec(mouse, rects.btn_focal):
		return .Toolbar
	case lmb_pressed && rl.CheckCollisionPointRec(mouse, rects.btn_aabb):
		return .Toolbar
	case lmb_pressed && ev.show_aabbs && rl.CheckCollisionPointRec(mouse, rects.btn_sel):
		return .Toolbar
	case lmb_pressed && rl.CheckCollisionPointRec(mouse, rects.btn_bvh):
		return .Toolbar
	case lmb_pressed && ev.show_bvh_hierarchy && rl.CheckCollisionPointRec(mouse, rects.btn_d_plus):
		return .Toolbar
	case lmb_pressed && ev.show_bvh_hierarchy && rl.CheckCollisionPointRec(mouse, rects.btn_d_minus):
		return .Toolbar
	case lmb_pressed:
		dd_rect, _, _ := edit_view_add_dropdown_rects(rects.btn_add)
		switch true {
		case ev.add_dropdown_open && rl.CheckCollisionPointRec(mouse, dd_rect),
		     rl.CheckCollisionPointRec(mouse, rects.btn_add),
		     (ev.selection_kind == .Sphere || ev.selection_kind == .Quad || ev.selection_kind == .Volume) && ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, rects.btn_del),
		     rl.CheckCollisionPointRec(mouse, rects.btn_fromview),
		     app.finished && rl.CheckCollisionPointRec(mouse, rects.btn_render):
			return .Toolbar
		}
	}
	return .ViewportOrbitAndPick
}

_vec_norm :: proc(v: [3]f32) -> [3]f32 {
	len_sq := rt.vector_length_squared(v)
	if len_sq <= 1e-8 { return {0, 0, 0} }
	inv := 1.0 / math.sqrt(len_sq)
	return {v[0] * inv, v[1] * inv, v[2] * inv}
}

_free_fly_apply_motion :: proc(ev: ^EditViewState, mouse_in_vp, rmb_down: bool) {
	ev.nav_keys_consumed = false

	// Mouse wheel (viewport-only); arrow/WASD/EQ keys work regardless of mouse position.
	wheel := mouse_in_vp ? vk_get_wheel_delta() : 0
	if wheel != 0 {
		if wheel > 0 {
			ev.speed_factor *= 1.18
		} else {
			ev.speed_factor /= 1.18
		}
		ev.speed_factor = clamp(ev.speed_factor, f32(0.05), f32(50.0))
	}

	forward_v := free_fly_forward(ev.fly_yaw, ev.fly_pitch)
	forward := [3]f32{forward_v.x, forward_v.y, forward_v.z}
	right := _vec_norm({forward[2], 0, -forward[0]})
	up := [3]f32{0, 1, 0}
	move := [3]f32{0, 0, 0}

	if (rmb_down && vk_is_key_down(glfw.KEY_W)) || vk_is_key_down(glfw.KEY_UP) { move += forward }
	if (rmb_down && vk_is_key_down(glfw.KEY_S)) || vk_is_key_down(glfw.KEY_DOWN) { move -= forward }
	if (rmb_down && vk_is_key_down(glfw.KEY_D)) || vk_is_key_down(glfw.KEY_RIGHT) { move += right }
	if (rmb_down && vk_is_key_down(glfw.KEY_A)) || vk_is_key_down(glfw.KEY_LEFT) { move -= right }
	if vk_is_key_down(glfw.KEY_E) || vk_is_key_down(glfw.KEY_PAGE_UP) { move += up }
	if vk_is_key_down(glfw.KEY_Q) || vk_is_key_down(glfw.KEY_PAGE_DOWN) { move -= up }

	if rt.vector_length_squared(move) <= 1e-8 { return }
	ev.nav_keys_consumed = true
	move = _vec_norm(move)
	modifier := f32(1.0)
	if vk_is_key_down(glfw.KEY_LEFT_SHIFT) || vk_is_key_down(glfw.KEY_RIGHT_SHIFT) {
		modifier *= 4.0
	}
	if vk_is_key_down(glfw.KEY_LEFT_CONTROL) || vk_is_key_down(glfw.KEY_RIGHT_CONTROL) {
		modifier *= 0.2
	}
	step := move * ev.move_speed * ev.speed_factor * modifier * vk_get_frame_time()
	if ev.lock_axis_x { step[0] = 0 }
	if ev.lock_axis_y { step[1] = 0 }
	if ev.lock_axis_z { step[2] = 0 }
	ev.fly_lookfrom += step
}

handle_context_menu_input :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2) {
	_ts := ui_trace_handler_begin("handle_context_menu_input"); defer ui_trace_handler_end(_ts)
	app.input_consumed = true
	if vk_is_mouse_pressed(glfw.MOUSE_BUTTON_LEFT) {
		items := ctx_menu_build_items(app, ev)
		rect  := ctx_menu_screen_rect(app, ev)
		if rl.CheckCollisionPointRec(mouse, rect) {
			local_y := mouse.y - rect.y
			ey: f32 = 0
			for &entry in items {
				ih := entry_height(entry)
				if !entry.separator && !entry.disabled && local_y >= ey && local_y < ey + ih {
					if len(entry.cmd_id) > 0 {
						cmd_execute(app, entry.cmd_id)
					} else {
						switch entry.label {
						case "Add Sphere":
							AppendDefaultSphere(ev.scene_mgr)
							new_idx := SceneManagerLen(ev.scene_mgr) - 1
							ev.selection_kind = .Sphere
							ev.selected_idx   = new_idx
							if e, ok := GetSceneEntity(ev.scene_mgr, new_idx); ok {
								edit_history_push(&app.edit_history, AddEntityAction{idx = new_idx, entity = e})
								mark_scene_dirty(app)
								app_push_log(app, "Add sphere")
							}
							app.r_render_pending = true
						case "Add Quad":
							AppendDefaultQuad(ev.scene_mgr)
							new_idx := SceneManagerLen(ev.scene_mgr) - 1
							ev.selection_kind = .Quad
							ev.selected_idx   = new_idx
							if e, ok := GetSceneEntity(ev.scene_mgr, new_idx); ok {
								edit_history_push(&app.edit_history, AddEntityAction{idx = new_idx, entity = e})
								mark_scene_dirty(app)
								app_push_log(app, "Add quad")
							}
							app.r_render_pending = true
						case "Add Volume":
							box_min, box_max, trans := default_volume_from_scene_scale(ev.scene_mgr)
							new_vol := core.SceneVolume{
								box_min      = box_min,
								box_max      = box_max,
								rotate_y_deg = 0,
								translate    = trans,
								density      = 0.02,
								albedo       = {0.8, 0.8, 0.8},
							}
							InsertEntityAt(ev.scene_mgr, SceneManagerLen(ev.scene_mgr), core.SceneEntity(new_vol))
							new_idx := SceneManagerLen(ev.scene_mgr) - 1
							ev.selection_kind = .Volume
							ev.selected_idx   = new_idx
							if e, ok := GetSceneEntity(ev.scene_mgr, new_idx); ok {
								edit_history_push(&app.edit_history, AddEntityAction{idx = new_idx, entity = e})
								mark_scene_dirty(app)
								app_push_log(app, "Add volume")
							}
							app.r_render_pending = true
						case "Delete":
							del_idx := ev.selected_idx
							if del_idx >= 0 && del_idx < SceneManagerLen(ev.scene_mgr) {
								if e, ok := GetSceneEntity(ev.scene_mgr, del_idx); ok {
									edit_history_push(&app.edit_history, DeleteEntityAction{idx = del_idx, entity = e})
									OrderedRemove(ev.scene_mgr, del_idx)
									mark_scene_dirty(app)
									app_push_log(app, "Delete object")
								}
								ev.selection_kind = .None
								ev.selected_idx   = -1
								app.r_render_pending = true
							}
						}
					}
					break
				}
				ey += ih
			}
		}
		ev.ctx_menu_open = false
	} else if vk_is_key_pressed(glfw.KEY_ESCAPE) {
		ev.ctx_menu_open = false
	}
}

handle_cam_rot_drag :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb: bool) {
	_ts := ui_trace_handler_begin("handle_cam_rot_drag"); defer ui_trace_handler_end(_ts)
	if !lmb {
		ui_log_drag_end(app, "CamRotation")
		edit_history_push(&app.edit_history, ModifyCameraAction{
			before = ev.cam_drag_before_params,
			after  = app.c_camera_params,
		})
		mark_scene_dirty(app)
		ev.cam_rot_drag_axis = -1
		vk_set_cursor(.Default)
		app.r_render_pending = true
	} else {
		dx := mouse.x - ev.cam_rot_drag_start_x
		sf := ev.cam_drag_start_lookfrom
		sa := ev.cam_drag_start_lookat
		forward := rl.Vector3{sa.x - sf.x, sa.y - sf.y, sa.z - sf.z}
		axis_vec: rl.Vector3
		switch ev.cam_rot_drag_axis {
		case 0: axis_vec = {1, 0, 0}
		case 1: axis_vec = {0, 1, 0}
		case 2: axis_vec = {0, 0, 1}
		case: axis_vec = {0, 1, 0}
		}
		new_forward := rl.Vector3RotateByAxisAngle(forward, axis_vec, dx * 0.005)
		app.c_camera_params.lookat = {
			sf.x + new_forward.x,
			sf.y + new_forward.y,
			sf.z + new_forward.z,
		}
	}
}

handle_cam_body_drag :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb: bool, rects: ^EditViewRects) {
	_ts := ui_trace_handler_begin("handle_cam_body_drag"); defer ui_trace_handler_end(_ts)
	if !lmb {
		ui_log_drag_end(app, "CamBody")
		edit_history_push(&app.edit_history, ModifyCameraAction{
			before = ev.cam_drag_before_params,
			after  = app.c_camera_params,
		})
		mark_scene_dirty(app)
		ev.cam_drag_active = false
		app.r_render_pending = true
	} else {
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, rects.vp_rect, false); ok {
			if xz, ok2 := ray_hit_plane_y(ray, ev.cam_drag_plane_y); ok2 {
				dx := xz.x - ev.cam_drag_start_hit_xz[0]
				dz := xz.y - ev.cam_drag_start_hit_xz[1]
				if ev.lock_axis_x { dx = 0 }
				if ev.lock_axis_z { dz = 0 }
				app.c_camera_params.lookfrom[0] = ev.cam_drag_start_lookfrom.x + dx
				app.c_camera_params.lookfrom[2] = ev.cam_drag_start_lookfrom.z + dz
				app.c_camera_params.lookat[0]   = ev.cam_drag_start_lookat.x + dx
				app.c_camera_params.lookat[2]   = ev.cam_drag_start_lookat.z + dz
			}
		}
	}
}

handle_cam_prop_drag :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb: bool) {
	_ts := ui_trace_handler_begin("handle_cam_prop_drag"); defer ui_trace_handler_end(_ts)
	DEG2RAD :: f32(math.PI / 180.0)
	if !lmb {
		ui_log_drag_end(app, "CamProp")
		edit_history_push(&app.edit_history, ModifyCameraAction{
			before = ev.cam_drag_before_params,
			after  = app.c_camera_params,
		})
		mark_scene_dirty(app)
		ev.cam_prop_drag_idx = -1
		vk_set_cursor(.Default)
		app.r_render_pending = true
	} else {
		delta := mouse.x - ev.cam_prop_drag_start_x
		sf := ev.cam_drag_start_lookfrom
		sa := ev.cam_drag_start_lookat
		s_yaw, s_pitch, s_dist := cam_forward_angles(
			{sf.x, sf.y, sf.z}, {sa.x, sa.y, sa.z})
		switch ev.cam_prop_drag_idx {
		case 0:
			d := delta * 0.02
			if ev.lock_axis_x { d = 0 }
			app.c_camera_params.lookfrom[0] = sf.x + d
			app.c_camera_params.lookat[0]   = sa.x + d
		case 1:
			d := delta * 0.02
			if ev.lock_axis_y { d = 0 }
			app.c_camera_params.lookfrom[1] = sf.y + d
			app.c_camera_params.lookat[1]   = sa.y + d
		case 2:
			d := delta * 0.02
			if ev.lock_axis_z { d = 0 }
			app.c_camera_params.lookfrom[2] = sf.z + d
			app.c_camera_params.lookat[2]   = sa.z + d
		case 3:
			new_yaw := s_yaw + delta * 0.5 * DEG2RAD
			app.c_camera_params.lookat = lookat_from_angles(
				{sf.x, sf.y, sf.z}, new_yaw, s_pitch, s_dist)
		case 4:
			new_pitch := clamp(s_pitch + delta * 0.3 * DEG2RAD,
				f32(-math.PI * 0.45), f32(math.PI * 0.45))
			app.c_camera_params.lookat = lookat_from_angles(
				{sf.x, sf.y, sf.z}, s_yaw, new_pitch, s_dist)
		case 5:
			new_dist := max(s_dist + delta * 0.05, f32(1.0))
			app.c_camera_params.lookat = lookat_from_angles(
				{sf.x, sf.y, sf.z}, s_yaw, s_pitch, new_dist)
		case 6:
			new_roll := clamp(ev.cam_prop_drag_start_val + delta * 0.005,
				f32(-math.PI), f32(math.PI))
			app.c_camera_params.vup = compute_vup_from_forward_and_roll(
				app.c_camera_params.lookfrom, app.c_camera_params.lookat, new_roll)
		case:
		}
	}
}

handle_sphere_prop_drag :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb: bool) {
	_ts := ui_trace_handler_begin("handle_sphere_prop_drag"); defer ui_trace_handler_end(_ts)
	if !lmb {
		ui_log_drag_end(app, "SphereProp")
		ev.prop_drag_idx = -1
		vk_set_cursor(.Default)
	} else if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
		delta := mouse.x - ev.prop_drag_start_x
		if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
			switch ev.prop_drag_idx {
			case 0: sphere.center[0] = ev.prop_drag_start_val + delta * 0.01
			case 1: sphere.center[1] = ev.prop_drag_start_val + delta * 0.01
			case 2: sphere.center[2] = ev.prop_drag_start_val + delta * 0.01
			case 3:
				sphere.radius = ev.prop_drag_start_val + delta * 0.005
				if sphere.radius < 0.05 { sphere.radius = 0.05 }
			case:
			}
			SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
		}
	}
}

handle_viewport_object_drag :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb: bool, rects: ^EditViewRects) {
	_ts := ui_trace_handler_begin("handle_viewport_object_drag"); defer ui_trace_handler_end(_ts)
	if !lmb {
		ev.drag_obj_active = false
		if ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
			if after, ok := GetSceneEntity(ev.scene_mgr, ev.selected_idx); ok {
				kind_name := core.entity_kind_name(after)
				ui_log_drag_end(app, kind_name)
				edit_history_push(&app.edit_history, ModifyEntityAction{
					idx = ev.selected_idx, before = ev.drag_before, after = after,
				})
				mark_scene_dirty(app)
				app_push_log(app, fmt.tprintf("Move %s", kind_name))
				app.r_render_pending = true
			}
		}
	} else if ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, rects.vp_rect, false); ok {
			if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
				if e, ok3 := GetSceneEntity(ev.scene_mgr, ev.selected_idx); ok3 {
					pos := core.entity_position(e)
					new_pos := [3]f32{xz.x - ev.drag_offset_xz[0], pos[1], xz.y - ev.drag_offset_xz[1]}
					core.entity_set_position(&e, new_pos)
					SetSceneEntity(ev.scene_mgr, ev.selected_idx, e)
					mark_viewport_visual_dirty(ev)
				}
			}
		}
	}
}

// try_start_entity_drag picks the closest entity under ray and begins an XZ drag if hit.
// Returns true if a drag was started (or deselection occurred), false if nothing was hit.
try_start_entity_drag :: proc(app: ^App, ev: ^EditViewState, ray: rl.Ray) -> bool {
	pick_kind, pick_idx, _ := PickClosestEntity(ev.scene_mgr, ray)
	if pick_idx < 0 { return false }
	ev.selection_kind  = pick_kind
	ev.selected_idx    = pick_idx
	ev.drag_obj_active = true
	if e, ok := GetSceneEntity(ev.scene_mgr, pick_idx); ok {
		ev.drag_before  = e
		pos := core.entity_position(e)
		ev.drag_plane_y = core.entity_drag_plane_y(e)
		if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
			ev.drag_offset_xz = {xz.x - pos[0], xz.y - pos[2]}
		} else {
			ev.drag_offset_xz = {0, 0}
		}
	}
	ui_log_drag_start(app, core.entity_kind_name(ev.drag_before))
	return true
}

handle_toolbar_input :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, rects: ^EditViewRects) {
	_ts := ui_trace_handler_begin("handle_toolbar_input"); defer ui_trace_handler_end(_ts)
	lmb := vk_is_mouse_down(glfw.MOUSE_BUTTON_LEFT)
	lmb_pressed := vk_is_mouse_pressed(glfw.MOUSE_BUTTON_LEFT)

	// Background color picker: ongoing drag or click to open/close/select
	if ev.bg_drag_idx >= 0 {
		if !lmb {
			ev.bg_drag_idx = -1
			vk_set_cursor(.Default)
		} else {
			delta := mouse.x - ev.bg_drag_start_x
			val := clamp(ev.bg_drag_start_val + delta * 0.002, 0, 1)
			app.c_camera_params.background[ev.bg_drag_idx] = val
			mark_scene_dirty(app)
			app.r_render_pending = true
			vk_set_cursor(.ResizeEW)
		}
		return
	}
	if ev.bg_picker_open {
		if lmb_pressed {
			in_popover := rl.CheckCollisionPointRec(mouse, rects.popover_bg)
			in_btn_bg  := rl.CheckCollisionPointRec(mouse, rects.btn_bg)
			if in_btn_bg {
				ev.bg_picker_open = false
			} else if !in_popover {
				ev.bg_picker_open = false
			} else {
				for i in 0..<BG_PRESET_COUNT {
					if rl.CheckCollisionPointRec(mouse, bg_preset_item_rect(rects.popover_bg, i)) {
						app.c_camera_params.background = bg_preset_color(i)
						mark_scene_dirty(app)
						app.r_render_pending = true
						ev.bg_picker_open = false
						return
					}
				}
			}
		}
		return
	}
	if lmb_pressed && rl.CheckCollisionPointRec(mouse, rects.btn_bg) {
		ev.bg_picker_open = true
		return
	}

	// Dispatch by which button was hit (switch on first match)
	switch {
	case rl.CheckCollisionPointRec(mouse, rects.btn_frustum):
		ev.show_frustum_gizmo = !ev.show_frustum_gizmo
		ui_log_click(app, "Frustum")
	case rl.CheckCollisionPointRec(mouse, rects.btn_focal):
		ev.show_focal_indicator = !ev.show_focal_indicator
		ui_log_click(app, "Focal")
	case rl.CheckCollisionPointRec(mouse, rects.btn_aabb):
		ev.show_aabbs = !ev.show_aabbs
		ui_log_click(app, "AABB")
	case ev.show_aabbs && rl.CheckCollisionPointRec(mouse, rects.btn_sel):
		ev.aabb_selected_only = !ev.aabb_selected_only
		ui_log_click(app, "AABB Sel")
	case rl.CheckCollisionPointRec(mouse, rects.btn_bvh):
		ev.show_bvh_hierarchy = !ev.show_bvh_hierarchy
		ui_log_click(app, "BVH")
		if !ev.show_bvh_hierarchy && ev.viz_bvh_root != nil {
			rt.free_bvh(ev.viz_bvh_root)
			ev.viz_bvh_root = nil
		}
	case ev.show_bvh_hierarchy && rl.CheckCollisionPointRec(mouse, rects.btn_d_plus):
		if ev.aabb_max_depth < AABB_MAX_DEPTH_CAP { ev.aabb_max_depth += 1 }
	case ev.show_bvh_hierarchy && rl.CheckCollisionPointRec(mouse, rects.btn_d_minus):
		if ev.aabb_max_depth > -1 { ev.aabb_max_depth -= 1 }
	case: {
		dd_rect, sphere_item, quad_item := edit_view_add_dropdown_rects(rects.btn_add)
		in_dropdown := rl.CheckCollisionPointRec(mouse, dd_rect)
		in_btn_add  := rl.CheckCollisionPointRec(mouse, rects.btn_add)

		if ev.add_dropdown_open {
			if vk_is_mouse_pressed(glfw.MOUSE_BUTTON_LEFT) {
				switch {
				case rl.CheckCollisionPointRec(mouse, sphere_item):
					ev.add_dropdown_open = false
					AppendDefaultSphere(ev.scene_mgr)
					new_idx := SceneManagerLen(ev.scene_mgr) - 1
					ev.selection_kind = .Sphere
					ev.selected_idx   = new_idx
					if e, ok := GetSceneEntity(ev.scene_mgr, new_idx); ok {
						edit_history_push(&app.edit_history, AddEntityAction{idx = new_idx, entity = e})
						mark_scene_dirty(app)
						app_push_log(app, "Add sphere")
					}
					app.r_render_pending = true
				case rl.CheckCollisionPointRec(mouse, quad_item):
					ev.add_dropdown_open = false
					AppendDefaultQuad(ev.scene_mgr)
					new_idx := SceneManagerLen(ev.scene_mgr) - 1
					ev.selection_kind = .Quad
					ev.selected_idx   = new_idx
					if e, ok := GetSceneEntity(ev.scene_mgr, new_idx); ok {
						edit_history_push(&app.edit_history, AddEntityAction{idx = new_idx, entity = e})
						mark_scene_dirty(app)
						app_push_log(app, "Add quad")
					}
					app.r_render_pending = true
				case !in_dropdown && !in_btn_add:
					ev.add_dropdown_open = false
				}
			}
		} else if rl.CheckCollisionPointRec(mouse, rects.btn_add) {
			ev.add_dropdown_open = true
		} else if (ev.selection_kind == .Sphere || ev.selection_kind == .Quad || ev.selection_kind == .Volume) && ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, rects.btn_del) {
			del_idx := ev.selected_idx
			if e, ok := GetSceneEntity(ev.scene_mgr, del_idx); ok {
				edit_history_push(&app.edit_history, DeleteEntityAction{idx = del_idx, entity = e})
				mark_scene_dirty(app)
				app_push_log(app, "Delete object")
				OrderedRemove(ev.scene_mgr, del_idx)
			}
			ev.selection_kind = .None
			ev.selected_idx   = -1
			app.r_render_pending = true
		} else if rl.CheckCollisionPointRec(mouse, rects.btn_fromview) {
			ui_log_click(app, "FromView")
			before := app.c_camera_params
			lookfrom, lookat := get_orbit_camera_pose(ev)
			app.c_camera_params.lookfrom = lookfrom
			app.c_camera_params.lookat   = lookat
			edit_history_push(&app.edit_history, ModifyCameraAction{before = before, after = app.c_camera_params})
			mark_scene_dirty(app)
			app.r_render_pending = true
		} else if app.finished && rl.CheckCollisionPointRec(mouse, rects.btn_render) {
			ui_log_click(app, "Render")
			rt.free_world_volumes(app.r_world)
			delete(app.r_world)
			app.r_world = app_rebuild_render_world(app)
			width, height, res_ok := calculate_render_dimensions(app)
			samples, samp_ok := strconv.parse_int(app.r_samples_input)
			if !res_ok {
				h, h_ok := strconv.parse_int(strings.trim_space(app.r_height_input))
				if !h_ok || h <= 0 {
					app_push_log(app, "Invalid height. Must be a positive integer.")
				} else {
					if h < MIN_RENDER_HEIGHT {
						app_push_log(app, fmt.tprintf("Warning: Height %d below minimum (%d)", h, MIN_RENDER_HEIGHT))
					} else if h > MAX_RENDER_HEIGHT {
						app_push_log(app, fmt.tprintf("Warning: Height %d exceeds maximum (%d)", h, MAX_RENDER_HEIGHT))
					}
					if width < MIN_RENDER_WIDTH {
						app_push_log(app, fmt.tprintf("Warning: Width %d below minimum (%d)", width, MIN_RENDER_WIDTH))
					} else if width > MAX_RENDER_WIDTH {
						app_push_log(app, fmt.tprintf("Warning: Width %d exceeds maximum (%d)", width, MAX_RENDER_WIDTH))
					}
				}
			} else if !samp_ok || samples <= 0 {
				app_push_log(app, "Invalid samples count. Must be a positive integer.")
			} else {
				restart_render_with_settings(app, width, height, samples)
			}
		}
	}
	}
	if g_app != nil { g_app.input_consumed = true }
}


handle_viewport_orbit_and_pick :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb_pressed: bool, rects: ^EditViewRects) {
	_ts := ui_trace_handler_begin("handle_viewport_orbit_and_pick"); defer ui_trace_handler_end(_ts)
	mouse_in_vp := rl.CheckCollisionPointRec(mouse, rects.vp_rect)
	rmb_pressed := vk_is_mouse_pressed(glfw.MOUSE_BUTTON_RIGHT)
	rmb_down    := vk_is_mouse_down(glfw.MOUSE_BUTTON_RIGHT)
	rmb_release := vk_is_mouse_released(glfw.MOUSE_BUTTON_RIGHT)
	if mouse_in_vp && vk_is_key_pressed(glfw.KEY_F) {
		ev.camera_mode = ev.camera_mode == .FreeFly ? .Orbit : .FreeFly
	}

	if rmb_pressed && mouse_in_vp {
		ev.rmb_press_pos = mouse
		ev.rmb_drag_dist = 0
		ev.rmb_held      = false
		ev.last_mouse    = mouse
	}
	if rmb_down && mouse_in_vp {
		delta := rl.Vector2{mouse.x - ev.rmb_press_pos.x, mouse.y - ev.rmb_press_pos.y}
		dist  := math.sqrt(delta.x*delta.x + delta.y*delta.y)
		if dist > ev.rmb_drag_dist { ev.rmb_drag_dist = dist }
		if ev.rmb_drag_dist >= RMB_DRAG_THRESHOLD { ev.rmb_held = true }
		if ev.rmb_held {
			orb_delta := rl.Vector2{mouse.x - ev.last_mouse.x, mouse.y - ev.last_mouse.y}
			if ev.camera_mode == .FreeFly {
				ev.fly_yaw   += orb_delta.x * 0.005
				ev.fly_pitch += -orb_delta.y * 0.005
			} else {
				ev.camera_yaw   += orb_delta.x * 0.005
				ev.camera_pitch += -orb_delta.y * 0.005
				ev.camera_pitch = clamp(ev.camera_pitch, -math.PI/2 + 0.01, math.PI/2 - 0.01)
			}
		}
		ev.last_mouse = mouse
	}
	if ev.camera_mode == .FreeFly {
		_free_fly_apply_motion(ev, mouse_in_vp, rmb_down)
	}
	if rmb_release && mouse_in_vp && ev.rmb_drag_dist < RMB_DRAG_THRESHOLD {
		update_orbit_camera(ev)
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, rects.vp_rect, false); ok {
			pick_kind, pick_idx, _ := PickClosestEntity(ev.scene_mgr, ray)
			if pick_idx >= 0 {
				ev.selection_kind = pick_kind
				ev.selected_idx   = pick_idx
			}
			ev.ctx_menu_open    = true
			ev.ctx_menu_pos     = mouse
			ev.ctx_menu_hit_idx = pick_idx
			app.input_consumed  = true
		}
	}
	if !rmb_down { ev.rmb_held = false }

	if mouse_in_vp {
		if ev.camera_mode != .FreeFly {
			ev.orbit_distance -= vk_get_wheel_delta() * 0.8
		}
	}

	if lmb_pressed && mouse_in_vp {
		update_orbit_camera(ev)
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, rects.vp_rect); ok {
			cam_lookfrom := app.c_camera_params.lookfrom
			cam_pos_v3   := rl.Vector3{cam_lookfrom[0], cam_lookfrom[1], cam_lookfrom[2]}
			vp_offset    := rl.Vector2{rects.vp_rect.x, rects.vp_rect.y}

			if ev.selection_kind == .Camera {
				ring := pick_rotation_ring(mouse, vp_offset, cam_pos_v3, ev.cam3d)
				switch {
				case ring >= 0:
					ev.cam_drag_before_params  = app.c_camera_params
					ev.cam_rot_drag_axis       = ring
					ev.cam_rot_drag_start_x   = mouse.x
					ev.cam_rot_drag_start_y   = mouse.y
					cp := &app.c_camera_params
					ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
					ev.cam_drag_start_lookat   = {cp.lookat[0], cp.lookat[1], cp.lookat[2]}
					ui_log_drag_start(app, "CamRotation")
					vk_set_cursor(.ResizeAll)
				case pick_camera(ray, cam_lookfrom):
					cp := &app.c_camera_params
					ev.cam_drag_before_params  = app.c_camera_params
					ev.cam_drag_active         = true
					ev.cam_drag_plane_y        = cam_pos_v3.y
					ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
					ev.cam_drag_start_lookat   = {cp.lookat[0], cp.lookat[1], cp.lookat[2]}
					if xz, ok2 := ray_hit_plane_y(ray, ev.cam_drag_plane_y); ok2 {
						ev.cam_drag_start_hit_xz = {xz.x, xz.y}
					}
					ui_log_drag_start(app, "CamBody")
				case:
					if !try_start_entity_drag(app, ev, ray) {
						ev.selection_kind = .None
						ev.selected_idx   = -1
					}
				}
			} else {
				if !try_start_entity_drag(app, ev, ray) {
					if pick_camera(ray, cam_lookfrom) {
						cp := &app.c_camera_params
						ev.cam_drag_before_params  = app.c_camera_params
						ev.selection_kind          = .Camera
						ev.selected_idx            = -1
						ev.cam_drag_active         = true
						ev.cam_drag_plane_y        = cam_pos_v3.y
						ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
						ev.cam_drag_start_lookat   = {cp.lookat[0], cp.lookat[1], cp.lookat[2]}
						if xz, ok2 := ray_hit_plane_y(ray, ev.cam_drag_plane_y); ok2 {
							ev.cam_drag_start_hit_xz = {xz.x, xz.y}
						}
						ui_log_drag_start(app, "CamBody")
					} else {
						ev.selection_kind = .None
						ev.selected_idx   = -1
					}
				}
			}
		}
	}
}

