package editor

import "core:math"
import rl "vendor:raylib"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"

// Selection kind when picking in the viewport: none, sphere, quad, volume, or camera.
// selected_idx is always an index into SceneManager.objects for geometry.
EditViewSelectionKind :: enum {
	None,
	Sphere,
	Quad,
	Volume,
	Camera,
}

// SceneManager holds a unified list of scene entities (spheres, quads, volumes).
SceneManager :: struct {
	objects: [dynamic]core.SceneEntity,
}

new_scene_manager :: proc() -> ^SceneManager {
	sm := new(SceneManager)
	sm.objects = make([dynamic]core.SceneEntity)
	return sm
}

free_scene_manager :: proc(sm: ^SceneManager) {
	if sm == nil { return }
	delete(sm.objects)
	free(sm)
}

LoadFromSceneSpheres :: proc(sm: ^SceneManager, src: []core.SceneSphere) {
	if sm == nil { return }
	clear(&sm.objects)
	for i in 0 ..< len(src) {
		append(&sm.objects, core.SceneEntity(src[i]))
	}
}

// ExportToSceneSpheres fills out with only sphere variants (for persistence paths that list spheres separately).
ExportToSceneSpheres :: proc(sm: ^SceneManager, out: ^[dynamic]core.SceneSphere) {
	if sm == nil { clear(out); return }
	clear(out)
	for e in sm.objects {
		if s, ok := e.(core.SceneSphere); ok {
			append(out, s)
		}
	}
}

// CollectVolumes appends all SceneVolume entities from the manager to out (caller clears out first if needed).
CollectVolumes :: proc(sm: ^SceneManager, out: ^[dynamic]core.SceneVolume) {
	if sm == nil { return }
	for e in sm.objects {
		if v, ok := e.(core.SceneVolume); ok {
			append(out, v)
		}
	}
}

AppendDefaultSphere :: proc(sm: ^SceneManager) {
	if sm == nil { return }
	sphere := core.SceneSphere{
		center        = {0, 0.5, 0},
		center1       = {0, 0.5, 0},
		radius        = 0.5,
		material_kind = .Lambertian,
		albedo        = core.ConstantTexture{color = {0.7, 0.7, 0.7}},
		is_moving     = false,
	}
	append(&sm.objects, core.SceneEntity(sphere))
}

AppendDefaultQuad :: proc(sm: ^SceneManager) {
	if sm == nil { return }
	q := core.SceneQuad{
		Q             = {0, 0, 0},
		u             = {1, 0, 0},
		v             = {0, 1, 0},
		material_kind = .Lambertian,
		albedo        = core.ConstantTexture{color = {0.7, 0.7, 0.7}},
		texture_kind  = .Constant,
		checker_scale = 1,
		fuzz          = 0.1,
		ref_idx       = 1.5,
	}
	append(&sm.objects, core.SceneEntity(q))
}

OrderedRemove :: proc(sm: ^SceneManager, idx: int) {
	if sm == nil { return }
	if idx < 0 || idx >= len(sm.objects) { return }
	ordered_remove(&sm.objects, idx)
}

SceneManagerLen :: proc(sm: ^SceneManager) -> int {
	if sm == nil { return 0 }
	return len(sm.objects)
}

GetSceneEntity :: proc(sm: ^SceneManager, idx: int) -> (e: core.SceneEntity, ok: bool) {
	if sm == nil { return {}, false }
	if idx < 0 || idx >= len(sm.objects) { return {}, false }
	return sm.objects[idx], true
}

SetSceneEntity :: proc(sm: ^SceneManager, idx: int, e: core.SceneEntity) {
	if sm == nil { return }
	if idx < 0 || idx >= len(sm.objects) { return }
	sm.objects[idx] = e
}

InsertEntityAt :: proc(sm: ^SceneManager, idx: int, e: core.SceneEntity) {
	if sm == nil { return }
	if idx < 0 || idx > len(sm.objects) { return }
	inject_at(&sm.objects, idx, e)
}

GetSceneSphere :: proc(sm: ^SceneManager, idx: int) -> (s: core.SceneSphere, ok: bool) {
	if e, got := GetSceneEntity(sm, idx); got {
		if v, ok2 := e.(core.SceneSphere); ok2 {
			return v, true
		}
	}
	return {}, false
}

SetSceneSphere :: proc(sm: ^SceneManager, idx: int, s: core.SceneSphere) {
	SetSceneEntity(sm, idx, core.SceneEntity(s))
}

GetSceneQuad :: proc(sm: ^SceneManager, idx: int) -> (q: core.SceneQuad, ok: bool) {
	if e, got := GetSceneEntity(sm, idx); got {
		if v, ok2 := e.(core.SceneQuad); ok2 {
			return v, true
		}
	}
	return {}, false
}

SetSceneQuad :: proc(sm: ^SceneManager, idx: int, q: core.SceneQuad) {
	SetSceneEntity(sm, idx, core.SceneEntity(q))
}

InsertSphereAt :: proc(sm: ^SceneManager, idx: int, s: core.SceneSphere) {
	InsertEntityAt(sm, idx, core.SceneEntity(s))
}

InsertQuadAt :: proc(sm: ^SceneManager, idx: int, q: core.SceneQuad) {
	InsertEntityAt(sm, idx, core.SceneEntity(q))
}

scene_manager_bounds :: proc(sm: ^SceneManager) -> (bmin, bmax: [3]f32, ok: bool) {
	if sm == nil || len(sm.objects) == 0 {
		return {}, {}, false
	}
	bmin = {1e30, 1e30, 1e30}
	bmax = {-1e30, -1e30, -1e30}
	found := false
	for e in sm.objects {
		ebmin, ebmax, eok := core.entity_bounds(e)
		if !eok { continue }
		found = true
		if ebmin[0] < bmin[0] { bmin[0] = ebmin[0] }
		if ebmin[1] < bmin[1] { bmin[1] = ebmin[1] }
		if ebmin[2] < bmin[2] { bmin[2] = ebmin[2] }
		if ebmax[0] > bmax[0] { bmax[0] = ebmax[0] }
		if ebmax[1] > bmax[1] { bmax[1] = ebmax[1] }
		if ebmax[2] > bmax[2] { bmax[2] = ebmax[2] }
	}
	if !found {
		return {}, {}, false
	}
	return bmin, bmax, true
}

scene_geometry_center :: proc(sm: ^SceneManager) -> (center: [3]f32, ok: bool) {
	bmin, bmax, ok_bounds := scene_manager_bounds(sm)
	if !ok_bounds {
		return {}, false
	}
	center = (bmin + bmax) * 0.5
	return center, true
}

frame_editor_camera_horizontal :: proc(ev: ^EditViewState, vertical_fov_deg: f32 = 45.0, fit_padding: f32 = 1.15) -> bool {
	if ev == nil {
		return false
	}
	bmin, bmax, ok := scene_manager_bounds(ev.scene_mgr)
	if !ok {
		return false
	}
	center := (bmin + bmax) * 0.5
	half := (bmax - bmin) * 0.5
	pad := fit_padding
	if pad < 1.0 { pad = 1.0 }

	half_xy := math.sqrt(half[0]*half[0] + half[1]*half[1]) * pad
	vfov_rad := max(vertical_fov_deg, f32(5.0)) * (math.PI / 180.0)
	dist := half_xy / max(math.tan(vfov_rad * 0.5), f32(1e-4))
	dist += half[2] * pad
	if dist < 2.0 { dist = 2.0 }

	ev.camera_mode = .Orbit
	ev.orbit_target = rl.Vector3{center[0], center[1], center[2]}
	ev.orbit_distance = dist
	ev.camera_pitch = 0
	ev.camera_yaw = 0

	lookfrom := center + [3]f32{0, 0, dist}
	ev.fly_lookfrom = lookfrom
	ev.fly_pitch = 0
	ev.fly_yaw = math.PI
	return true
}

scene_scale_recommendations :: proc(sm: ^SceneManager) -> (center: [3]f32, radius, move_speed: f32) {
	center = {0, 0, 0}
	radius = 8.0
	move_speed = 2.0
	bmin, bmax, ok := scene_manager_bounds(sm)
	if !ok {
		return
	}
	center = (bmin + bmax) * 0.5
	d := bmax - bmin
	diag := math.sqrt(d[0]*d[0] + d[1]*d[1] + d[2]*d[2])
	if diag < 1.0 { diag = 1.0 }
	radius = max(diag * 0.45, f32(3.0))
	move_speed = clamp(diag * 0.06, f32(0.2), f32(300.0))
	return
}

default_volume_from_scene_scale :: proc(sm: ^SceneManager) -> (box_min, box_max, translate: [3]f32) {
	box_min = {-0.5, -0.5, -0.5}
	box_max = {0.5, 0.5, 0.5}
	translate = {0, 0, 0}
	bmin, bmax, ok := scene_manager_bounds(sm)
	if !ok {
		return
	}
	center := (bmin + bmax) * 0.5
	d := bmax - bmin
	diag := math.sqrt(d[0]*d[0] + d[1]*d[1] + d[2]*d[2])
	if diag < 1.0 { diag = 1.0 }
	half := max(diag * 0.15, f32(0.5))
	box_min = {-half, -half, -half}
	box_max = {half, half, half}
	translate = center
	return
}

// PickClosestEntity returns the closest hit among all entities; idx indexes SceneManager.objects.
PickClosestEntity :: proc(sm: ^SceneManager, ray: rl.Ray) -> (kind: EditViewSelectionKind, idx: int, t: f32) {
	kind = .None
	idx = -1
	t = 1e30
	if sm == nil { return }
	dir := rl.Vector3Normalize(ray.direction)
	r_origin := [3]f32{ray.position.x, ray.position.y, ray.position.z}
	r_dir := [3]f32{dir.x, dir.y, dir.z}
	ray_t := rt.Interval{1e-5, 1e30}
	norm_ray := rl.Ray{position = ray.position, direction = dir}
	for i in 0 ..< len(sm.objects) {
		switch e in sm.objects[i] {
		case core.SceneSphere:
			center := rl.Vector3{e.center[0], e.center[1], e.center[2]}
			hit := rl.GetRayCollisionSphere(norm_ray, center, e.radius)
			if hit.hit && hit.distance > 0 && f32(hit.distance) < t {
				t = f32(hit.distance)
				kind = .Sphere
				idx = i
			}
		case core.SceneQuad:
			q := rt.scene_quad_to_rt_quad(e, nil)
			r := rt.ray{origin = r_origin, dir = r_dir, time = 0}
			rec: rt.hit_record
			if rt.hit_quad(q, r, ray_t, &rec) && rec.t < t {
				t = rec.t
				kind = .Quad
				idx = i
			}
		case core.SceneVolume:
			box := volume_world_aabb(e)
			hit := rl.GetRayCollisionBox(norm_ray, box)
			if hit.hit && hit.distance > 0 && f32(hit.distance) < t {
				t = f32(hit.distance)
				kind = .Volume
				idx = i
			}
		}
	}
	return
}

// LoadFromWorld fills the scene manager from render world objects (spheres and quads only; skips ground and volumes).
LoadFromWorld :: proc(sm: ^SceneManager, world: []rt.Object) {
	if sm == nil { return }
	clear(&sm.objects)
	for obj in world {
		switch o in obj {
		case rt.Sphere:
			if core.is_ground_heuristic(o.center[1], o.radius) {
				continue
			}
			append(&sm.objects, core.SceneEntity(rt.sphere_to_scene_sphere(o)))
		case rt.Quad:
			sq := rt.rt_quad_to_scene_quad(o)
			append(&sm.objects, core.SceneEntity(sq))
		case rt.ConstantMedium:
			continue
		}
	}
}

// AppendLoadedVolumes appends volume definitions after geometry (matches import order: objects then volumes).
AppendLoadedVolumes :: proc(sm: ^SceneManager, volumes: []core.SceneVolume) {
	if sm == nil { return }
	for v in volumes {
		append(&sm.objects, core.SceneEntity(v))
	}
}
