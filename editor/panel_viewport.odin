package editor

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Editor 3D view: meters, perspective clip (matches rlgl defaults except near).
EDITOR_VIEW_CLIP_NEAR :: f32(0.1) // 10 cm — minimal useful depth
EDITOR_VIEW_CLIP_FAR  :: f32(1000.0) // 1 km — max view distance

MAX_GRID_LINES_PER_AXIS :: 100
GRID_TIER_HYSTERESIS   :: f32(1.20) // reduce tier flapping while orbiting/tilting
GRID_TARGET_PIXELS     :: f32(46)   // desired minor grid spacing on screen
GRID_MAJOR_RATIO       :: f32(8)    // major line spacing = minor * ratio
GRID_AXIS_EPS_FRAC     :: f32(0.02) // treat lines within 2% of cell as origin axis
BG_PRESET_COUNT  :: 6
BG_PRESET_ITEM_H :: f32(22)

bg_preset_name :: proc(i: int) -> cstring {
	switch i {
	case 0: return "Sky Blue"
	case 1: return "Dark Blue"
	case 2: return "White"
	case 3: return "Black"
	case 4: return "Sunset"
	case 5: return "Night Sky"
	case:  return "Custom"
	}
}

bg_preset_color :: proc(i: int) -> [3]f32 {
	switch i {
	case 0: return [3]f32{0.529, 0.808, 0.922}
	case 1: return [3]f32{0.1,   0.2,   0.5}
	case 2: return [3]f32{1.0,   1.0,   1.0}
	case 3: return [3]f32{0.0,   0.0,   0.0}
	case 4: return [3]f32{0.9,   0.5,   0.2}
	case 5: return [3]f32{0.05,  0.05,  0.15}
	case:   return [3]f32{0.0,   0.0,   0.0}
	}
}

bg_preset_item_rect :: proc(popover: rl.Rectangle, idx: int) -> rl.Rectangle {
	return rl.Rectangle{
		popover.x + 4,
		popover.y + 6 + f32(idx) * BG_PRESET_ITEM_H,
		popover.width - 8,
		BG_PRESET_ITEM_H - 2,
	}
}

// draw_world_axis draws RGB axis lines through the origin in ±EDITOR_VIEW_CLIP_FAR
// (Godot-style infinite axes, clipped by the view far plane).
draw_world_axis :: proc(_: ^EditViewState) {
	f := EDITOR_VIEW_CLIP_FAR
	o := rl.Vector3{0, 0, 0}
	rl.DrawLine3D(o + {-f, 0, 0}, o + {f, 0, 0}, rl.RED)
	rl.DrawLine3D(o + {0, -f, 0}, o + {0, f, 0}, rl.GREEN)
	rl.DrawLine3D(o + {0, 0, -f}, o + {0, 0, f}, rl.BLUE)
}

// viewport_ray_dir matches compute_viewport_ray (ui_viewport): perspective ray through
// normalized viewport UV (u,v) in [0,1]², Y-down screen space like mouse picking.
viewport_ray_dir :: proc(cam: rl.Camera3D, tex_w, tex_h: i32, u, v: f32) -> rl.Vector3 {
	forward := rl.Vector3Normalize(cam.target - cam.position)
	right   := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, cam.up))
	upv     := rl.Vector3CrossProduct(right, forward)
	aspect  := f32(tex_w) / max(f32(tex_h), f32(1e-6))
	half_h  := math.tan(cam.fovy * math.PI / 360.0)
	half_w  := half_h * aspect
	ndc_x   := (u * 2.0 - 1.0) * half_w
	ndc_y   := (1.0 - v * 2.0) * half_h
	return rl.Vector3Normalize(forward + right * ndc_x + upv * ndc_y)
}

// ray_hit_xz_plane_y0: camera ray vs y=0; returns distance along ray and xz hit.
// Parallel to the plane or hit behind the camera → ok = false.
ray_hit_xz_plane_y0 :: proc(origin, dir: rl.Vector3) -> (ok: bool, dist: f32, xz: rl.Vector2) {
	dy := dir.y
	if math.abs(dy) < 1e-6 { return false, 0, {} }
	t := -origin.y / dy
	if t < EDITOR_VIEW_CLIP_NEAR * 0.01 { return false, 0, {} }
	return true, t, {
		origin.x + t * dir.x,
		origin.z + t * dir.z,
	}
}

@(private)
grid_world_units_per_pixel :: proc(cam: rl.Camera3D, tex_w, tex_h: i32) -> (wpp: f32, ok: bool) {
	if tex_w <= 0 || tex_h <= 0 { return 0, false }

	SAMPLE_PX :: f32(20)
	du := clamp(SAMPLE_PX / max(f32(tex_w), f32(1)), f32(0.01), f32(0.25))
	samples := [8][2]f32{
		{0.5, 0.70},
		{0.5, 0.85},
		{0.25, 0.85},
		{0.75, 0.85},
		{0.5, 0.5},
		{0.5, 0.95},
		{0.05, 0.95},
		{0.95, 0.95},
	}

	for s in samples {
		u := s[0]
		v := s[1]
		dir0 := viewport_ray_dir(cam, tex_w, tex_h, u, v)
		ok0, _, p0 := ray_hit_xz_plane_y0(cam.position, dir0)
		if !ok0 { continue }

		u1 := clamp(u + du, f32(0), f32(1))
		dir1 := viewport_ray_dir(cam, tex_w, tex_h, u1, v)
		ok1, _, p1 := ray_hit_xz_plane_y0(cam.position, dir1)
		px := (u1 - u) * f32(tex_w)

		if !ok1 || px < 1 {
			u1 = clamp(u - du, f32(0), f32(1))
			dir1 = viewport_ray_dir(cam, tex_w, tex_h, u1, v)
			ok1, _, p1 = ray_hit_xz_plane_y0(cam.position, dir1)
			px = (u - u1) * f32(tex_w)
		}
		if !ok1 || px < 1 { continue }

		dx := p1.x - p0.x
		dz := p1.y - p0.y
		world := math.sqrt(dx*dx + dz*dz)
		if world <= 1e-6 { continue }
		return world / px, true
	}
	return 0, false
}

draw_adaptive_infinite_grid :: proc(app: ^App, fb_w, fb_h: i32) {
	ev := &app.e_edit_view
	if ev == nil || !ev.grid_visible { return }
	cam3d := ev.cam3d
	pos := cam3d.position
	// Match BeginMode3D's projection: while a render texture is bound, this is the
	// active framebuffer size (not the window and not necessarily stale EditView tex fields).
	tw := fb_w
	th := fb_h
	rw := rl.GetRenderWidth()
	rh := rl.GetRenderHeight()
	if rw > 0 && rh > 0 {
		tw = i32(rw)
		th = i32(rh)
	}
	if tw <= 0 || th <= 0 { return }

	density := clamp(ev.grid_density, f32(0.25), f32(8.0))

	world_per_px, ok_scale := grid_world_units_per_pixel(cam3d, tw, th)
	if ok_scale {
		desired_base := max(world_per_px*GRID_TARGET_PIXELS, f32(1e-5))
		if ev.grid_scale_tier == -999 {
			ev.grid_scale_tier = int(math.round(math.log2(f64(desired_base))))
		} else {
			cur := ev.grid_scale_tier
			cur_cell := f32(math.pow(2.0, f64(cur)))
			for desired_base > cur_cell*GRID_TIER_HYSTERESIS {
				cur += 1
				cur_cell *= 2.0
			}
			for desired_base < cur_cell/GRID_TIER_HYSTERESIS {
				cur -= 1
				cur_cell *= 0.5
			}
			ev.grid_scale_tier = cur
		}
	} else if ev.grid_scale_tier == -999 {
		fallback := max(math.abs(pos.y), EDITOR_VIEW_CLIP_NEAR)
		ev.grid_scale_tier = int(math.round(math.log2(f64(fallback))))
	}

	base_cell := f32(math.pow(2.0, f64(ev.grid_scale_tier)))
	base_cell = clamp(base_cell, f32(0.0001), EDITOR_VIEW_CLIP_FAR)
	step := base_cell / density
	ev.grid_current_cell = step

	cells := [2]f32{step * GRID_MAJOR_RATIO, step}
	alphas := [2]u8{120, 70}
	axis_col := rl.Color{120, 140, 185, 180}

	line_radius := f32(MAX_GRID_LINES_PER_AXIS / 2)
	extent := EDITOR_VIEW_CLIP_FAR

	for li in 0 ..< len(cells) {
		c := cells[li]
		a := alphas[li]
		base_col := rl.Color{95, 105, 130, a}

		x_start := math.floor(pos.x/c)*c - line_radius*c
		for i := 0; i <= MAX_GRID_LINES_PER_AXIS; i += 1 {
			wx := math.round((x_start + f32(i)*c) / c) * c
			col := base_col
			if math.abs(wx) <= c * GRID_AXIS_EPS_FRAC { col = axis_col }
			rl.DrawLine3D({wx, 0, -extent}, {wx, 0, extent}, col)
		}

		z_start := math.floor(pos.z/c)*c - line_radius*c
		for i := 0; i <= MAX_GRID_LINES_PER_AXIS; i += 1 {
			wz := math.round((z_start + f32(i)*c) / c) * c
			col := base_col
			if math.abs(wz) <= c * GRID_AXIS_EPS_FRAC { col = axis_col }
			rl.DrawLine3D({-extent, 0, wz}, {extent, 0, wz}, col)
		}
	}
}


render_viewport_to_texture :: proc(app: ^App, width, height: i32) {
	ev := &app.e_edit_view
	sm := ev.scene_mgr
	if sm == nil || width <= 0 || height <= 0 { return }

	// TODO: Resize only when delta exceeds a small tolerance (e.g. 4px) or after a short cooldown,
	// to avoid reallocating every frame during drag-resize (stale frame + GPU churn).
	if width != ev.tex_w || height != ev.tex_h {
		if ev.tex_w > 0 {
			rl.UnloadRenderTexture(ev.viewport_tex)
		}
		ev.viewport_tex = rl.LoadRenderTexture(width, height)
		ev.tex_w = width
		ev.tex_h = height
	}

	if ev.tex_w <= 0 || ev.tex_h <= 0 { return }

	ensure_viewport_sphere_cache_filled(app, ev)
	if sync_render_camera_from_editor(ev, &app.c_camera_params) {
		app.scene_version += 1
	}

	rl.BeginTextureMode(ev.viewport_tex)
	rl.ClearBackground(rl.Color{20, 25, 35, 255})
	prev_clip_n := rlgl.GetCullDistanceNear()
	prev_clip_f := rlgl.GetCullDistanceFar()
	rlgl.SetClipPlanes(f64(EDITOR_VIEW_CLIP_NEAR), f64(EDITOR_VIEW_CLIP_FAR))
	rl.BeginMode3D(ev.cam3d)
	draw_adaptive_infinite_grid(app, width, height)
	draw_viewport_scene_objects(app, ev, ev.selection_kind, ev.selected_idx)
	draw_viewport_camera_gizmos(app, ev)
	draw_world_axis(ev)
	rl.EndMode3D()
	rlgl.SetClipPlanes(prev_clip_n, prev_clip_f)
	rl.EndTextureMode()
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
