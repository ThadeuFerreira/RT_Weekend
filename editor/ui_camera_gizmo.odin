package editor

import rl "vendor:raylib"

// draw_camera_gizmo draws the render camera body (pyramid + base) and wireframe.
// cam_pos, cam_at, vup define the camera frame; selected toggles highlight color.
draw_camera_gizmo :: proc(cam_pos, cam_at, vup: rl.Vector3, selected: bool) {
	fwd     := rl.Vector3Normalize(cam_at - cam_pos)
	right   := rl.Vector3Normalize(rl.Vector3CrossProduct(fwd, vup))
	up      := rl.Vector3CrossProduct(right, fwd)
	hw, hh, apex_len := f32(0.14), f32(0.10), f32(0.35)
	c0 := cam_pos - right*hw - up*hh
	c1 := cam_pos + right*hw - up*hh
	c2 := cam_pos + right*hw + up*hh
	c3 := cam_pos - right*hw + up*hh
	apex := cam_pos + fwd * apex_len
	cam_col := selected ? rl.YELLOW : rl.Color{255, 105, 180, 255}
	wire_col := selected ? rl.Color{220, 200, 0, 200} : rl.Color{180, 80, 120, 200}
	rl.DrawTriangle3D(c0, c1, apex, cam_col)
	rl.DrawTriangle3D(c1, c2, apex, cam_col)
	rl.DrawTriangle3D(c2, c3, apex, cam_col)
	rl.DrawTriangle3D(c3, c0, apex, cam_col)
	rl.DrawTriangle3D(c0, c1, c2, cam_col)
	rl.DrawTriangle3D(c0, c2, c3, cam_col)
	rl.DrawLine3D(c0, c1, wire_col)
	rl.DrawLine3D(c1, c2, wire_col)
	rl.DrawLine3D(c2, c3, wire_col)
	rl.DrawLine3D(c3, c0, wire_col)
	rl.DrawLine3D(c0, apex, wire_col)
	rl.DrawLine3D(c1, apex, wire_col)
	rl.DrawLine3D(c2, apex, wire_col)
	rl.DrawLine3D(c3, apex, wire_col)
}

// draw_frustum_wireframe draws the view frustum as 8 lines: apex to each corner, plus the viewport rectangle.
draw_frustum_wireframe :: proc(apex, ul, ur, lr, ll: rl.Vector3, line_color: rl.Color) {
	rl.DrawLine3D(apex, ul, line_color)
	rl.DrawLine3D(apex, ur, line_color)
	rl.DrawLine3D(apex, lr, line_color)
	rl.DrawLine3D(apex, ll, line_color)
	rl.DrawLine3D(ul, ur, line_color)
	rl.DrawLine3D(ur, lr, line_color)
	rl.DrawLine3D(lr, ll, line_color)
	rl.DrawLine3D(ll, ul, line_color)
}

// draw_focal_distance_indicator draws a ray from the camera to the focus point and a small sphere at the focus point.
draw_focal_distance_indicator :: proc(cam_pos, focus_point: rl.Vector3, ray_color, ball_color: rl.Color) {
	rl.DrawLine3D(cam_pos, focus_point, ray_color)
	rl.DrawSphere(focus_point, 0.06, ball_color)
}

CAM_RING_R :: f32(1.2)

// draw_camera_rotation_rings draws three rings around the camera gizmo when it is selected,
// one per world axis (Godot/Unreal style).
//   axis 0 → X ring (red)   in the YZ plane  (rotationAxis={0,1,0}, angle=90)
//   axis 1 → Y ring (green) in the XZ plane  (rotationAxis={1,0,0}, angle=90)
//   axis 2 → Z ring (blue)  in the XY plane  (rotationAxis={1,0,0}, angle=0)
// active_axis: the ring currently being dragged (-1 = none).
draw_camera_rotation_rings :: proc(cam_pos: rl.Vector3, active_axis: int) {
	x_col := active_axis == 0 ? rl.Color{255,  60,  60, 255} : rl.Color{200,  60,  60, 180}
	y_col := active_axis == 1 ? rl.Color{ 60, 255,  60, 255} : rl.Color{ 60, 200,  60, 180}
	z_col := active_axis == 2 ? rl.Color{ 60, 120, 255, 255} : rl.Color{ 60, 120, 220, 180}
	rl.DrawCircle3D(cam_pos, CAM_RING_R, {0, 1, 0}, 90, x_col) // YZ plane — X axis
	rl.DrawCircle3D(cam_pos, CAM_RING_R, {1, 0, 0}, 90, y_col) // XZ plane — Y axis
	rl.DrawCircle3D(cam_pos, CAM_RING_R, {1, 0, 0},  0, z_col) // XY plane — Z axis
}
