package editor

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Editor 3D view: meters, perspective clip (matches rlgl defaults except near).
EDITOR_VIEW_CLIP_NEAR :: f32(0.1) // 10 cm — minimal useful depth
EDITOR_VIEW_CLIP_FAR  :: f32(1000.0) // 1 km — max view distance

// Grid LOD: cell sizes are powers of 10 in [0.1 m, 1000 m].
GRID_LOD_EXP_MIN :: -1 // 10^-1 = 0.1 m
GRID_LOD_EXP_MAX :: 3  // 10^3 = 1000 m

// Maximum lines drawn per axis per level. Caps GPU draw calls; also used to
// bound the drawing extent per level so the coarse/fine split stays visible
// even at shallow view angles (see draw_adaptive_infinite_grid).
MAX_GRID_LINES_PER_AXIS :: 100

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

// viewport_ray_dir returns the world-space unit direction for a perspective ray
// through viewport UV (u,v) in [0,1]², Y-down (u=0,v=0 is top-left).
// Matches the formula used in compute_viewport_ray (ui_viewport.odin).
viewport_ray_dir :: proc(cam: rl.Camera3D, tex_w, tex_h: i32, u, v: f32) -> rl.Vector3 {
	forward := rl.Vector3Normalize(cam.target - cam.position)
	right   := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, cam.up))
	upv     := rl.Vector3CrossProduct(right, forward)
	aspect  := f32(tex_w) / max(f32(tex_h), f32(1e-6))
	half_h  := math.tan(cam.fovy * math.PI / 360.0) // fovy is degrees
	half_w  := half_h * aspect
	ndc_x   := (u * 2.0 - 1.0) * half_w
	ndc_y   := (1.0 - v * 2.0) * half_h
	return rl.Vector3Normalize(forward + right * ndc_x + upv * ndc_y)
}

// ray_hit_xz_plane_y0 intersects a ray with the y=0 plane.
// Returns ok=false when the ray is parallel to the plane or hits behind the origin.
ray_hit_xz_plane_y0 :: proc(origin, dir: rl.Vector3) -> (ok: bool, dist: f32, xz: rl.Vector2) {
	dy := dir.y
	if math.abs(dy) < 1e-6 { return false, 0, {} }
	t := -origin.y / dy
	if t < 0 { return false, 0, {} }
	return true, t, {
		origin.x + t * dir.x,
		origin.z + t * dir.z,
	}
}

// draw_adaptive_infinite_grid draws a Godot-style adaptive XZ grid on y=0.
//
// Algorithm overview
// ──────────────────
// 1. Cast five viewport rays (screen center + four corners) to the y=0 plane.
//    The shortest hit distance drives the LOD — it represents the closest part of
//    the grid that is actually visible, so the cell size is always appropriate for
//    what the user sees near the camera.
//
// 2. Compute exp = floor(log10(dist)).  The primary cell is 10^exp / density.
//    Two levels are drawn: fine (step) and coarse (step×10), crossfaded across
//    the decade using frac = log10(dist) − exp.  This is the same technique
//    Godot uses for its infinite grid.
//
// 3. The drawing extent for each level is the intersection of:
//      a) the world frustum footprint on y=0 (min/max XZ from all corner hits), and
//      b) a per-level line-budget cap: camera XZ ± (cell × MAX_GRID_LINES_PER_AXIS/2).
//    Using cap (b) instead of a coarsening loop is the key to stability at shallow
//    angles: when the frustum footprint is enormous (view nearly horizontal) the
//    cell size does NOT jump — only the drawing extent is reduced.  The far grid
//    lines near the horizon are clipped by the GPU far plane anyway.
//
// 4. Lines within 2% of a cell width of the origin axes are highlighted in the
//    editor's accent colour instead of the grey grid colour.
draw_adaptive_infinite_grid :: proc(app: ^App, fb_w, fb_h: i32) {
	ev := &app.e_edit_view
	if ev == nil || !ev.grid_visible { return }
	cam3d := ev.cam3d
	pos   := cam3d.position

	// While a render texture is bound, GetRenderWidth/Height return the texture
	// dimensions, which is what BeginMode3D's projection was built for.
	tw := fb_w
	th := fb_h
	if rw := rl.GetRenderWidth();  rw > 0 { tw = i32(rw) }
	if rh := rl.GetRenderHeight(); rh > 0 { th = i32(rh) }
	if tw <= 0 || th <= 0 { return }

	density := clamp(ev.grid_density, f32(0.25), f32(8.0))

	// ── Step 1: cast five rays, collect frustum footprint and min hit distance ──
	uv_center  := [2]f32{0.5, 0.5}
	uv_corners := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}

	min_x, max_x := f32(0), f32(0)
	min_z, max_z := f32(0), f32(0)
	first_corner := true
	min_dist     := f32(1e30)

	dir_c := viewport_ray_dir(cam3d, tw, th, uv_center[0], uv_center[1])
	if ok_c, d_c, xz_c := ray_hit_xz_plane_y0(pos, dir_c); ok_c {
		min_dist = d_c
		min_x = xz_c.x; max_x = xz_c.x
		min_z = xz_c.y; max_z = xz_c.y
		first_corner = false
	}
	for uv in uv_corners {
		dir := viewport_ray_dir(cam3d, tw, th, uv[0], uv[1])
		ok, d, xz := ray_hit_xz_plane_y0(pos, dir)
		if !ok { continue }
		if d < min_dist { min_dist = d }
		if first_corner {
			min_x = xz.x; max_x = xz.x
			min_z = xz.y; max_z = xz.y
			first_corner = false
		} else {
			if xz.x < min_x { min_x = xz.x }
			if xz.x > max_x { max_x = xz.x }
			if xz.y < min_z { min_z = xz.y }
			if xz.y > max_z { max_z = xz.y }
		}
	}

	// Fallback when all rays miss (looking at sky): use camera height above plane.
	if first_corner {
		min_dist = max(math.abs(pos.y), EDITOR_VIEW_CLIP_NEAR)
		r := EDITOR_VIEW_CLIP_FAR
		min_x = pos.x - r; max_x = pos.x + r
		min_z = pos.z - r; max_z = pos.z + r
	}

	dist := clamp(min_dist, EDITOR_VIEW_CLIP_NEAR, EDITOR_VIEW_CLIP_FAR)

	// ── Step 2: Godot-style decade LOD ──────────────────────────────────────────
	log_dist := math.log10(f64(dist))
	exp      := clamp(int(math.floor(log_dist)), GRID_LOD_EXP_MIN, GRID_LOD_EXP_MAX)
	frac     := f32(log_dist - f64(exp))

	step_base := f32(math.pow(10.0, f64(exp)))
	step      := step_base / density
	ev.grid_scale_tier   = exp
	ev.grid_current_cell = step

	// Two levels with crossfade across the decade.
	cells  := [2]f32{step * 10.0, step}
	alphas := [2]u8{
		u8(40 + int(90 * frac)),      // coarse: fades in  as we zoom out
		u8(int(130 * (1.0 - frac))),  // fine:   fades out as we zoom out
	}
	axis_col := rl.Color{120, 140, 185, 180}

	// ── Step 3: draw each level ──────────────────────────────────────────────────
	for li in 0 ..< len(cells) {
		c := cells[li]
		a := alphas[li]
		if a < 5 { continue }

		// Extent = frustum footprint intersected with per-level line-budget cap.
		// The cap prevents the coarsening instability at shallow view angles:
		// large footprints are simply drawn to fewer lines, not to larger cells.
		half_ext := c * f32(MAX_GRID_LINES_PER_AXIS / 2)
		x_lo := max(min_x, pos.x - half_ext)
		x_hi := min(max_x, pos.x + half_ext)
		z_lo := max(min_z, pos.z - half_ext)
		z_hi := min(max_z, pos.z + half_ext)

		mg   := max(c * f32(0.25), c * f32(0.05))
		x_lo -= mg; x_hi += mg
		z_lo -= mg; z_hi += mg

		ix0 := int(math.floor(f64(x_lo / c)))
		ix1 := int(math.ceil(f64(x_hi / c)))
		jz0 := int(math.floor(f64(z_lo / c)))
		jz1 := int(math.ceil(f64(z_hi / c)))

		base_col := rl.Color{95, 105, 130, a}

		for i := ix0; i <= ix1; i += 1 {
			wx  := f32(i) * c
			col := base_col
			if math.abs(wx) <= c * f32(0.02) { col = axis_col }
			rl.DrawLine3D({wx, 0, z_lo}, {wx, 0, z_hi}, col)
		}
		for j := jz0; j <= jz1; j += 1 {
			wz  := f32(j) * c
			col := base_col
			if math.abs(wz) <= c * f32(0.02) { col = axis_col }
			rl.DrawLine3D({x_lo, 0, wz}, {x_hi, 0, wz}, col)
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
