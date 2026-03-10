package editor

import rl "vendor:raylib"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"

// Selection kind when picking in the viewport: none, sphere, quad, or camera (used by Edit View).
EditViewSelectionKind :: enum {
	None,
	Sphere,
	Quad,
	Camera,
}

// SceneManager is a thin wrapper around the editor-side object list.
// Stores core.SceneSphere directly in EditorObject; no conversion on Get/Set.
// Single place to add adapters later (EditorObject polymorphism).
SceneManager :: struct {
	objects: [dynamic]EditorObject,
}

new_scene_manager :: proc() -> ^SceneManager {
	sm := new(SceneManager)
	sm.objects = make([dynamic]EditorObject)
	return sm
}

// free_scene_manager deletes Objects and frees the SceneManager. Call on shutdown.
free_scene_manager :: proc(sm: ^SceneManager) {
	if sm == nil { return }
	delete(sm.objects)
	free(sm)
}

// Load from canonical scene representation
LoadFromSceneSpheres :: proc(sm: ^SceneManager, src: []core.SceneSphere) {
	if sm == nil { return }
	clear(&sm.objects)
	for i in 0..<len(src) {
		append(&sm.objects, src[i])
	}
}

// ExportToSceneSpheres clears out and fills it with current sphere data. Caller owns out; no per-call allocation.
ExportToSceneSpheres :: proc(sm: ^SceneManager, out: ^[dynamic]core.SceneSphere) {
	if sm == nil { clear(out); return }
	clear(out)
	for obj in sm.objects {
		#partial switch s in obj {
		case core.SceneSphere:
			append(out, s)
		case rt.Quad:
			// skip quads; they are appended separately via AppendQuadsToWorld
		}
	}
}

// AppendQuadsToWorld appends all Quad objects from the scene manager to world (e.g. after ground + spheres).
AppendQuadsToWorld :: proc(sm: ^SceneManager, world: ^[dynamic]rt.Object) {
	if sm == nil || world == nil { return }
	for obj in sm.objects {
		#partial switch q in obj {
		case rt.Quad:
			append(world, rt.Object(q))
		case core.SceneSphere:
			// skip
		}
	}
}

AppendDefaultSphere :: proc(sm: ^SceneManager) {
	if sm == nil { return }
	sphere := core.SceneSphere{
		center = {0, 0.5, 0},
		center1 = {0, 0.5, 0},
		radius = 0.5,
		material_kind = .Lambertian,
		albedo = core.ConstantTexture{color={0.7, 0.7, 0.7}},
		is_moving = false,
	}
	append(&sm.objects, sphere)
}

// AppendDefaultQuad appends a default 1×1 quad in the XY plane at z=0 (grey Lambertian).
AppendDefaultQuad :: proc(sm: ^SceneManager) {
	if sm == nil { return }
	default_mat := rt.material(rt.lambertian{albedo = rt.ConstantTexture{color = {0.7, 0.7, 0.7}}})
	q := rt.make_quad([3]f32{0, 0, 0}, [3]f32{1, 0, 0}, [3]f32{0, 1, 0}, default_mat)
	append(&sm.objects, q)
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

PickSphereInManager :: proc(sm: ^SceneManager, ray: rl.Ray) -> int {
	if sm == nil { return -1 }
	best_idx  := -1
	best_dist := f32(1e30)
	for i in 0..<len(sm.objects) {
		#partial switch s in sm.objects[i] {
		case core.SceneSphere:
			center := rl.Vector3{s.center[0], s.center[1], s.center[2]}
			hit    := rl.GetRayCollisionSphere(ray, center, s.radius)
			if hit.hit && hit.distance > 0 && hit.distance < best_dist {
				best_dist = hit.distance
				best_idx  = i
			}
		case rt.Quad:
			// Quad picking via PickClosestObject
		}
	}
	return best_idx
}

// PickClosestObject returns the closest hit object (sphere or quad) and its hit distance t.
// Returns (.None, -1, 1e30) when nothing is hit.
// Ray direction is normalized so t is comparable between sphere and quad hits.
PickClosestObject :: proc(sm: ^SceneManager, ray: rl.Ray) -> (kind: EditViewSelectionKind, idx: int, t: f32) {
	kind = .None
	idx  = -1
	t    = 1e30
	if sm == nil { return }
	// Normalize direction so t is in world units for both sphere and quad
	dir := rl.Vector3Normalize(ray.direction)
	r_origin := [3]f32{ray.position.x, ray.position.y, ray.position.z}
	r_dir    := [3]f32{dir.x, dir.y, dir.z}
	ray_t    := rt.Interval{1e-5, 1e30} // small min to avoid rejecting close hits
	norm_ray := rl.Ray{position = ray.position, direction = dir}
	for i in 0..<len(sm.objects) {
		#partial switch obj in sm.objects[i] {
		case core.SceneSphere:
			center := rl.Vector3{obj.center[0], obj.center[1], obj.center[2]}
			hit    := rl.GetRayCollisionSphere(norm_ray, center, obj.radius)
			if hit.hit && hit.distance > 0 && f32(hit.distance) < t {
				t    = f32(hit.distance)
				kind = .Sphere
				idx  = i
			}
		case rt.Quad:
			r := rt.ray{origin = r_origin, dir = r_dir, time = 0}
			rec: rt.hit_record
			if rt.hit_quad(obj, r, ray_t, &rec) && rec.t < t {
				t    = rec.t
				kind = .Quad
				idx  = i
			}
		}
	}
	return
}

GetSceneSphere :: proc(sm: ^SceneManager, idx: int) -> (s: core.SceneSphere, ok: bool) {
	if sm == nil { return core.SceneSphere{}, false }
	if idx < 0 || idx >= len(sm.objects) { return core.SceneSphere{}, false }
	switch s in sm.objects[idx] {
	case core.SceneSphere:
		return s, true
	case rt.Quad:
		return core.SceneSphere{}, false
	}
	return core.SceneSphere{}, false
}

SetSceneSphere :: proc(sm: ^SceneManager, idx: int, s: core.SceneSphere) {
	if sm == nil { return }
	if idx < 0 || idx >= len(sm.objects) { return }
	sm.objects[idx] = s
}

SetSceneQuad :: proc(sm: ^SceneManager, idx: int, q: rt.Quad) {
	if sm == nil { return }
	if idx < 0 || idx >= len(sm.objects) { return }
	quad := q
	rt.quad_refresh_cached(&quad)
	sm.objects[idx] = quad
}

// InsertSphereAt inserts a sphere at the given index, shifting later elements right.
InsertSphereAt :: proc(sm: ^SceneManager, idx: int, s: core.SceneSphere) {
	if sm == nil { return }
	if idx < 0 || idx > len(sm.objects) { return }
	obj: EditorObject = s
	inject_at(&sm.objects, idx, obj)
}

GetSceneQuad :: proc(sm: ^SceneManager, idx: int) -> (q: rt.Quad, ok: bool) {
	if sm == nil { return rt.Quad{}, false }
	if idx < 0 || idx >= len(sm.objects) { return rt.Quad{}, false }
	switch qu in sm.objects[idx] {
	case rt.Quad:
		return qu, true
	case core.SceneSphere:
		return rt.Quad{}, false
	}
	return rt.Quad{}, false
}

// InsertQuadAt inserts a quad at the given index (for undo/redo).
InsertQuadAt :: proc(sm: ^SceneManager, idx: int, q: rt.Quad) {
	if sm == nil { return }
	if idx < 0 || idx > len(sm.objects) { return }
	quad := q
	rt.quad_refresh_cached(&quad)
	obj: EditorObject = quad
	inject_at(&sm.objects, idx, obj)
}

// LoadFromWorld clears the scene manager and fills it from a raytrace world (spheres + quads).
// Preserves object order so selected_idx and saved selections remain correct for mixed scenes.
// world is a slice (e.g. r_world[:] or world[:]). Skips the ground plane (sphere with center.y < -100).
LoadFromWorld :: proc(sm: ^SceneManager, world: []rt.Object) {
	if sm == nil { return }
	clear(&sm.objects)
	for obj in world {
		switch o in obj {
		case rt.Sphere:
			if o.center[1] < -100 { continue } // skip ground plane
			append(&sm.objects, rt.sphere_to_scene_sphere(o))
		case rt.Quad:
			append(&sm.objects, o)
		}
	}
}
