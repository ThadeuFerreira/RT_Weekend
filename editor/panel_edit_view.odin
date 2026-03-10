package editor

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

// calculate_render_dimensions computes width and height from app settings.
// Returns false if dimensions are out of bounds (16k max, 720p min).
calculate_render_dimensions :: proc(app: ^App) -> (width, height: int, ok: bool) {
    h, h_ok := strconv.parse_int(strings.trim_space(app.r_height_input))
    if !h_ok || h <= 0 {
        return 0, 0, false
    }
    aspect := get_render_aspect(app)
    w := int(f32(h) * aspect)

    // Check bounds (16k max, 720p min)
    if h < MIN_RENDER_HEIGHT || h > MAX_RENDER_HEIGHT {
        return w, h, false
    }
    if w < MIN_RENDER_WIDTH || w > MAX_RENDER_WIDTH {
        return w, h, false
    }

    return w, h, true
}

// flip_image_vertical_rgba flips pixel rows in place. buf is width*height*4 bytes (RGBA).
flip_image_vertical_rgba :: proc(buf: []u8, width, height: int) {
	if width <= 0 || height <= 1 do return
	row_bytes := width * 4
	for y in 0 ..< height / 2 {
		other := height - 1 - y
		for x in 0 ..< row_bytes {
			buf[y * row_bytes + x], buf[other * row_bytes + x] = buf[other * row_bytes + x], buf[y * row_bytes + x]
		}
	}
}

// free_viewport_sphere_cache_entry unloads model and texture for one cache slot; call before overwriting or clearing.
free_viewport_sphere_cache_entry :: proc(entry: ^ViewportSphereCacheEntry) {
	if entry.tex.id != 0 {
		rl.UnloadModel(entry.model)
		rl.UnloadTexture(entry.tex)
		delete(entry.tex_sig)
		entry.tex = {}
	}
}

// viewport_texture_from_albedo builds a Raylib texture from core.Texture for use in the 3D viewport.
// Caller must call rl.UnloadTexture on the returned texture when done.
// For ImageTexture we flip the image vertically in our buffer (no raylib call) so sphere UV matches
// the path tracer; rl.ImageFlipVertical must not be used because img.data points to our buffer.
viewport_texture_from_albedo :: proc(app: ^App, albedo: core.Texture) -> (tex: rl.Texture2D, ok: bool) {
	img, buf_to_free, ok_build := texture_view_build_image(app, albedo)
	if !ok_build do return {}, false
	if _, is_image := albedo.(core.ImageTexture); is_image && len(buf_to_free) > 0 {
		flip_image_vertical_rgba(buf_to_free, int(img.width), int(img.height))
	}
	tex = rl.LoadTextureFromImage(img)
	#partial switch _ in albedo {
	case core.ConstantTexture, core.CheckerTexture:
		rl.UnloadImage(img)
	case core.ImageTexture:
		delete(buf_to_free)
	}
	return tex, true
}

// compute_viewport_ray casts a perspective ray through the given mouse position.
// When require_inside=true (default) returns false if mouse is outside vp_rect.
// When require_inside=false the UV is clamped to viewport edges — useful during
// active drags where the mouse may wander outside the panel.
// NOTE: viewport / picking helpers were moved into the editor package so they
// can be shared by object implementations without creating package cycles.

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
	if ev.viewport_sphere_cache_dirty {
		for i in 0..<len(ev.viewport_sphere_cache) {
			free_viewport_sphere_cache_entry(&ev.viewport_sphere_cache[i])
		}
		clear(&ev.viewport_sphere_cache)
		ev.viewport_sphere_cache_dirty = false
	}

	// Ensure cache has one slot per object in sm; shrink and free evicted entries if count dropped.
	n_objects := len(sm.objects)
	for len(ev.viewport_sphere_cache) > n_objects {
		free_viewport_sphere_cache_entry(&ev.viewport_sphere_cache[len(ev.viewport_sphere_cache) - 1])
		pop(&ev.viewport_sphere_cache)
	}
	for len(ev.viewport_sphere_cache) < n_objects {
		append(&ev.viewport_sphere_cache, ViewportSphereCacheEntry{})
	}

	// Pre-pass: build mesh+model+texture for any cache miss *before* we enter render target / 3D mode.
	// Creating and uploading mesh/model inside BeginTextureMode/BeginMode3D can prevent the texture from showing.
	N_RINGS  :: 64
	N_SLICES :: 64
	for i in 0..<n_objects {
		s, ok := sm.objects[i].(core.SceneSphere)
		if !ok { continue }
		entry   := &ev.viewport_sphere_cache[i]
		tex_sig := texture_view_sig(app, s.albedo)
		cache_hit := entry.tex.id != 0 && entry.radius == s.radius && entry.tex_sig == tex_sig
		if cache_hit { continue }
		if tex, tex_ok := viewport_texture_from_albedo(app, s.albedo); tex_ok {
			free_viewport_sphere_cache_entry(entry)
			sphere_mesh := rl.GenMeshSphere(s.radius, N_RINGS, N_SLICES)
			uvs := transmute([]rl.Vector2)(sphere_mesh.texcoords[:sphere_mesh.vertexCount])
			for &uv in uvs {
				uv.x, uv.y = uv.y, uv.x
				uv.y = 1.0 - uv.y
			}
			rl.UpdateMeshBuffer(sphere_mesh, 1, raw_data(uvs), i32(len(uvs) * size_of(rl.Vector2)), 0)
			model := rl.LoadModelFromMesh(sphere_mesh)
			rl.SetMaterialTexture(&model.materials[0], rl.MaterialMapIndex.ALBEDO, tex)
			entry.model   = model
			entry.tex     = tex
			entry.radius  = s.radius
			entry.tex_sig = strings.clone(tex_sig)
		}
	}

	rl.BeginTextureMode(ev.viewport_tex)
	rl.ClearBackground(rl.Color{20, 25, 35, 255})
	rl.BeginMode3D(ev.cam3d)
	rl.DrawGrid(20, 1.0)

	for i in 0..<n_objects {
		selected := (ev.selection_kind == .Sphere || ev.selection_kind == .Quad) && ev.selected_idx == i
		#partial switch o in sm.objects[i] {
		case core.SceneSphere:
			s := o
			center := s.center
			wire_col := rl.Color{30, 30, 30, 180}
			if selected { wire_col = rl.Color{255, 220, 0, 200} }

			entry := &ev.viewport_sphere_cache[i]
			if entry.tex.id != 0 {
				// Cached model (any texture type that produced a valid GPU tex)
				tint := rl.WHITE
				if selected { tint = rl.YELLOW }
				rl.DrawModelEx(entry.model, center, {0, 1, 0}, -90.0, {1, 1, 1}, tint)
				rl.DrawSphereWires(center, s.radius + 0.01, 8, 8, wire_col)
			} else {
				// Fallback: solid colour (shared with preview panel)
				draw_sphere_solid(s.center, s.radius, sphere_solid_color_from_albedo(s.albedo), selected)
			}
		case rt.Quad:
			draw_quad_with_material_color(o, selected)
		}
	}

	// Render camera gizmo (body) and optional frustum / focal indicator
	cp := &app.c_camera_params
	cam_pos := rl.Vector3{cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
	cam_at  := rl.Vector3{cp.lookat[0], cp.lookat[1], cp.lookat[2]}
	vup     := rl.Vector3{cp.vup[0], cp.vup[1], cp.vup[2]}
	draw_camera_gizmo(cam_pos, cam_at, vup, ev.selection_kind == .Camera)

	if ev.selection_kind == .Camera {
		draw_camera_rotation_rings(cam_pos, ev.cam_rot_drag_axis)
	}

	aspect := get_render_aspect(app)
	if ev.show_frustum_gizmo {
		ul, ur, lr, ll := get_camera_viewport_corners(cp, f32(aspect))
		draw_frustum_wireframe(
			cam_pos,
			vec3_from_core(ul), vec3_from_core(ur), vec3_from_core(lr), vec3_from_core(ll),
			rl.Color{0, 200, 220, 180},
		)
	}
	if ev.show_focal_indicator {
		fwd := rl.Vector3Normalize(cam_at - cam_pos)
		focus_point := cam_pos + fwd * cp.focus_dist
		draw_focal_distance_indicator(cam_pos, focus_point, rl.RED, rl.RED)
	}

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

	btn_add   := rl.Rectangle{content.x + 8, content.y + 5, ADD_DROPDOWN_W, 22}
	add_hover := rl.CheckCollisionPointRec(mouse, btn_add)
	rl.DrawRectangleRec(btn_add, add_hover ? rl.Color{80, 130, 200, 255} : rl.Color{55, 85, 140, 255})
	draw_ui_text(app, "Add Object", i32(btn_add.x) + 6, i32(btn_add.y) + 4, 12, rl.RAYWHITE)
	draw_ui_text(app, "\u25BC", i32(btn_add.x) + 72, i32(btn_add.y) + 4, 10, rl.RAYWHITE) // dropdown arrow

	// Add Object dropdown (Sphere / Quad)
	if ev.add_dropdown_open {
		dd_rect, sphere_item, quad_item := edit_view_add_dropdown_rects(btn_add)
		rl.DrawRectangleRec(dd_rect, rl.Color{50, 52, 70, 255})
		rl.DrawRectangleLinesEx(dd_rect, 1, BORDER_COLOR)
		sphere_hov  := rl.CheckCollisionPointRec(mouse, sphere_item)
		quad_hov    := rl.CheckCollisionPointRec(mouse, quad_item)
		if sphere_hov { rl.DrawRectangleRec(sphere_item, rl.Color{60, 65, 95, 255}) }
		if quad_hov   { rl.DrawRectangleRec(quad_item,   rl.Color{60, 65, 95, 255}) }
		draw_ui_text(app, "Sphere", i32(sphere_item.x) + 8, i32(sphere_item.y) + 4, 12, rl.RAYWHITE)
		draw_ui_text(app, "Quad",   i32(quad_item.x) + 8,   i32(quad_item.y) + 4,   12, rl.RAYWHITE)
	}

	// Delete for sphere or quad selection (camera is non-deletable)
	if (ev.selection_kind == .Sphere || ev.selection_kind == .Quad) && ev.selected_idx >= 0 {
		btn_del   := rl.Rectangle{content.x + 106, content.y + 5, 60, 22}
		del_hover := rl.CheckCollisionPointRec(mouse, btn_del)
		rl.DrawRectangleRec(btn_del, del_hover ? rl.Color{200, 60, 60, 255} : rl.Color{140, 40, 40, 255})
		draw_ui_text(app, "Delete", i32(btn_del.x) + 8, i32(btn_del.y) + 4, 12, rl.RAYWHITE)
	}

	// Frustum / Focal toggles (camera gizmo visibility)
	btn_frustum := rl.Rectangle{content.x + 174, content.y + 5, 56, 22}
	btn_focal   := rl.Rectangle{content.x + 234, content.y + 5, 40, 22}
	frustum_hover := rl.CheckCollisionPointRec(mouse, btn_frustum)
	focal_hover   := rl.CheckCollisionPointRec(mouse, btn_focal)
	frustum_bg := (ev.show_frustum_gizmo ? rl.Color{70, 120, 130, 255} : rl.Color{45, 55, 70, 255})
	if frustum_hover { frustum_bg = ev.show_frustum_gizmo ? rl.Color{90, 150, 160, 255} : rl.Color{55, 68, 88, 255} }
	rl.DrawRectangleRec(btn_frustum, frustum_bg)
	rl.DrawRectangleLinesEx(btn_frustum, 1, ev.show_frustum_gizmo ? ACCENT_COLOR : BORDER_COLOR)
	draw_ui_text(app, "Frustum", i32(btn_frustum.x) + 4, i32(btn_frustum.y) + 4, 11, rl.RAYWHITE)
	focal_bg := (ev.show_focal_indicator ? rl.Color{130, 70, 70, 255} : rl.Color{45, 55, 70, 255})
	if focal_hover { focal_bg = ev.show_focal_indicator ? rl.Color{160, 90, 90, 255} : rl.Color{55, 68, 88, 255} }
	rl.DrawRectangleRec(btn_focal, focal_bg)
	rl.DrawRectangleLinesEx(btn_focal, 1, ev.show_focal_indicator ? ACCENT_COLOR : BORDER_COLOR)
	draw_ui_text(app, "Focal", i32(btn_focal.x) + 6, i32(btn_focal.y) + 4, 11, rl.RAYWHITE)

	// AABB / BVH visualization toggles
	btn_aabb, btn_sel, btn_bvh, btn_d_plus, btn_d_minus := edit_view_aabb_toolbar_rects(content)
	aabb_hover   := rl.CheckCollisionPointRec(mouse, btn_aabb)
	sel_hover    := rl.CheckCollisionPointRec(mouse, btn_sel)
	bvh_hover    := rl.CheckCollisionPointRec(mouse, btn_bvh)
	dplus_hover  := rl.CheckCollisionPointRec(mouse, btn_d_plus)
	dminus_hover := rl.CheckCollisionPointRec(mouse, btn_d_minus)
	aabb_bg := (ev.show_aabbs ? rl.Color{70, 120, 130, 255} : rl.Color{45, 55, 70, 255})
	if aabb_hover { aabb_bg = ev.show_aabbs ? rl.Color{90, 150, 160, 255} : rl.Color{55, 68, 88, 255} }
	rl.DrawRectangleRec(btn_aabb, aabb_bg)
	rl.DrawRectangleLinesEx(btn_aabb, 1, ev.show_aabbs ? ACCENT_COLOR : BORDER_COLOR)
	draw_ui_text(app, "AABB", i32(btn_aabb.x) + 4, i32(btn_aabb.y) + 4, 11, rl.RAYWHITE)
	if ev.show_aabbs {
		sel_bg := (ev.aabb_selected_only ? rl.Color{70, 120, 130, 255} : rl.Color{45, 55, 70, 255})
		if sel_hover { sel_bg = ev.aabb_selected_only ? rl.Color{90, 150, 160, 255} : rl.Color{55, 68, 88, 255} }
		rl.DrawRectangleRec(btn_sel, sel_bg)
		rl.DrawRectangleLinesEx(btn_sel, 1, ev.aabb_selected_only ? ACCENT_COLOR : BORDER_COLOR)
		draw_ui_text(app, "Sel", i32(btn_sel.x) + 4, i32(btn_sel.y) + 4, 11, rl.RAYWHITE)
	}
	bvh_bg := (ev.show_bvh_hierarchy ? rl.Color{70, 120, 130, 255} : rl.Color{45, 55, 70, 255})
	if bvh_hover { bvh_bg = ev.show_bvh_hierarchy ? rl.Color{90, 150, 160, 255} : rl.Color{55, 68, 88, 255} }
	rl.DrawRectangleRec(btn_bvh, bvh_bg)
	rl.DrawRectangleLinesEx(btn_bvh, 1, ev.show_bvh_hierarchy ? ACCENT_COLOR : BORDER_COLOR)
	draw_ui_text(app, "BVH", i32(btn_bvh.x) + 4, i32(btn_bvh.y) + 4, 11, rl.RAYWHITE)
	if ev.show_bvh_hierarchy {
		dplus_hover  := rl.CheckCollisionPointRec(mouse, btn_d_plus)
		dminus_hover := rl.CheckCollisionPointRec(mouse, btn_d_minus)
		dplus_bg  := dplus_hover ? rl.Color{55, 68, 88, 255} : rl.Color{45, 55, 70, 255}
		dminus_bg := dminus_hover ? rl.Color{55, 68, 88, 255} : rl.Color{45, 55, 70, 255}
		rl.DrawRectangleRec(btn_d_plus, dplus_bg)
		rl.DrawRectangleLinesEx(btn_d_plus, 1, BORDER_COLOR)
		draw_ui_text(app, "D+", i32(btn_d_plus.x) + 4, i32(btn_d_plus.y) + 4, 11, rl.RAYWHITE)
		rl.DrawRectangleRec(btn_d_minus, dminus_bg)
		rl.DrawRectangleLinesEx(btn_d_minus, 1, BORDER_COLOR)
		draw_ui_text(app, "D-", i32(btn_d_minus.x) + 4, i32(btn_d_minus.y) + 4, 11, rl.RAYWHITE)
		depth_label := ev.aabb_max_depth < 0 ? "\u221E" : fmt.ctprintf("%d", ev.aabb_max_depth)
		draw_ui_text(app, depth_label, i32(btn_d_minus.x) + 22 + 4, i32(btn_d_minus.y) + 5, 11, rl.Color{180, 185, 200, 220})
	}

	// "From View" — sync orbit (editor) camera → render camera
	btn_fromview  := rl.Rectangle{content.x + content.width - 178, content.y + 5, 82, 22}
	fv_hover      := rl.CheckCollisionPointRec(mouse, btn_fromview)
	rl.DrawRectangleRec(btn_fromview, fv_hover ? rl.Color{80, 110, 170, 255} : rl.Color{55, 75, 120, 255})
	draw_ui_text(app, "From View", i32(btn_fromview.x) + 6, i32(btn_fromview.y) + 4, 12, rl.RAYWHITE)

	btn_render   := rl.Rectangle{content.x + content.width - 90, content.y + 5, 82, 22}
	render_busy  := !app.finished
	render_ready := app.finished && app.r_render_pending
	render_hover := !render_busy && rl.CheckCollisionPointRec(mouse, btn_render)

	// Button color: bright green when render is pending, normal when not, dim when busy
	btn_color: rl.Color
	if render_busy {
		btn_color = rl.Color{45, 75, 45, 200}
	} else if render_ready {
		btn_color = rl.Color{80, 220, 80, 255} // bright green when pending
	} else if render_hover {
		btn_color = rl.Color{80, 190, 80, 255}
	} else {
		btn_color = rl.Color{50, 140, 50, 255}
	}
	rl.DrawRectangleRec(btn_render, btn_color)

	btn_text := render_busy ? cstring("Rendering…") : (render_ready ? cstring("Render*") : cstring("Render"))
	draw_ui_text(app, btn_text, i32(btn_render.x) + 6, i32(btn_render.y) + 4, 12, rl.RAYWHITE)

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
	ev      := &app.e_edit_view
	content := rect

	// Orbit camera is always updated at the end, even on early return.
	defer update_orbit_camera(ev)

	// Shared rects (mirror draw proc)
	btn_add      := rl.Rectangle{content.x + 8,                    content.y + 5, ADD_DROPDOWN_W, 22}
	btn_del      := rl.Rectangle{content.x + 106,                  content.y + 5, 60, 22}
	btn_frustum  := rl.Rectangle{content.x + 174,                  content.y + 5, 56, 22}
	btn_focal    := rl.Rectangle{content.x + 234,                  content.y + 5, 40, 22}
	btn_aabb, btn_sel, btn_bvh, btn_d_plus, btn_d_minus := edit_view_aabb_toolbar_rects(content)
	btn_fromview := rl.Rectangle{content.x + content.width - 178,  content.y + 5, 82, 22}
	btn_render   := rl.Rectangle{content.x + content.width - 90,   content.y + 5, 82, 22}
	AABB_MAX_DEPTH_CAP :: 20
	vp_rect    := rl.Rectangle{
		content.x,
		content.y + EDIT_TOOLBAR_H,
		content.width,
		content.height - EDIT_TOOLBAR_H - EDIT_PROPS_H,
	}
	props_rect := rl.Rectangle{
		content.x,
		content.y + content.height - EDIT_PROPS_H,
		content.width,
		EDIT_PROPS_H,
	}

	// ── Priority 0: Context menu input (highest priority when open) ───────
	if ev.ctx_menu_open {
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
						if entry.label == "Add Sphere" {
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
						} else if entry.label == "Add Quad" {
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
						} else if entry.label == "Delete" {
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
						} else if len(entry.cmd_id) > 0 {
							cmd_execute(app, entry.cmd_id)
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
		return
	}

	// ── Priority A: camera rotation ring drag ────────────────────────────
	// Free-flow: rotation is centered on the camera's own position (lookfrom).
	// The forward vector (lookat - lookfrom) is rotated; lookfrom stays fixed.
	//   axis 0 = X ring → rotate around {1,0,0}
	//   axis 1 = Y ring → rotate around {0,1,0}
	//   axis 2 = Z ring → rotate around {0,0,1}
	if ev.cam_rot_drag_axis >= 0 {
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
			// forward = lookat - lookfrom (camera center stays, forward direction rotates)
			forward := rl.Vector3{sa.x - sf.x, sa.y - sf.y, sa.z - sf.z}
			axis_vec: rl.Vector3
			switch ev.cam_rot_drag_axis {
			case 0: axis_vec = {1, 0, 0}
			case 1: axis_vec = {0, 1, 0}
			case 2: axis_vec = {0, 0, 1}
			}
			new_forward := rl.Vector3RotateByAxisAngle(forward, axis_vec, dx * 0.005)
			app.c_camera_params.lookat = {
				sf.x + new_forward.x,
				sf.y + new_forward.y,
				sf.z + new_forward.z,
			}
			// lookfrom is unchanged — camera rotates around its own center
		}
		return
	}

	// ── Priority B: camera body drag in viewport (XZ plane) ──────────────
	if ev.cam_drag_active {
		if !lmb {
			edit_history_push(&app.edit_history, ModifyCameraAction{
				before = ev.cam_drag_before_params,
				after  = app.c_camera_params,
			})
			mark_scene_dirty(app)
			ev.cam_drag_active = false
			app.r_render_pending = true
		} else {
			if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect, false); ok {
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
		return
	}

	// ── Priority C: camera property-field drag ────────────────────────────
	if ev.cam_prop_drag_idx >= 0 {
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
			DEG2RAD :: f32(math.PI / 180.0)
			delta := mouse.x - ev.cam_prop_drag_start_x
			sf := ev.cam_drag_start_lookfrom
			sa := ev.cam_drag_start_lookat
			s_yaw, s_pitch, s_dist := cam_forward_angles(
				{sf.x, sf.y, sf.z}, {sa.x, sa.y, sa.z})
			switch ev.cam_prop_drag_idx {
			case 0: // Pos X — translate whole camera (maintain look direction)
				d := delta * 0.02
				app.c_camera_params.lookfrom[0] = sf.x + d
				app.c_camera_params.lookat[0]   = sa.x + d
			case 1: // Pos Y
				d := delta * 0.02
				app.c_camera_params.lookfrom[1] = sf.y + d
				app.c_camera_params.lookat[1]   = sa.y + d
			case 2: // Pos Z
				d := delta * 0.02
				app.c_camera_params.lookfrom[2] = sf.z + d
				app.c_camera_params.lookat[2]   = sa.z + d
			case 3: // Yaw — rotate forward only; vup unchanged (independent gimbal)
				new_yaw := s_yaw + delta * 0.5 * DEG2RAD
				app.c_camera_params.lookat = lookat_from_angles(
					{sf.x, sf.y, sf.z}, new_yaw, s_pitch, s_dist)
			case 4: // Pitch — forward only; vup unchanged
				new_pitch := clamp(s_pitch + delta * 0.3 * DEG2RAD,
					f32(-math.PI * 0.45), f32(math.PI * 0.45))
				app.c_camera_params.lookat = lookat_from_angles(
					{sf.x, sf.y, sf.z}, s_yaw, new_pitch, s_dist)
			case 5: // Distance — forward only; vup unchanged
				new_dist := max(s_dist + delta * 0.05, f32(1.0))
				app.c_camera_params.lookat = lookat_from_angles(
					{sf.x, sf.y, sf.z}, s_yaw, s_pitch, new_dist)
			case 6: // Roll — only update vup; no gimbal lock, so allow full ±π
				new_roll := clamp(ev.cam_prop_drag_start_val + delta * 0.005,
					f32(-math.PI), f32(math.PI))
				app.c_camera_params.vup = compute_vup_from_forward_and_roll(
					app.c_camera_params.lookfrom, app.c_camera_params.lookat, new_roll)
			}
		}
		return
	}

	// ── Priority 1: active property-field drag (sphere only) ─────────────
	if ev.prop_drag_idx >= 0 {
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
				}
				SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
			}
		}
		return
	}

	// ── Priority 2: active viewport object drag (sphere or quad) ───────────
	if ev.drag_obj_active {
		if !lmb {
			ev.drag_obj_active = false
			// Commit drag to history
			if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
				if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
					edit_history_push(&app.edit_history, ModifySphereAction{
						idx    = ev.selected_idx,
						before = ev.drag_before,
						after  = sphere,
					})
					mark_scene_dirty(app)
					app_push_log(app, strings.clone("Move sphere"))
					app.r_render_pending = true
				}
			} else if ev.selection_kind == .Quad && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
				if quad, ok := GetSceneQuad(ev.scene_mgr, ev.selected_idx); ok {
					edit_history_push(&app.edit_history, ModifyQuadAction{
						idx    = ev.selected_idx,
						before = ev.drag_before_quad,
						after  = quad,
					})
					mark_scene_dirty(app)
					app_push_log(app, strings.clone("Move quad"))
					app.r_render_pending = true
				}
			}
		} else if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
			// require_inside=false: keep dragging even when mouse leaves viewport
			if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect, false); ok {
				if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
					if sphere, ok3 := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok3 {
						sphere.center[0] = xz.x - ev.drag_offset_xz[0]
						sphere.center[2] = xz.y - ev.drag_offset_xz[1]
						SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
					}
				}
			}
		} else if ev.selection_kind == .Quad && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
			if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect, false); ok {
				if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
					if quad, ok3 := GetSceneQuad(ev.scene_mgr, ev.selected_idx); ok3 {
						quad.Q[0] = xz.x - ev.drag_offset_xz[0]
						quad.Q[2] = xz.y - ev.drag_offset_xz[1]
						SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
					}
				}
			}
		}
		return
	}

	// ── Toolbar buttons ─────────────────────────────────────────────────
	if lmb_pressed {
		if rl.CheckCollisionPointRec(mouse, btn_frustum) {
			ev.show_frustum_gizmo = !ev.show_frustum_gizmo
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if rl.CheckCollisionPointRec(mouse, btn_focal) {
			ev.show_focal_indicator = !ev.show_focal_indicator
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if rl.CheckCollisionPointRec(mouse, btn_aabb) {
			ev.show_aabbs = !ev.show_aabbs
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if ev.show_aabbs && rl.CheckCollisionPointRec(mouse, btn_sel) {
			ev.aabb_selected_only = !ev.aabb_selected_only
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if rl.CheckCollisionPointRec(mouse, btn_bvh) {
			ev.show_bvh_hierarchy = !ev.show_bvh_hierarchy
			if !ev.show_bvh_hierarchy && ev.viz_bvh_root != nil {
				rt.free_bvh(ev.viz_bvh_root)
				ev.viz_bvh_root = nil
			}
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if ev.show_bvh_hierarchy && rl.CheckCollisionPointRec(mouse, btn_d_plus) {
			if ev.aabb_max_depth < AABB_MAX_DEPTH_CAP {
				ev.aabb_max_depth += 1
			}
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if ev.show_bvh_hierarchy && rl.CheckCollisionPointRec(mouse, btn_d_minus) {
			if ev.aabb_max_depth > -1 {
				ev.aabb_max_depth -= 1
			}
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		// Add Object dropdown: if open, handle item clicks or close on outside click
		dd_rect, sphere_item, quad_item := edit_view_add_dropdown_rects(btn_add)
		in_dropdown  := rl.CheckCollisionPointRec(mouse, dd_rect)
		in_btn_add   := rl.CheckCollisionPointRec(mouse, btn_add)

		if ev.add_dropdown_open {
			if rl.IsMouseButtonPressed(.LEFT) {
				if rl.CheckCollisionPointRec(mouse, sphere_item) {
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
					if g_app != nil { g_app.input_consumed = true }
					return
				} else if rl.CheckCollisionPointRec(mouse, quad_item) {
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
					if g_app != nil { g_app.input_consumed = true }
					return
				} else if !in_dropdown && !in_btn_add {
					ev.add_dropdown_open = false
				}
			}
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if rl.CheckCollisionPointRec(mouse, btn_add) {
			ev.add_dropdown_open = true
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		// Delete for sphere or quad (camera is non-deletable)
		if (ev.selection_kind == .Sphere || ev.selection_kind == .Quad) && ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, btn_del) {
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
			return
		}
		if rl.CheckCollisionPointRec(mouse, btn_fromview) {
			// Sync editor orbit camera → render camera (lookfrom/lookat only; preserve vup/roll)
			before := app.c_camera_params
			lookfrom, lookat := get_orbit_camera_pose(ev)
			app.c_camera_params.lookfrom = lookfrom
			app.c_camera_params.lookat   = lookat
			edit_history_push(&app.edit_history, ModifyCameraAction{
				before = before,
				after  = app.c_camera_params,
			})
			mark_scene_dirty(app)
			app.r_render_pending = true
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if app.finished && rl.CheckCollisionPointRec(mouse, btn_render) {
			// Use render camera params as-is (modified via gizmo or From View)

			// Export scene
			ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
			delete(app.r_world)
			app.r_world = app_build_world_from_scene(app, ev.export_scratch[:])
			AppendQuadsToWorld(ev.scene_mgr, &app.r_world)

			// Parse render settings
			width, height, res_ok := calculate_render_dimensions(app)
			samples, samp_ok := strconv.parse_int(app.r_samples_input)

			if !res_ok {
				// Check if it's a parse error or bounds error
				h, h_ok := strconv.parse_int(strings.trim_space(app.r_height_input))
				if !h_ok || h <= 0 {
					app_push_log(app, strings.clone("Invalid height. Must be a positive integer."))
				} else {
					// Bounds error
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

			if g_app != nil { g_app.input_consumed = true }
			return
		}
	}
	// "From view" copies orbit camera into camera_params so Render uses current view
	// Removed - now integrated into render button behavior

	// ── Property drag-field: start drag on click (camera) ────────────────
	if ev.selection_kind == .Camera && rl.CheckCollisionPointRec(mouse, props_rect) {
		fields := cam_orbit_prop_rects(props_rect)
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
					ev.cam_drag_start_lookat   = {cp.lookat[0],   cp.lookat[1],   cp.lookat[2]}
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

	// ── Property drag-field: start drag on click (sphere only) ───────────
	if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, props_rect) {
		fields := prop_field_rects(props_rect)
		if tmp, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
			vals := [4]f32{ tmp.center[0], tmp.center[1], tmp.center[2], tmp.radius }
			// Hover cursor
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
		}
		// (handled above)
	} else {
		rl.SetMouseCursor(.DEFAULT)
	}

	// ── Viewport: orbit, zoom, select, drag-start ────────────────────────
	mouse_in_vp := rl.CheckCollisionPointRec(mouse, vp_rect)

	// Right-mouse orbit + context menu disambiguation
	RMB_DRAG_THRESHOLD :: f32(5.0)
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
		if ev.rmb_drag_dist >= RMB_DRAG_THRESHOLD {
			ev.rmb_held = true
		}
		if ev.rmb_held {
			orb_delta      := rl.Vector2{mouse.x - ev.last_mouse.x, mouse.y - ev.last_mouse.y}
			ev.camera_yaw   += orb_delta.x * 0.005
			ev.camera_pitch += -orb_delta.y * 0.005
		}
		ev.last_mouse = mouse
	}
	if rmb_release && mouse_in_vp && ev.rmb_drag_dist < RMB_DRAG_THRESHOLD {
		// Short click → open context menu
		update_orbit_camera(ev)
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect, false); ok {
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
	if !rmb_down {
		ev.rmb_held = false
	}

	// Scroll zoom
	if mouse_in_vp {
		ev.orbit_distance -= rl.GetMouseWheelMove() * 0.8
	}

	// Left-click: select and begin drag (camera rotation ring / body / sphere/quad)
	if lmb_pressed && mouse_in_vp {
		update_orbit_camera(ev) // use current camera for pick ray (e.g. after scroll this frame)
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect); ok {
			cam_lookfrom := app.c_camera_params.lookfrom
			cam_pos_v3   := rl.Vector3{cam_lookfrom[0], cam_lookfrom[1], cam_lookfrom[2]}
			vp_offset    := rl.Vector2{vp_rect.x, vp_rect.y}

			if ev.selection_kind == .Camera {
				// Camera already selected: check rings first, then body, then sphere, then deselect
				ring := pick_rotation_ring(mouse, vp_offset, cam_pos_v3, ev.cam3d)
				if ring >= 0 {
					// Start ring drag — record render cam start pose
					ev.cam_drag_before_params  = app.c_camera_params
					ev.cam_rot_drag_axis       = ring
					ev.cam_rot_drag_start_x     = mouse.x
					ev.cam_rot_drag_start_y     = mouse.y
					cp := &app.c_camera_params
					ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
					ev.cam_drag_start_lookat   = {cp.lookat[0],   cp.lookat[1],   cp.lookat[2]}
					rl.SetMouseCursor(.RESIZE_ALL)
				} else if pick_camera(ray, cam_lookfrom) {
					// Start camera body drag — translate render camera in XZ
					cp := &app.c_camera_params
					ev.cam_drag_before_params  = app.c_camera_params
					ev.cam_drag_active         = true
					ev.cam_drag_plane_y        = cam_pos_v3.y
					ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
					ev.cam_drag_start_lookat   = {cp.lookat[0],   cp.lookat[1],   cp.lookat[2]}
					if xz, ok2 := ray_hit_plane_y(ray, ev.cam_drag_plane_y); ok2 {
						ev.cam_drag_start_hit_xz = {xz.x, xz.y}
					}
				} else {
					// Try closest object (sphere or quad)
					pick_kind, pick_idx, _ := PickClosestObject(ev.scene_mgr, ray)
					if pick_idx >= 0 && pick_kind == .Sphere {
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
					} else if pick_idx >= 0 && pick_kind == .Quad {
						ev.selection_kind  = .Quad
						ev.selected_idx    = pick_idx
						ev.drag_obj_active = true
						if quad, ok3 := GetSceneQuad(ev.scene_mgr, pick_idx); ok3 {
							ev.drag_before_quad = quad
							ev.drag_plane_y     = quad.Q[1]
							// Use the same horizontal plane intersection method used during drag updates
							// so click-to-select does not cause a snap/reset on the first drag frame.
							if xz, ok4 := ray_hit_plane_y(ray, ev.drag_plane_y); ok4 {
								ev.drag_offset_xz = {xz.x - quad.Q[0], xz.y - quad.Q[2]}
							} else {
								ev.drag_offset_xz = {0, 0}
							}
						}
					} else {
						ev.selection_kind = .None
						ev.selected_idx   = -1
					}
				}
			} else {
				// Camera not selected: closest object first, then camera body
				pick_kind, pick_idx, _ := PickClosestObject(ev.scene_mgr, ray)
				if pick_idx >= 0 && pick_kind == .Sphere {
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
				} else if pick_idx >= 0 && pick_kind == .Quad {
					ev.selection_kind  = .Quad
					ev.selected_idx    = pick_idx
					ev.drag_obj_active = true
					if quad, ok3 := GetSceneQuad(ev.scene_mgr, pick_idx); ok3 {
						ev.drag_before_quad = quad
						ev.drag_plane_y     = quad.Q[1]
						// Keep drag-start and drag-update math consistent to avoid click snapping.
						if xz, ok4 := ray_hit_plane_y(ray, ev.drag_plane_y); ok4 {
							ev.drag_offset_xz = {xz.x - quad.Q[0], xz.y - quad.Q[2]}
						} else {
							ev.drag_offset_xz = {0, 0}
						}
					}
				} else if pick_camera(ray, cam_lookfrom) {
					cp := &app.c_camera_params
					ev.cam_drag_before_params  = app.c_camera_params
					ev.selection_kind          = .Camera
					ev.selected_idx            = -1
					ev.cam_drag_active         = true
					ev.cam_drag_plane_y        = cam_pos_v3.y
					ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
					ev.cam_drag_start_lookat   = {cp.lookat[0],   cp.lookat[1],   cp.lookat[2]}
					if xz, ok2 := ray_hit_plane_y(ray, ev.cam_drag_plane_y); ok2 {
						ev.cam_drag_start_hit_xz = {xz.x, xz.y}
					}
				} else {
					ev.selection_kind = .None
					ev.selected_idx   = -1
				}
			}
		}
	}

	// Keyboard nudge (sphere only)
	MOVE_SPEED   :: f32(0.05)
	RADIUS_SPEED :: f32(0.02)
	if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
		any_nudge :=
			rl.IsKeyDown(.W)     || rl.IsKeyDown(.UP)          ||
			rl.IsKeyDown(.S)     || rl.IsKeyDown(.DOWN)        ||
			rl.IsKeyDown(.A)     || rl.IsKeyDown(.LEFT)        ||
			rl.IsKeyDown(.D)     || rl.IsKeyDown(.RIGHT)       ||
			rl.IsKeyDown(.Q)     || rl.IsKeyDown(.E)           ||
			rl.IsKeyDown(.EQUAL) || rl.IsKeyDown(.KP_ADD)      ||
			rl.IsKeyDown(.MINUS) || rl.IsKeyDown(.KP_SUBTRACT)

		// Capture before-state on first keydown of a nudge session
		if any_nudge && !ev.nudge_active {
			ev.nudge_active = true
			if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
				ev.nudge_before = sphere
			}
		}

		if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
			if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)    { sphere.center[2] -= MOVE_SPEED }
			if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)  { sphere.center[2] += MOVE_SPEED }
			if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)  { sphere.center[0] -= MOVE_SPEED }
			if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { sphere.center[0] += MOVE_SPEED }
			if rl.IsKeyDown(.Q)                         { sphere.center[1] -= MOVE_SPEED }
			if rl.IsKeyDown(.E)                         { sphere.center[1] += MOVE_SPEED }
			if rl.IsKeyDown(.EQUAL) || rl.IsKeyDown(.KP_ADD) {
				sphere.radius += RADIUS_SPEED
			}
			if rl.IsKeyDown(.MINUS) || rl.IsKeyDown(.KP_SUBTRACT) {
				sphere.radius -= RADIUS_SPEED
				if sphere.radius < 0.05 { sphere.radius = 0.05 }
			}
			SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
		}

		// Commit nudge to history when all keys released
		if !any_nudge && ev.nudge_active {
			ev.nudge_active = false
			if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
				edit_history_push(&app.edit_history, ModifySphereAction{
					idx    = ev.selected_idx,
					before = ev.nudge_before,
					after  = sphere,
				})
				mark_scene_dirty(app)
				app_push_log(app, strings.clone("Nudge sphere"))
				app.r_render_pending = true
			}
		}
	} else {
		// Selection lost — clear nudge state without pushing (nothing to commit)
		ev.nudge_active = false
	}
}
