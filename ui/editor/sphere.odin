package editor

import rl "vendor:raylib"
import "RT_Weekend:scene"

// Value <-> Scene conversions and drawing/hit helpers for SphereObject.
FromSceneSphereValue :: proc(s: scene.SceneSphere) -> SphereObject {
	return SphereObject{
		center = s.center,
		radius = s.radius,
		material_kind = s.material_kind,
		albedo = s.albedo,
		fuzz = s.fuzz,
		ref_idx = s.ref_idx,
	}
}

ToSceneSphereValue :: proc(s: SphereObject) -> scene.SceneSphere {
	return scene.SceneSphere{
		center = s.center,
		radius = s.radius,
		material_kind = s.material_kind,
		albedo = s.albedo,
		fuzz = s.fuzz,
		ref_idx = s.ref_idx,
	}
}

// Draw the sphere into the raylib 3D viewport.
DrawSphereObject3D :: proc(s: ^SphereObject, selected: bool) {
	if s == nil { return }
	c := rl.Vector3{s.center[0], s.center[1], s.center[2]}
	col := rl.Color{u8(s.albedo[0]*255), u8(s.albedo[1]*255), u8(s.albedo[2]*255), 255}
	if selected {
		col = rl.YELLOW
	}
	rl.DrawSphere(c, s.radius, col)
	rl.DrawSphereWires(c, s.radius, 8, 8, rl.Color{30, 30, 30, 180})
}

// Hit test a sphere against a ray.
HitTestSphereObject :: proc(s: ^SphereObject, ray: rl.Ray) -> (hit: bool, distance: f32) {
	if s == nil { return false, 0 }
	center := rl.Vector3{s.center[0], s.center[1], s.center[2]}
	h := rl.GetRayCollisionSphere(ray, center, s.radius)
	return h.hit && h.distance > 0, h.distance
}

// Lightweight method-like procs to operate on pointer receivers.
ToSceneSphere :: proc(s: ^SphereObject) -> (ok: bool, out: scene.SceneSphere) {
	if s == nil { return false, scene.SceneSphere{} }
	return true, ToSceneSphereValue(s^)
}

FromSceneSphere :: proc(s: ^SphereObject, src: scene.SceneSphere) {
	if s == nil { return }
	s^ = FromSceneSphereValue(src)
}

