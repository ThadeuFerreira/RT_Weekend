package editor

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

draw_viewport_3d :: proc(app: ^App, vp_rect: rl.Rectangle) {
	ev := &app.e_edit_view
	sm := ev.scene_mgr
	if sm == nil { return }
	new_w := i32(vp_rect.width)
	new_h := i32(vp_rect.height)

	if new_w != ev.tex_w || new_h != ev.tex_h {
		if ev.tex_w > 0 { rl.UnloadRenderTexture(ev.viewport_tex) }
		if new_w > 0 && new_h > 0 {
			ev.viewport_tex = rl.LoadRenderTexture(new_w, new_h)
		}
		ev.tex_w = new_w
		ev.tex_h = new_h
	}

	if ev.tex_w <= 0 || ev.tex_h <= 0 { return }

	// Invalidate viewport sphere cache when scene changed (load, add/remove sphere, etc.)
	ensure_viewport_sphere_cache_filled(app, ev)

	rl.BeginTextureMode(ev.viewport_tex)
	rl.ClearBackground(rl.Color{20, 25, 35, 255})
	rl.BeginMode3D(ev.cam3d)
	rl.DrawGrid(20, 1.0)
	draw_viewport_scene_objects(app, ev, ev.selection_kind, ev.selected_idx)
	draw_viewport_camera_gizmos(app, ev)

	// Draw a move indicator on the selected sphere during drag
	if ev.drag_obj_active && ev.selection_kind == .Sphere && ev.selected_idx >= 0 {
		if sphere, ok := GetSceneSphere(sm, ev.selected_idx); ok {
			c := rl.Vector3{sphere.center[0], sphere.center[1], sphere.center[2]}
			rl.DrawCircle3D(c, sphere.radius + 0.08, rl.Vector3{1, 0, 0}, 90, rl.Color{255, 220, 0, 200})
		}
	}
	// Draw a move indicator on the selected quad during drag
	if ev.drag_obj_active && ev.selection_kind == .Quad && ev.selected_idx >= 0 {
		if quad, ok := GetSceneQuad(sm, ev.selected_idx); ok {
			draw_quad_3d(quad, rl.Color{255, 220, 0, 220}) // overlay tint
		}
	}

	// --- AABB Visualization ---
	if ev.show_aabbs {
		for i in 0..<len(sm.objects) {
			if ev.aabb_selected_only && !((ev.selection_kind == .Sphere || ev.selection_kind == .Quad) && ev.selected_idx == i) {
				continue
			}
			color := rl.Color{100, 220, 100, 150}
			if (ev.selection_kind == .Sphere || ev.selection_kind == .Quad) && ev.selected_idx == i {
				color = rl.Color{255, 220, 0, 200}
			}
			#partial switch o in sm.objects[i] {
			case core.SceneSphere:
				draw_aabb_wireframe(compute_scene_sphere_aabb(o), color)
			case rt.Quad:
				draw_aabb_wireframe(rt.quad_bounding_box(o), color)
			}
		}
	}

	// --- BVH Hierarchy Visualization (cached; rebuild only when scene changes) ---
	if ev.show_bvh_hierarchy && SceneManagerLen(sm) > 0 {
		if ev.viz_bvh_dirty {
			if ev.viz_bvh_root != nil {
				rt.free_bvh(ev.viz_bvh_root)
				ev.viz_bvh_root = nil
			}
			ExportToSceneSpheres(sm, &ev.export_scratch)
			objects := app_build_world_from_scene(app, ev.export_scratch[:])
			AppendQuadsToWorld(sm, &objects)
			defer delete(objects)
			ev.viz_bvh_root = rt.build_bvh(objects[:])
			ev.viz_bvh_dirty = false
		}
		if ev.viz_bvh_root != nil {
			draw_bvh_node(ev.viz_bvh_root, 0, ev.aabb_max_depth)
		}
	}

	rl.EndMode3D()
	rl.EndTextureMode()

	src := rl.Rectangle{0, 0, f32(ev.tex_w), -f32(ev.tex_h)}
	rl.DrawTexturePro(ev.viewport_tex.texture, src, vp_rect, rl.Vector2{0, 0}, 0.0, rl.WHITE)
}

// ── Panel draw ─────────────────────────────────────────────────────────────

draw_edit_view_content :: proc(app: ^App, content: rl.Rectangle) {
	ev    := &app.e_edit_view
	mouse := rl.GetMousePosition()

	// Toolbar
	toolbar_rect := rl.Rectangle{content.x, content.y, content.width, EDIT_TOOLBAR_H}
	rl.DrawRectangleRec(toolbar_rect, rl.Color{40, 42, 58, 255})
	rl.DrawRectangleLinesEx(toolbar_rect, 1, BORDER_COLOR)

	// Add Object (trigger + dropdown)
	btn_add := Button{
		rect    = rl.Rectangle{content.x + 8, content.y + 5, ADD_DROPDOWN_W, 22},
		label   = "Add Object",
		style   = DEFAULT_BUTTON_STYLE,
		enabled = true,
	}
	_ = draw_button(app, btn_add, mouse)
	draw_ui_text(app, "\u25BC", i32(btn_add.rect.x) + 72, i32(btn_add.rect.y) + 4, 10, rl.RAYWHITE)

	if ev.add_dropdown_open {
		dd_rect, sphere_item, quad_item := edit_view_add_dropdown_rects(btn_add.rect)
		draw_dropdown_panel(dd_rect)
		_ = draw_dropdown_item(app, sphere_item, "Sphere", mouse)
		_ = draw_dropdown_item(app, quad_item, "Quad", mouse)
	}

	// Delete (only when sphere or quad selected)
	if (ev.selection_kind == .Sphere || ev.selection_kind == .Quad) && ev.selected_idx >= 0 {
		btn_del := Button{
			rect    = rl.Rectangle{content.x + 106, content.y + 5, 60, 22},
			label   = "Delete",
			style   = BUTTON_STYLE_DANGER,
			enabled = true,
		}
		_ = draw_button(app, btn_del, mouse)
	}

	// Frustum / Focal toggles
	draw_toggle(app, Toggle{
		rect  = rl.Rectangle{content.x + 174, content.y + 5, 56, 22},
		label = "Frustum",
		value = ev.show_frustum_gizmo,
		style = DEFAULT_TOGGLE_STYLE,
	}, mouse)
	draw_toggle(app, Toggle{
		rect  = rl.Rectangle{content.x + 234, content.y + 5, 40, 22},
		label = "Focal",
		value = ev.show_focal_indicator,
		style = TOGGLE_STYLE_ON_RED,
	}, mouse)

	// AABB / BVH toggles and depth D+ / D-
	btn_aabb, btn_sel, btn_bvh, btn_d_plus, btn_d_minus := edit_view_aabb_toolbar_rects(content)
	draw_toggle(app, Toggle{rect = btn_aabb, label = "AABB", value = ev.show_aabbs, style = DEFAULT_TOGGLE_STYLE}, mouse)
	if ev.show_aabbs {
		draw_toggle(app, Toggle{rect = btn_sel, label = "Sel", value = ev.aabb_selected_only, style = DEFAULT_TOGGLE_STYLE}, mouse)
	}
	draw_toggle(app, Toggle{rect = btn_bvh, label = "BVH", value = ev.show_bvh_hierarchy, style = DEFAULT_TOGGLE_STYLE}, mouse)
	if ev.show_bvh_hierarchy {
		_ = draw_button(app, Button{rect = btn_d_plus, label = "D+", style = BUTTON_STYLE_NEUTRAL, enabled = true}, mouse)
		_ = draw_button(app, Button{rect = btn_d_minus, label = "D-", style = BUTTON_STYLE_NEUTRAL, enabled = true}, mouse)
		depth_label := ev.aabb_max_depth < 0 ? "\u221E" : fmt.ctprintf("%d", ev.aabb_max_depth)
		draw_ui_text(app, depth_label, i32(btn_d_minus.x) + 22 + 4, i32(btn_d_minus.y) + 5, 11, rl.Color{180, 185, 200, 220})
	}

	// Background color (swatch opens R G B popover)
	btn_bg, swatch_bg, popover_bg := edit_view_background_rects(content)
	bg := app.c_camera_params.background
	draw_ui_text(app, "Background", i32(btn_bg.x), i32(btn_bg.y) + 5, 10, CONTENT_TEXT_COLOR)
	swatch_c := rl.Color{
		u8(clamp(bg[0], 0, 1) * 255),
		u8(clamp(bg[1], 0, 1) * 255),
		u8(clamp(bg[2], 0, 1) * 255),
		255,
	}
	rl.DrawRectangleRec(swatch_bg, swatch_c)
	rl.DrawRectangleLinesEx(swatch_bg, 1, BORDER_COLOR)
	if ev.bg_picker_open {
		draw_dropdown_panel(popover_bg)
		op_section_label(app, "Background", popover_bg.x + 8, popover_bg.y + 6)
		x0 := popover_bg.x + 8 + OP_LW + OP_GAP
		cy := popover_bg.y + 6 + 18
		box_rgb := [3]rl.Rectangle{
			{x0,             cy, OP_FW, OP_FH},
			{x0 + OP_COL,   cy, OP_FW, OP_FH},
			{x0 + 2*OP_COL, cy, OP_FW, OP_FH},
		}
		op_drag_field(app, "R", bg[0], box_rgb[0], ev.bg_drag_idx == 0, mouse)
		op_drag_field(app, "G", bg[1], box_rgb[1], ev.bg_drag_idx == 1, mouse)
		op_drag_field(app, "B", bg[2], box_rgb[2], ev.bg_drag_idx == 2, mouse)
	}

	// From View
	btn_fromview := Button{
		rect    = rl.Rectangle{content.x + content.width - 178, content.y + 5, 82, 22},
		label   = "From View",
		style   = DEFAULT_BUTTON_STYLE,
		enabled = true,
	}
	_ = draw_button(app, btn_fromview, mouse)

	// Render (state-dependent label and color)
	btn_render_rect := rl.Rectangle{content.x + content.width - 90, content.y + 5, 82, 22}
	render_busy  := !app.finished
	render_ready := app.finished && app.r_render_pending
	render_style := BUTTON_STYLE_SUCCESS
	if render_busy {
		render_style = BUTTON_STYLE_RENDER_BUSY
	} else if render_ready {
		render_style = BUTTON_STYLE_RENDER_READY
	}
	btn_render := Button{
		rect    = btn_render_rect,
		label   = render_busy ? "Rendering…" : (render_ready ? "Render*" : "Render"),
		style   = render_style,
		enabled = !render_busy,
	}
	_ = draw_button(app, btn_render, mouse)

	// 3D viewport
	vp_rect := rl.Rectangle{
		content.x,
		content.y + EDIT_TOOLBAR_H,
		content.width,
		content.height - EDIT_TOOLBAR_H - EDIT_PROPS_H,
	}
	draw_viewport_3d(app, vp_rect)

	// Properties strip
	props_rect := rl.Rectangle{
		content.x,
		content.y + content.height - EDIT_PROPS_H,
		content.width,
		EDIT_PROPS_H,
	}
	draw_edit_properties(app, props_rect, mouse, ev.export_scratch[:])

	// Context menu drawn last so it renders on top of everything
	if ev.ctx_menu_open {
		draw_edit_view_context_menu(app, ev)
	}
}

// pick_rotation_ring returns which of the 3 world-axis rings is closest to the mouse,
// or -1 if none is within the pixel threshold.
//   0 = X ring (red,   YZ plane)
//   1 = Y ring (green, XZ plane)
//   2 = Z ring (blue,  XY plane)
// Uses sampled world points projected to screen space so the hit zone scales with zoom
// and handles all viewing angles (rings that are edge-on become narrow, as expected).
pick_rotation_ring :: proc(mouse, vp_offset: rl.Vector2, cam_pos: rl.Vector3, cam3d: rl.Camera3D) -> int {
	SAMPLE_N   :: 32
	HIT_THRESH :: f32(10) // pixels

	best_axis := -1
	best_dist := HIT_THRESH

	for axis in 0..<3 {
		for i in 0..<SAMPLE_N {
			t  := f32(i) * (2.0 * math.PI / SAMPLE_N)
			ct := math.cos(t) * CAM_RING_R
			st := math.sin(t) * CAM_RING_R
			p: rl.Vector3
			switch axis {
			case 0: p = cam_pos + {0, ct, st}  // YZ plane — X axis ring
			case 1: p = cam_pos + {ct, 0, st}  // XZ plane — Y axis ring
			case 2: p = cam_pos + {ct, st, 0}  // XY plane — Z axis ring
			}
			proj := rl.GetWorldToScreen(p, cam3d)
			proj.x += vp_offset.x
			proj.y += vp_offset.y
			dmx := mouse.x - proj.x
			dmy := mouse.y - proj.y
			d := math.sqrt(dmx*dmx + dmy*dmy)
			if d < best_dist {
				best_dist = d
				best_axis = axis
			}
		}
	}
	return best_axis
}

// ── Panel update ───────────────────────────────────────────────────────────

update_edit_view_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	ev     := &app.e_edit_view
	content := rect

	defer update_orbit_camera(ev)

	rects := edit_view_rects_from_content(content)
	if lmb_pressed && ev.bg_picker_open && !rl.CheckCollisionPointRec(mouse, rects.popover_bg) && !rl.CheckCollisionPointRec(mouse, rects.btn_bg) {
		ev.bg_picker_open = false
	}
	phase := get_edit_view_input_phase(app, ev, mouse, lmb_pressed, &rects)

	switch phase {
	case .ContextMenu:
		handle_context_menu_input(app, ev, mouse)
		return
	case .CamRotDrag:
		handle_cam_rot_drag(app, ev, mouse, lmb)
		return
	case .CamBodyDrag:
		handle_cam_body_drag(app, ev, mouse, lmb, &rects)
		return
	case .CamPropDrag:
		handle_cam_prop_drag(app, ev, mouse, lmb)
		return
	case .SpherePropDrag:
		handle_sphere_prop_drag(app, ev, mouse, lmb)
		return
	case .ViewportObjectDrag:
		handle_viewport_object_drag(app, ev, mouse, lmb, &rects)
		return
	case .Toolbar:
		handle_toolbar_input(app, ev, mouse, &rects)
		return
	case .PropFieldCamera:
		handle_prop_field_camera_start(app, ev, mouse, lmb_pressed, &rects)
		return
	case .PropFieldSphere:
		handle_prop_field_sphere_start(app, ev, mouse, lmb_pressed, &rects)
		return
	case .ViewportOrbitAndPick:
		handle_viewport_orbit_and_pick(app, ev, mouse, lmb_pressed, &rects)
		// Cursor feedback when hovering prop fields (no drag start)
		handle_prop_field_camera_start(app, ev, mouse, false, &rects)
		handle_prop_field_sphere_start(app, ev, mouse, false, &rects)
	}

	update_sphere_nudge(app, ev)
}
