// edit_view_input.odin — Edit View input handling: phase enum, rects, and per-phase handlers.
// update_edit_view_content delegates to get_edit_view_input_phase + switch and these handlers.

package editor

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

AABB_MAX_DEPTH_CAP :: 20
RMB_DRAG_THRESHOLD :: f32(5.0)

EditViewRects :: struct {
	vp_rect, props_rect: rl.Rectangle,
	btn_add, btn_del, btn_frustum, btn_focal: rl.Rectangle,
	btn_aabb, btn_sel, btn_bvh, btn_d_plus, btn_d_minus: rl.Rectangle,
	btn_fromview, btn_render: rl.Rectangle,
}

edit_view_rects_from_content :: proc(content: rl.Rectangle) -> EditViewRects {
	r: EditViewRects
	r.btn_add      = rl.Rectangle{content.x + 8, content.y + 5, ADD_DROPDOWN_W, 22}
	r.btn_del      = rl.Rectangle{content.x + 106, content.y + 5, 60, 22}
	r.btn_frustum  = rl.Rectangle{content.x + 174, content.y + 5, 56, 22}
	r.btn_focal    = rl.Rectangle{content.x + 234, content.y + 5, 40, 22}
	r.btn_aabb, r.btn_sel, r.btn_bvh, r.btn_d_plus, r.btn_d_minus = edit_view_aabb_toolbar_rects(content)
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
	PropFieldCamera,
	PropFieldSphere,
	ViewportOrbitAndPick,
}

get_edit_view_input_phase :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb_pressed: bool, rects: ^EditViewRects) -> EditViewInputPhase {
	if ev.ctx_menu_open { return .ContextMenu }
	if ev.cam_rot_drag_axis >= 0 { return .CamRotDrag }
	if ev.cam_drag_active { return .CamBodyDrag }
	if ev.cam_prop_drag_idx >= 0 { return .CamPropDrag }
	if ev.prop_drag_idx >= 0 { return .SpherePropDrag }
	if ev.drag_obj_active { return .ViewportObjectDrag }
	if lmb_pressed {
		if rl.CheckCollisionPointRec(mouse, rects.btn_frustum) { return .Toolbar }
		if rl.CheckCollisionPointRec(mouse, rects.btn_focal) { return .Toolbar }
		if rl.CheckCollisionPointRec(mouse, rects.btn_aabb) { return .Toolbar }
		if ev.show_aabbs && rl.CheckCollisionPointRec(mouse, rects.btn_sel) { return .Toolbar }
		if rl.CheckCollisionPointRec(mouse, rects.btn_bvh) { return .Toolbar }
		if ev.show_bvh_hierarchy && rl.CheckCollisionPointRec(mouse, rects.btn_d_plus) { return .Toolbar }
		if ev.show_bvh_hierarchy && rl.CheckCollisionPointRec(mouse, rects.btn_d_minus) { return .Toolbar }
		dd_rect, _, _ := edit_view_add_dropdown_rects(rects.btn_add)
		if ev.add_dropdown_open && rl.CheckCollisionPointRec(mouse, dd_rect) { return .Toolbar }
		if rl.CheckCollisionPointRec(mouse, rects.btn_add) { return .Toolbar }
		if (ev.selection_kind == .Sphere || ev.selection_kind == .Quad) && ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, rects.btn_del) { return .Toolbar }
		if rl.CheckCollisionPointRec(mouse, rects.btn_fromview) { return .Toolbar }
		if app.finished && rl.CheckCollisionPointRec(mouse, rects.btn_render) { return .Toolbar }
	}
	if ev.selection_kind == .Camera && rl.CheckCollisionPointRec(mouse, rects.props_rect) && lmb_pressed {
		fields := cam_orbit_prop_rects(rects.props_rect)
		for i in 0..<7 {
			if rl.CheckCollisionPointRec(mouse, fields[i]) { return .PropFieldCamera }
		}
	}
	if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, rects.props_rect) && lmb_pressed {
		fields := prop_field_rects(rects.props_rect)
		for i in 0..<4 {
			if rl.CheckCollisionPointRec(mouse, fields[i]) { return .PropFieldSphere }
		}
	}
	return .ViewportOrbitAndPick
}

handle_context_menu_input :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2) {
	app.input_consumed = true
	if rl.IsMouseButtonPressed(.LEFT) {
		items := ctx_menu_build_items(app, ev)
		rect  := ctx_menu_screen_rect(app, ev)
		if rl.CheckCollisionPointRec(mouse, rect) {
			local_y := mouse.y - rect.y
			ey: f32 = 0
			for &entry in items {
				ih := entry_height(entry)
				if !entry.separator && !entry.disabled && local_y >= ey && local_y < ey + ih {
					switch entry.label {
					case "Add Sphere":
						AppendDefaultSphere(ev.scene_mgr)
						new_idx := SceneManagerLen(ev.scene_mgr) - 1
						ev.selection_kind = .Sphere
						ev.selected_idx   = new_idx
						if new_sphere, ok := GetSceneSphere(ev.scene_mgr, new_idx); ok {
							edit_history_push(&app.edit_history, AddSphereAction{idx = new_idx, sphere = new_sphere})
							mark_scene_dirty(app)
							app_push_log(app, strings.clone("Add sphere"))
						}
						app.r_render_pending = true
					case "Add Quad":
						AppendDefaultQuad(ev.scene_mgr)
						new_idx := SceneManagerLen(ev.scene_mgr) - 1
						ev.selection_kind = .Quad
						ev.selected_idx   = new_idx
						if new_quad, ok := GetSceneQuad(ev.scene_mgr, new_idx); ok {
							edit_history_push(&app.edit_history, AddQuadAction{idx = new_idx, quad = new_quad})
							mark_scene_dirty(app)
							app_push_log(app, strings.clone("Add quad"))
						}
						app.r_render_pending = true
					case "Delete":
						del_idx := ev.ctx_menu_hit_idx
						if del_sphere, ok := GetSceneSphere(ev.scene_mgr, del_idx); ok {
							edit_history_push(&app.edit_history, DeleteSphereAction{idx = del_idx, sphere = del_sphere})
							mark_scene_dirty(app)
							app_push_log(app, strings.clone("Delete sphere"))
						} else if del_quad, ok := GetSceneQuad(ev.scene_mgr, del_idx); ok {
							edit_history_push(&app.edit_history, DeleteQuadAction{idx = del_idx, quad = del_quad})
							mark_scene_dirty(app)
							app_push_log(app, strings.clone("Delete quad"))
						}
						OrderedRemove(ev.scene_mgr, del_idx)
						ev.selection_kind = .None
						ev.selected_idx   = -1
						app.r_render_pending = true
					case:
						if len(entry.cmd_id) > 0 {
							cmd_execute(app, entry.cmd_id)
						}
					}
					break
				}
				ey += ih
			}
		}
		ev.ctx_menu_open = false
	} else if rl.IsKeyPressed(.ESCAPE) {
		ev.ctx_menu_open = false
	}
}

handle_cam_rot_drag :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb: bool) {
	if !lmb {
		edit_history_push(&app.edit_history, ModifyCameraAction{
			before = ev.cam_drag_before_params,
			after  = app.c_camera_params,
		})
		mark_scene_dirty(app)
		ev.cam_rot_drag_axis = -1
		rl.SetMouseCursor(.DEFAULT)
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
	if !lmb {
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
				app.c_camera_params.lookfrom[0] = ev.cam_drag_start_lookfrom.x + dx
				app.c_camera_params.lookfrom[2] = ev.cam_drag_start_lookfrom.z + dz
				app.c_camera_params.lookat[0]   = ev.cam_drag_start_lookat.x + dx
				app.c_camera_params.lookat[2]   = ev.cam_drag_start_lookat.z + dz
			}
		}
	}
}

handle_cam_prop_drag :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb: bool) {
	DEG2RAD :: f32(math.PI / 180.0)
	if !lmb {
		edit_history_push(&app.edit_history, ModifyCameraAction{
			before = ev.cam_drag_before_params,
			after  = app.c_camera_params,
		})
		mark_scene_dirty(app)
		ev.cam_prop_drag_idx = -1
		rl.SetMouseCursor(.DEFAULT)
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
			app.c_camera_params.lookfrom[0] = sf.x + d
			app.c_camera_params.lookat[0]   = sa.x + d
		case 1:
			d := delta * 0.02
			app.c_camera_params.lookfrom[1] = sf.y + d
			app.c_camera_params.lookat[1]   = sa.y + d
		case 2:
			d := delta * 0.02
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
	if !lmb {
		ev.prop_drag_idx = -1
		rl.SetMouseCursor(.DEFAULT)
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
	if !lmb {
		ev.drag_obj_active = false
		if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
			if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
				edit_history_push(&app.edit_history, ModifySphereAction{
					idx = ev.selected_idx, before = ev.drag_before, after = sphere,
				})
				mark_scene_dirty(app)
				app_push_log(app, strings.clone("Move sphere"))
				app.r_render_pending = true
			}
		} else if ev.selection_kind == .Quad && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
			if quad, ok := GetSceneQuad(ev.scene_mgr, ev.selected_idx); ok {
				edit_history_push(&app.edit_history, ModifyQuadAction{
					idx = ev.selected_idx, before = ev.drag_before_quad, after = quad,
				})
				mark_scene_dirty(app)
				app_push_log(app, strings.clone("Move quad"))
				app.r_render_pending = true
			}
		}
	} else if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, rects.vp_rect, false); ok {
			if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
				if sphere, ok3 := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok3 {
					sphere.center[0] = xz.x - ev.drag_offset_xz[0]
					sphere.center[2] = xz.y - ev.drag_offset_xz[1]
					SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
				}
			}
		}
	} else if ev.selection_kind == .Quad && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, rects.vp_rect, false); ok {
			if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
				if quad, ok3 := GetSceneQuad(ev.scene_mgr, ev.selected_idx); ok3 {
					quad.Q[0] = xz.x - ev.drag_offset_xz[0]
					quad.Q[2] = xz.y - ev.drag_offset_xz[1]
					SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
				}
			}
		}
	}
}

handle_toolbar_input :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, rects: ^EditViewRects) {
	// Dispatch by which button was hit (switch on first match)
	switch {
	case rl.CheckCollisionPointRec(mouse, rects.btn_frustum):
		ev.show_frustum_gizmo = !ev.show_frustum_gizmo
	case rl.CheckCollisionPointRec(mouse, rects.btn_focal):
		ev.show_focal_indicator = !ev.show_focal_indicator
	case rl.CheckCollisionPointRec(mouse, rects.btn_aabb):
		ev.show_aabbs = !ev.show_aabbs
	case ev.show_aabbs && rl.CheckCollisionPointRec(mouse, rects.btn_sel):
		ev.aabb_selected_only = !ev.aabb_selected_only
	case rl.CheckCollisionPointRec(mouse, rects.btn_bvh):
		ev.show_bvh_hierarchy = !ev.show_bvh_hierarchy
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
			if rl.IsMouseButtonPressed(.LEFT) {
				switch {
				case rl.CheckCollisionPointRec(mouse, sphere_item):
					ev.add_dropdown_open = false
					AppendDefaultSphere(ev.scene_mgr)
					new_idx := SceneManagerLen(ev.scene_mgr) - 1
					ev.selection_kind = .Sphere
					ev.selected_idx   = new_idx
					if new_sphere, ok := GetSceneSphere(ev.scene_mgr, new_idx); ok {
						edit_history_push(&app.edit_history, AddSphereAction{idx = new_idx, sphere = new_sphere})
						mark_scene_dirty(app)
						app_push_log(app, strings.clone("Add sphere"))
					}
					app.r_render_pending = true
				case rl.CheckCollisionPointRec(mouse, quad_item):
					ev.add_dropdown_open = false
					AppendDefaultQuad(ev.scene_mgr)
					new_idx := SceneManagerLen(ev.scene_mgr) - 1
					ev.selection_kind = .Quad
					ev.selected_idx   = new_idx
					if new_quad, ok := GetSceneQuad(ev.scene_mgr, new_idx); ok {
						edit_history_push(&app.edit_history, AddQuadAction{idx = new_idx, quad = new_quad})
						mark_scene_dirty(app)
						app_push_log(app, strings.clone("Add quad"))
					}
					app.r_render_pending = true
				case !in_dropdown && !in_btn_add:
					ev.add_dropdown_open = false
				}
			}
		} else if rl.CheckCollisionPointRec(mouse, rects.btn_add) {
			ev.add_dropdown_open = true
		} else if (ev.selection_kind == .Sphere || ev.selection_kind == .Quad) && ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, rects.btn_del) {
			del_idx := ev.selected_idx
			if ev.selection_kind == .Sphere {
				if del_sphere, ok := GetSceneSphere(ev.scene_mgr, del_idx); ok {
					edit_history_push(&app.edit_history, DeleteSphereAction{idx = del_idx, sphere = del_sphere})
					mark_scene_dirty(app)
					app_push_log(app, strings.clone("Delete sphere"))
				}
			} else if ev.selection_kind == .Quad {
				if del_quad, ok := GetSceneQuad(ev.scene_mgr, del_idx); ok {
					edit_history_push(&app.edit_history, DeleteQuadAction{idx = del_idx, quad = del_quad})
					mark_scene_dirty(app)
					app_push_log(app, strings.clone("Delete quad"))
				}
			}
			OrderedRemove(ev.scene_mgr, del_idx)
			ev.selection_kind = .None
			ev.selected_idx   = -1
			app.r_render_pending = true
		} else if rl.CheckCollisionPointRec(mouse, rects.btn_fromview) {
			before := app.c_camera_params
			lookfrom, lookat := get_orbit_camera_pose(ev)
			app.c_camera_params.lookfrom = lookfrom
			app.c_camera_params.lookat   = lookat
			edit_history_push(&app.edit_history, ModifyCameraAction{before = before, after = app.c_camera_params})
			mark_scene_dirty(app)
			app.r_render_pending = true
		} else if app.finished && rl.CheckCollisionPointRec(mouse, rects.btn_render) {
			ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
			delete(app.r_world)
			app.r_world = app_build_world_from_scene(app, ev.export_scratch[:])
			AppendQuadsToWorld(ev.scene_mgr, &app.r_world)
			width, height, res_ok := calculate_render_dimensions(app)
			samples, samp_ok := strconv.parse_int(app.r_samples_input)
			if !res_ok {
				h, h_ok := strconv.parse_int(strings.trim_space(app.r_height_input))
				if !h_ok || h <= 0 {
					app_push_log(app, strings.clone("Invalid height. Must be a positive integer."))
				} else {
					if h < MIN_RENDER_HEIGHT {
						app_push_log(app, fmt.aprintf("Warning: Height %d below minimum (%d)", h, MIN_RENDER_HEIGHT))
					} else if h > MAX_RENDER_HEIGHT {
						app_push_log(app, fmt.aprintf("Warning: Height %d exceeds maximum (%d)", h, MAX_RENDER_HEIGHT))
					}
					if width < MIN_RENDER_WIDTH {
						app_push_log(app, fmt.aprintf("Warning: Width %d below minimum (%d)", width, MIN_RENDER_WIDTH))
					} else if width > MAX_RENDER_WIDTH {
						app_push_log(app, fmt.aprintf("Warning: Width %d exceeds maximum (%d)", width, MAX_RENDER_WIDTH))
					}
				}
			} else if !samp_ok || samples <= 0 {
				app_push_log(app, strings.clone("Invalid samples count. Must be a positive integer."))
			} else {
				restart_render_with_settings(app, width, height, samples)
			}
		}
	}
	}
	if g_app != nil { g_app.input_consumed = true }
}

handle_prop_field_camera_start :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb_pressed: bool, rects: ^EditViewRects) {
	fields := cam_orbit_prop_rects(rects.props_rect)
	any_hovered := false
	for i in 0..<7 {
		if rl.CheckCollisionPointRec(mouse, fields[i]) {
			any_hovered = true
			if lmb_pressed {
				cp := &app.c_camera_params
				ev.cam_drag_before_params   = app.c_camera_params
				ev.cam_prop_drag_idx       = i
				ev.cam_prop_drag_start_x   = mouse.x
				ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
				ev.cam_drag_start_lookat   = {cp.lookat[0], cp.lookat[1], cp.lookat[2]}
				if i == 6 {
					ev.cam_prop_drag_start_val = roll_from_vup(cp.lookfrom, cp.lookat, cp.vup)
				}
				rl.SetMouseCursor(.RESIZE_EW)
				return
			}
		}
	}
	if any_hovered { rl.SetMouseCursor(.RESIZE_EW) } else { rl.SetMouseCursor(.DEFAULT) }
}

handle_prop_field_sphere_start :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb_pressed: bool, rects: ^EditViewRects) {
	fields := prop_field_rects(rects.props_rect)
	if tmp, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
		vals := [4]f32{tmp.center[0], tmp.center[1], tmp.center[2], tmp.radius}
		any_hovered := false
		for i in 0..<4 {
			if rl.CheckCollisionPointRec(mouse, fields[i]) {
				any_hovered = true
				if lmb_pressed {
					ev.prop_drag_idx       = i
					ev.prop_drag_start_x   = mouse.x
					ev.prop_drag_start_val = vals[i]
					rl.SetMouseCursor(.RESIZE_EW)
					app.r_render_pending = true
					return
				}
			}
		}
		if any_hovered { rl.SetMouseCursor(.RESIZE_EW) } else { rl.SetMouseCursor(.DEFAULT) }
	} else {
		rl.SetMouseCursor(.DEFAULT)
	}
}

handle_viewport_orbit_and_pick :: proc(app: ^App, ev: ^EditViewState, mouse: rl.Vector2, lmb_pressed: bool, rects: ^EditViewRects) {
	mouse_in_vp := rl.CheckCollisionPointRec(mouse, rects.vp_rect)
	rmb_pressed := rl.IsMouseButtonPressed(.RIGHT)
	rmb_down    := rl.IsMouseButtonDown(.RIGHT)
	rmb_release := rl.IsMouseButtonReleased(.RIGHT)

	if rmb_pressed && mouse_in_vp {
		ev.rmb_press_pos = mouse
		ev.rmb_drag_dist = 0
		ev.rmb_held      = false
		ev.last_mouse    = mouse
	}
	if rmb_down {
		delta := rl.Vector2{mouse.x - ev.rmb_press_pos.x, mouse.y - ev.rmb_press_pos.y}
		dist  := math.sqrt(delta.x*delta.x + delta.y*delta.y)
		if dist > ev.rmb_drag_dist { ev.rmb_drag_dist = dist }
		if ev.rmb_drag_dist >= RMB_DRAG_THRESHOLD { ev.rmb_held = true }
		if ev.rmb_held {
			orb_delta := rl.Vector2{mouse.x - ev.last_mouse.x, mouse.y - ev.last_mouse.y}
			ev.camera_yaw   += orb_delta.x * 0.005
			ev.camera_pitch += -orb_delta.y * 0.005
		}
		ev.last_mouse = mouse
	}
	if rmb_release && mouse_in_vp && ev.rmb_drag_dist < RMB_DRAG_THRESHOLD {
		update_orbit_camera(ev)
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, rects.vp_rect, false); ok {
			pick_kind, pick_idx, _ := PickClosestObject(ev.scene_mgr, ray)
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
		ev.orbit_distance -= rl.GetMouseWheelMove() * 0.8
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
					rl.SetMouseCursor(.RESIZE_ALL)
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
				case:
					pick_kind, pick_idx, _ := PickClosestObject(ev.scene_mgr, ray)
					switch {
					case pick_idx >= 0 && pick_kind == .Sphere:
						ev.selection_kind  = .Sphere
						ev.selected_idx    = pick_idx
						ev.drag_obj_active = true
						if sphere, ok3 := GetSceneSphere(ev.scene_mgr, pick_idx); ok3 {
							ev.drag_before  = sphere
							ev.drag_plane_y = sphere.center[1]
							if xz, ok4 := ray_hit_plane_y(ray, ev.drag_plane_y); ok4 {
								ev.drag_offset_xz = {xz.x - sphere.center[0], xz.y - sphere.center[2]}
							}
						}
					case pick_idx >= 0 && pick_kind == .Quad:
						ev.selection_kind  = .Quad
						ev.selected_idx    = pick_idx
						ev.drag_obj_active = true
						if quad, ok3 := GetSceneQuad(ev.scene_mgr, pick_idx); ok3 {
							ev.drag_before_quad = quad
							ev.drag_plane_y    = quad.Q[1]
							if xz, ok4 := ray_hit_plane_y(ray, ev.drag_plane_y); ok4 {
								ev.drag_offset_xz = {xz.x - quad.Q[0], xz.y - quad.Q[2]}
							} else { ev.drag_offset_xz = {0, 0} }
						}
					case:
						ev.selection_kind = .None
						ev.selected_idx   = -1
					}
				}
			} else {
				pick_kind, pick_idx, _ := PickClosestObject(ev.scene_mgr, ray)
				switch {
				case pick_idx >= 0 && pick_kind == .Sphere:
					ev.selection_kind  = .Sphere
					ev.selected_idx    = pick_idx
					ev.drag_obj_active = true
					if sphere, ok3 := GetSceneSphere(ev.scene_mgr, pick_idx); ok3 {
						ev.drag_before  = sphere
						ev.drag_plane_y = sphere.center[1]
						if xz, ok4 := ray_hit_plane_y(ray, ev.drag_plane_y); ok4 {
							ev.drag_offset_xz = {xz.x - sphere.center[0], xz.y - sphere.center[2]}
						}
					}
				case pick_idx >= 0 && pick_kind == .Quad:
					ev.selection_kind  = .Quad
					ev.selected_idx    = pick_idx
					ev.drag_obj_active = true
					if quad, ok3 := GetSceneQuad(ev.scene_mgr, pick_idx); ok3 {
						ev.drag_before_quad = quad
						ev.drag_plane_y    = quad.Q[1]
						if xz, ok4 := ray_hit_plane_y(ray, ev.drag_plane_y); ok4 {
							ev.drag_offset_xz = {xz.x - quad.Q[0], xz.y - quad.Q[2]}
						} else { ev.drag_offset_xz = {0, 0} }
					}
				case pick_camera(ray, cam_lookfrom):
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
				case:
					ev.selection_kind = .None
					ev.selected_idx   = -1
				}
			}
		}
	}
}
