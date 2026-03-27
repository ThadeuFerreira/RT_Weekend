package editor

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

MAX_GRID_LINES_PER_AXIS :: 52
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

// draw_world_axis draws RGB axis lines at the origin so users can identify
// coordinate directions (X=red, Y=green, Z=blue).  Length scales with scene.
draw_world_axis :: proc(ev: ^EditViewState) {
	_, radius, _ := scene_scale_recommendations(ev.scene_mgr)
	size := max(radius * 0.5, 1.0)
	origin := rl.Vector3{0, 0, 0}
	rl.DrawLine3D(origin, origin + {size, 0, 0}, rl.RED)
	rl.DrawLine3D(origin, origin + {0, size, 0}, rl.GREEN)
	rl.DrawLine3D(origin, origin + {0, 0, size}, rl.BLUE)
}

draw_adaptive_infinite_grid :: proc(ev: ^EditViewState) {
	if ev == nil || !ev.grid_visible { return }
	center, radius, _ := scene_scale_recommendations(ev.scene_mgr)
	cam := ev.cam3d.position
	base_cell := clamp(radius / 18.0, f32(0.1), f32(1000.0)) / clamp(ev.grid_density, f32(0.25), f32(8.0))
	levels := [3]f32{base_cell, base_cell * 10.0, base_cell * 100.0}
	level_ext := [3]f32{28.0, 40.0, 55.0}
	axis_col := rl.Color{120, 140, 185, 170}

	for li in 0..<len(levels) {
		cell := levels[li]
		ext_cells := level_ext[li]
		range_w := ext_cells * cell
		min_x := math.floor((cam.x - range_w) / cell) * cell
		max_x := math.ceil((cam.x + range_w) / cell) * cell
		min_z := math.floor((cam.z - range_w) / cell) * cell
		max_z := math.ceil((cam.z + range_w) / cell) * cell

		count_x := int((max_x - min_x) / cell + 1)
		count_z := int((max_z - min_z) / cell + 1)
		step_x := 1
		if count_x > MAX_GRID_LINES_PER_AXIS {
			step_x = (count_x + MAX_GRID_LINES_PER_AXIS - 1) / MAX_GRID_LINES_PER_AXIS
		}
		step_z := 1
		if count_z > MAX_GRID_LINES_PER_AXIS {
			step_z = (count_z + MAX_GRID_LINES_PER_AXIS - 1) / MAX_GRID_LINES_PER_AXIS
		}

		x_step := cell * f32(step_x)
		z_step := cell * f32(step_z)
		a_base := f32(110 - li * 25)

		for x := min_x; x <= max_x; x += x_step {
			dist := math.abs(x - cam.x) / max(range_w, f32(1e-3))
			alpha := clamp(1.0 - dist, 0.0, 1.0) * a_base
			col := rl.Color{95, 105, 130, u8(alpha)}
			if math.abs(x - center[0]) < cell * 0.25 { col = axis_col }
			rl.DrawLine3D(
				rl.Vector3{x, 0, min_z},
				rl.Vector3{x, 0, max_z},
				col,
			)
		}
		for z := min_z; z <= max_z; z += z_step {
			dist := math.abs(z - cam.z) / max(range_w, f32(1e-3))
			alpha := clamp(1.0 - dist, 0.0, 1.0) * a_base
			col := rl.Color{95, 105, 130, u8(alpha)}
			if math.abs(z - center[2]) < cell * 0.25 { col = axis_col }
			rl.DrawLine3D(
				rl.Vector3{min_x, 0, z},
				rl.Vector3{max_x, 0, z},
				col,
			)
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
	sync_render_camera_from_editor(ev, &app.c_camera_params)

	rl.BeginTextureMode(ev.viewport_tex)
	rl.ClearBackground(rl.Color{20, 25, 35, 255})
	rl.BeginMode3D(ev.cam3d)
	draw_adaptive_infinite_grid(ev)
	draw_viewport_scene_objects(app, ev, ev.selection_kind, ev.selected_idx)
	for v, i in app.e_volumes {
		draw_volume_cube_wireframe(v, ev.selection_kind == .Volume && ev.selected_idx == i)
	}
	draw_viewport_camera_gizmos(app, ev)
	draw_world_axis(ev)
	rl.EndMode3D()
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

