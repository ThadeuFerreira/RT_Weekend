package editor

import "core:math"
import rl "vendor:raylib"
import "RT_Weekend:core"

// EditorObject is a discriminated union; add variants here for new object types.
// Enables switch obj in SceneManager with exhaustiveness checking.
EditorObject :: union { core.SceneSphere }

// compute_viewport_ray casts a perspective ray through the given mouse position.
// Operates on explicit camera/texture params to avoid circular imports with ui package.
compute_viewport_ray :: proc(
	cam3d: rl.Camera3D,
	tex_w: i32,
	tex_h: i32,
	mouse: rl.Vector2,
	vp_rect: rl.Rectangle,
	require_inside: bool = true,
) -> (ray: rl.Ray, ok: bool) {
	if require_inside && !rl.CheckCollisionPointRec(mouse, vp_rect) {
		return {}, false
	}
	if tex_w <= 0 || tex_h <= 0 { return {}, false }

	u := clamp((mouse.x - vp_rect.x) / vp_rect.width,  f32(0), f32(1))
	v := clamp((mouse.y - vp_rect.y) / vp_rect.height, f32(0), f32(1))

	forward := rl.Vector3Normalize(cam3d.target - cam3d.position)
	right   := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, cam3d.up))
	up      := rl.Vector3CrossProduct(right, forward)

	aspect := f32(tex_w) / f32(tex_h)
	half_h := math.tan(cam3d.fovy * math.PI / 360.0)
	half_w := half_h * aspect

	ndc_x := (u * 2.0 - 1.0) * half_w
	ndc_y := (1.0 - v * 2.0) * half_h

	dir := rl.Vector3Normalize(forward + right * ndc_x + up * ndc_y)
	return rl.Ray{position = cam3d.position, direction = dir}, true
}

// ray_hit_plane_y intersects a ray with the horizontal plane y=plane_y.
ray_hit_plane_y :: proc(ray: rl.Ray, plane_y: f32) -> (xz: rl.Vector2, ok: bool) {
	dy := ray.direction.y
	if abs(dy) < 1e-4 { return {}, false }
	t := (plane_y - ray.position.y) / dy
	if t < 0 { return {}, false }
	return rl.Vector2{
		ray.position.x + t * ray.direction.x,
		ray.position.z + t * ray.direction.z,
	}, true
}

// vec3_from_core converts core [3]f32 to rl.Vector3 for drawing.
vec3_from_core :: proc(v: [3]f32) -> rl.Vector3 {
	return rl.Vector3{v[0], v[1], v[2]}
}

// get_camera_viewport_corners returns the four corners of the render camera's viewport
// rectangle at focus_dist in world space (ul, ur, lr, ll). Matches raytrace camera init_camera math.
get_camera_viewport_corners :: proc(cp: ^core.CameraParams, aspect_ratio: f32) -> (ul, ur, lr, ll: [3]f32) {
	center := cp.lookfrom
	w_dir := cp.lookfrom - cp.lookat
	len_w := math.sqrt(w_dir[0]*w_dir[0] + w_dir[1]*w_dir[1] + w_dir[2]*w_dir[2])
	if len_w < 1e-6 {
		return ul, ur, lr, ll
	}
	w := [3]f32{w_dir[0] / len_w, w_dir[1] / len_w, w_dir[2] / len_w}
	// u = unit(cross(vup, w))
	cross_vw := [3]f32{
		cp.vup[1]*w[2] - cp.vup[2]*w[1],
		cp.vup[2]*w[0] - cp.vup[0]*w[2],
		cp.vup[0]*w[1] - cp.vup[1]*w[0],
	}
	len_u := math.sqrt(cross_vw[0]*cross_vw[0] + cross_vw[1]*cross_vw[1] + cross_vw[2]*cross_vw[2])
	if len_u < 1e-6 {
		return ul, ur, lr, ll
	}
	u := [3]f32{cross_vw[0] / len_u, cross_vw[1] / len_u, cross_vw[2] / len_u}
	// v = cross(w, u)
	v := [3]f32{
		w[1]*u[2] - w[2]*u[1],
		w[2]*u[0] - w[0]*u[2],
		w[0]*u[1] - w[1]*u[0],
	}
	theta := cp.vfov * (math.PI / 180.0)
	h := math.tan(theta * 0.5)
	viewport_height := 2.0 * h * cp.focus_dist
	viewport_width := viewport_height * aspect_ratio
	viewport_u := [3]f32{u[0] * viewport_width, u[1] * viewport_width, u[2] * viewport_width}
	viewport_v := [3]f32{-v[0] * viewport_height, -v[1] * viewport_height, -v[2] * viewport_height}
	// viewport_upper_left = center - focus_dist*w - 0.5*(viewport_u + viewport_v)
	half_u := [3]f32{viewport_u[0] * 0.5, viewport_u[1] * 0.5, viewport_u[2] * 0.5}
	half_v := [3]f32{viewport_v[0] * 0.5, viewport_v[1] * 0.5, viewport_v[2] * 0.5}
	ul = [3]f32{
		center[0] - cp.focus_dist*w[0] - half_u[0] - half_v[0],
		center[1] - cp.focus_dist*w[1] - half_u[1] - half_v[1],
		center[2] - cp.focus_dist*w[2] - half_u[2] - half_v[2],
	}
	ur = [3]f32{ul[0] + viewport_u[0], ul[1] + viewport_u[1], ul[2] + viewport_u[2]}
	lr = [3]f32{ur[0] + viewport_v[0], ur[1] + viewport_v[1], ur[2] + viewport_v[2]}
	ll = [3]f32{ul[0] + viewport_v[0], ul[1] + viewport_v[1], ul[2] + viewport_v[2]}
	return ul, ur, lr, ll
}

CAMERA_GIZMO_RADIUS :: f32(0.35)
pick_camera :: proc(ray: rl.Ray, lookfrom: [3]f32) -> bool {
	center := rl.Vector3{lookfrom[0], lookfrom[1], lookfrom[2]}
	hit    := rl.GetRayCollisionSphere(ray, center, CAMERA_GIZMO_RADIUS)
	return hit.hit && hit.distance > 0
}
