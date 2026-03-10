package editor

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

// draw_scene_objects_simple draws all scene objects as solid spheres or quads (no texture cache).
// Used by the preview panel and as fallback in the edit view. Call inside BeginMode3D.
draw_scene_objects_simple :: proc(
	sm: ^SceneManager,
	selection_kind: EditViewSelectionKind,
	selected_idx: int,
) {
	if sm == nil { return }
	for i in 0..<len(sm.objects) {
		selected := (selection_kind == .Sphere || selection_kind == .Quad) && selected_idx == i
		#partial switch o in sm.objects[i] {
		case core.SceneSphere:
			s := o
			disp_col := sphere_solid_color_from_albedo(s.albedo)
			draw_sphere_solid(s.center, s.radius, disp_col, selected)
		case rt.Quad:
			draw_quad_with_material_color(o, selected)
		}
	}
}
