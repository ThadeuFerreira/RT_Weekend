package editor

import "core:math"
import "core:strings"
import rl "vendor:raylib"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"

// draw_quad_3d draws a quad as two triangles, both front- and back-face, so it is
// visible from either side (matches path tracer's set_face_normal double-sided behavior).
// Call inside BeginMode3D.
draw_quad_3d :: proc(q: rt.Quad, color: rl.Color) {
	v0 := rl.Vector3{q.Q[0], q.Q[1], q.Q[2]}
	v1 := rl.Vector3{q.Q[0] + q.u[0], q.Q[1] + q.u[1], q.Q[2] + q.u[2]}
	v2 := rl.Vector3{q.Q[0] + q.u[0] + q.v[0], q.Q[1] + q.u[1] + q.v[1], q.Q[2] + q.u[2] + q.v[2]}
	v3 := rl.Vector3{q.Q[0] + q.v[0], q.Q[1] + q.v[1], q.Q[2] + q.v[2]}
	// Front face (one winding)
	rl.DrawTriangle3D(v0, v1, v2, color)
	rl.DrawTriangle3D(v0, v2, v3, color)
	// Back face (reversed winding) so quad is visible from behind
	rl.DrawTriangle3D(v0, v2, v1, color)
	rl.DrawTriangle3D(v0, v3, v2, color)
	rl.DrawLine3D(v0, v1, rl.BLACK)
	rl.DrawLine3D(v1, v2, rl.BLACK)
	rl.DrawLine3D(v2, v3, rl.BLACK)
	rl.DrawLine3D(v3, v0, rl.BLACK)
}

// sphere_solid_color_from_albedo returns the display color for a sphere when drawn
// as a solid (no texture). Used by preview and edit view fallback.
sphere_solid_color_from_albedo :: proc(tex: core.Texture) -> [3]f32 {
	disp_col := [3]f32{0.5, 0.5, 0.5}
	#partial switch t in tex {
	case core.ConstantTexture: disp_col = t.color
	case core.CheckerTexture:  disp_col = t.even
	}
	return disp_col
}

// draw_sphere_solid draws a sphere with solid color and wireframe. Call inside BeginMode3D.
draw_sphere_solid :: proc(center: [3]f32, radius: f32, color: [3]f32, selected: bool) {
	col: rl.Color
	if selected {
		col = rl.YELLOW
	} else {
		col = rl.Color{
			u8(clamp(color[0], 0.0, 1.0) * 255),
			u8(clamp(color[1], 0.0, 1.0) * 255),
			u8(clamp(color[2], 0.0, 1.0) * 255),
			255,
		}
	}
	wire_col := selected ? rl.Color{255, 220, 0, 200} : rl.Color{30, 30, 30, 180}
	pos := rl.Vector3{center[0], center[1], center[2]}
	rl.DrawSphere(pos, radius, col)
	rl.DrawSphereWires(pos, radius + 0.01, 8, 8, wire_col)
}

// draw_quad_with_material_color draws a quad using rt.material_display_color for tint.
draw_quad_with_material_color :: proc(q: rt.Quad, selected: bool) {
	col: rl.Color
	if selected {
		col = rl.YELLOW
	} else {
		dc := rt.material_display_color(q.material)
		col = rl.Color{
			u8(clamp(dc[0], 0.0, 1.0) * 255),
			u8(clamp(dc[1], 0.0, 1.0) * 255),
			u8(clamp(dc[2], 0.0, 1.0) * 255),
			255,
		}
	}
	draw_quad_3d(q, col)
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

// ensure_viewport_sphere_cache_filled invalidates cache if dirty, sizes it to match scene,
// and fills any cache miss with mesh+texture. Call before BeginTextureMode (creating
// mesh/model inside render target can prevent the texture from showing).
// Shared by Viewport and Camera Preview so both display textured spheres the same way.
ensure_viewport_sphere_cache_filled :: proc(app: ^App, ev: ^EditViewState) {
	sm := ev.scene_mgr
	if sm == nil { return }
	if ev.viewport_sphere_cache_dirty {
		for i in 0..<len(ev.viewport_sphere_cache) {
			free_viewport_sphere_cache_entry(&ev.viewport_sphere_cache[i])
		}
		clear(&ev.viewport_sphere_cache)
		ev.viewport_sphere_cache_dirty = false
	}
	n_objects := len(sm.objects)
	for len(ev.viewport_sphere_cache) > n_objects {
		free_viewport_sphere_cache_entry(&ev.viewport_sphere_cache[len(ev.viewport_sphere_cache) - 1])
		pop(&ev.viewport_sphere_cache)
	}
	for len(ev.viewport_sphere_cache) < n_objects {
		append(&ev.viewport_sphere_cache, ViewportSphereCacheEntry{})
	}
	N_RINGS  :: 64
	N_SLICES :: 64
	for i in 0..<n_objects {
		s, ok := sm.objects[i].(core.SceneSphere)
		if !ok { continue }
		entry   := &ev.viewport_sphere_cache[i]
		tex_sig := texture_view_sig(app, s.albedo)
		cache_hit := entry.tex.id != 0 && entry.radius == s.radius && entry.tex_sig == tex_sig
		if cache_hit {
			delete(tex_sig)
			continue
		}
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
		delete(tex_sig)
	}
}

// volume_world_corners fills the 8 world-space corners of a SceneVolume (box after rotate_y + translate).
// Order: back face z=min (0..3), front face z=max (4..7); same as box corners.
volume_world_corners :: proc(v: core.SceneVolume, corners: ^[8]rl.Vector3) {
	cos_y := math.cos(v.rotate_y_deg * (math.PI / 180.0))
	sin_y := math.sin(v.rotate_y_deg * (math.PI / 180.0))
	min_x, min_y, min_z := v.box_min[0], v.box_min[1], v.box_min[2]
	max_x, max_y, max_z := v.box_max[0], v.box_max[1], v.box_max[2]
	tx, ty, tz := v.translate[0], v.translate[1], v.translate[2]
	rot_xz :: proc(x, z: f32, cx, sx: f32) -> (wx, wz: f32) {
		wx = cx*x - sx*z
		wz = sx*x + cx*z
		return
	}
	local := [8][3]f32{
		{min_x, min_y, min_z}, {max_x, min_y, min_z}, {max_x, max_y, min_z}, {min_x, max_y, min_z},
		{min_x, min_y, max_z}, {max_x, min_y, max_z}, {max_x, max_y, max_z}, {min_x, max_y, max_z},
	}
	for i in 0..<8 {
		lx, lz := local[i][0], local[i][2]
		wx, wz := rot_xz(lx, lz, cos_y, sin_y)
		corners[i] = rl.Vector3{tx + wx, ty + local[i][1], tz + wz}
	}
}

// volume_world_aabb returns the world-space AABB of a SceneVolume (for ray picking).
volume_world_aabb :: proc(v: core.SceneVolume) -> rl.BoundingBox {
	corners: [8]rl.Vector3
	volume_world_corners(v, &corners)
	min_v := rl.Vector3{1e30, 1e30, 1e30}
	max_v := rl.Vector3{-1e30, -1e30, -1e30}
	for i in 0..<8 {
		if corners[i].x < min_v.x { min_v.x = corners[i].x }
		if corners[i].y < min_v.y { min_v.y = corners[i].y }
		if corners[i].z < min_v.z { min_v.z = corners[i].z }
		if corners[i].x > max_v.x { max_v.x = corners[i].x }
		if corners[i].y > max_v.y { max_v.y = corners[i].y }
		if corners[i].z > max_v.z { max_v.z = corners[i].z }
	}
	return rl.BoundingBox{min = min_v, max = max_v}
}

// pick_closest_volume returns the index and hit distance of the closest volume hit by the ray, or (-1, 1e30).
pick_closest_volume :: proc(ray: rl.Ray, volumes: []core.SceneVolume) -> (idx: int, t: f32) {
	idx = -1
	t = 1e30
	dir := rl.Vector3Normalize(ray.direction)
	norm_ray := rl.Ray{position = ray.position, direction = dir}
	for i in 0..<len(volumes) {
		box := volume_world_aabb(volumes[i])
		hit := rl.GetRayCollisionBox(norm_ray, box)
		if hit.hit && hit.distance > 0 && f32(hit.distance) < t {
			t = f32(hit.distance)
			idx = i
		}
	}
	return
}

// draw_volume_cube_wireframe draws a volume as a transparent wireframe box (edges only). Call inside BeginMode3D.
// When selected is true, edges are drawn in yellow.
draw_volume_cube_wireframe :: proc(v: core.SceneVolume, selected: bool = false) {
	corners: [8]rl.Vector3
	volume_world_corners(v, &corners)
	edge_col := selected ? rl.Color{255, 220, 0, 200} : rl.Color{100, 200, 255, 180}
	// Back face (z=min): 0-1-2-3
	rl.DrawLine3D(corners[0], corners[1], edge_col)
	rl.DrawLine3D(corners[1], corners[2], edge_col)
	rl.DrawLine3D(corners[2], corners[3], edge_col)
	rl.DrawLine3D(corners[3], corners[0], edge_col)
	// Front face (z=max): 4-5-6-7
	rl.DrawLine3D(corners[4], corners[5], edge_col)
	rl.DrawLine3D(corners[5], corners[6], edge_col)
	rl.DrawLine3D(corners[6], corners[7], edge_col)
	rl.DrawLine3D(corners[7], corners[4], edge_col)
	// Connecting edges
	rl.DrawLine3D(corners[0], corners[4], edge_col)
	rl.DrawLine3D(corners[1], corners[5], edge_col)
	rl.DrawLine3D(corners[2], corners[6], edge_col)
	rl.DrawLine3D(corners[3], corners[7], edge_col)
}

// draw_viewport_scene_objects draws all scene objects (spheres with cache or solid, quads).
// Call inside BeginMode3D. Uses ev.viewport_sphere_cache; pass selection_kind/selected_idx
// for Viewport (highlight), or .None/-1 for Camera Preview (no highlight). Shared by both panels.
draw_viewport_scene_objects :: proc(
	app: ^App,
	ev: ^EditViewState,
	selection_kind: EditViewSelectionKind,
	selected_idx: int,
) {
	if app == nil || ev == nil { return }
	sm := ev.scene_mgr
	if sm == nil { return }
	n_objects := len(sm.objects)
	for i in 0..<n_objects {
		if i >= len(ev.viewport_sphere_cache) { continue }
		selected := (selection_kind == .Sphere || selection_kind == .Quad) && selected_idx == i
		#partial switch o in sm.objects[i] {
		case core.SceneSphere:
			s := o
			center := s.center
			wire_col := rl.Color{30, 30, 30, 180}
			if selected { wire_col = rl.Color{255, 220, 0, 200} }
			entry := &ev.viewport_sphere_cache[i]
			if entry.tex.id != 0 {
				tint := rl.WHITE
				if selected { tint = rl.YELLOW }
				rl.DrawModelEx(entry.model, center, {0, 1, 0}, -90.0, {1, 1, 1}, tint)
				rl.DrawSphereWires(center, s.radius + 0.01, 8, 8, wire_col)
			} else {
				draw_sphere_solid(s.center, s.radius, sphere_solid_color_from_albedo(s.albedo), selected)
			}
		case rt.Quad:
			draw_quad_with_material_color(o, selected)
		}
	}
}

// draw_viewport_camera_gizmos draws the render camera gizmo (body), optional rotation rings, frustum wireframe, and focal-distance indicator.
// In RenderCamera binding the camera body gizmo is hidden (editor IS the camera), but frustum and focal indicator still draw.
draw_viewport_camera_gizmos :: proc(app: ^App, ev: ^EditViewState) {
	if app == nil || ev == nil { return }
	cp := &app.c_camera_params
	cam_pos := rl.Vector3{cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
	cam_at  := rl.Vector3{cp.lookat[0], cp.lookat[1], cp.lookat[2]}
	vup     := rl.Vector3{cp.vup[0], cp.vup[1], cp.vup[2]}

	// Camera body gizmo and rotation rings only in FreeFly (in RenderCamera the gizmo would sit at the view origin).
	if ev.camera_binding == .FreeFly {
		draw_camera_gizmo(cam_pos, cam_at, vup, ev.selection_kind == .Camera)
		if ev.selection_kind == .Camera {
			draw_camera_rotation_rings(cam_pos, ev.cam_rot_drag_axis)
		}
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
}

