package editor

import "core:math"
import rl "vendor:raylib"
import "RT_Weekend:scene"

// TODO: define EditorObject interface here once we introduce polymorphic objects.

// BaseObject: common fields that object implementations can embed.
BaseObject :: struct {
	id:   int,
	name: cstring,
}

// Basic EditorObject kind + container for future polymorphism.
EditorObjectKind :: enum {
	Sphere,
}

EditorObject :: struct {
	kind: EditorObjectKind,
	// current concrete data (sphere). Future types will add more fields.
	sphere: SphereObject,
}

// SphereObject is declared here so all editor package files (in ui/editor/) can use it.
SphereObject :: struct {
	center: [3]f32,
	radius: f32,
	material_kind: scene.MaterialKind,
	albedo: [3]f32,
	fuzz: f32,
	ref_idx: f32,
}

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

CAMERA_GIZMO_RADIUS :: f32(0.35)
pick_camera :: proc(ray: rl.Ray, lookfrom: [3]f32) -> bool {
	center := rl.Vector3{lookfrom[0], lookfrom[1], lookfrom[2]}
	hit    := rl.GetRayCollisionSphere(ray, center, CAMERA_GIZMO_RADIUS)
	return hit.hit && hit.distance > 0
}

