package editor

import "core:math"
import rl "vendor:raylib"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"

// Selection kind when picking in the viewport: none, sphere, quad, volume, or camera (used by Viewport).
// When Volume: selected_idx is the index into app.e_volumes.
EditViewSelectionKind :: enum {
	None,
	Sphere,
	Quad,
	Volume,
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

scene_manager_bounds :: proc(sm: ^SceneManager) -> (bmin, bmax: [3]f32, ok: bool) {
	if sm == nil || len(sm.objects) == 0 {
		return {}, {}, false
	}
	bmin = {1e30, 1e30, 1e30}
	bmax = {-1e30, -1e30, -1e30}
	found := false
	for obj in sm.objects {
		#partial switch o in obj {
		case core.SceneSphere:
			if core.scene_sphere_is_ground(o) {
				continue
			}
			r := o.radius
			p0 := o.center - [3]f32{r, r, r}
			p1 := o.center + [3]f32{r, r, r}
			if o.is_moving {
				p0m := o.center1 - [3]f32{r, r, r}
				p1m := o.center1 + [3]f32{r, r, r}
				if p0m[0] < p0[0] { p0[0] = p0m[0] }
				if p0m[1] < p0[1] { p0[1] = p0m[1] }
				if p0m[2] < p0[2] { p0[2] = p0m[2] }
				if p1m[0] > p1[0] { p1[0] = p1m[0] }
				if p1m[1] > p1[1] { p1[1] = p1m[1] }
				if p1m[2] > p1[2] { p1[2] = p1m[2] }
			}
			if p0[0] < bmin[0] { bmin[0] = p0[0] }
			if p0[1] < bmin[1] { bmin[1] = p0[1] }
			if p0[2] < bmin[2] { bmin[2] = p0[2] }
			if p1[0] > bmax[0] { bmax[0] = p1[0] }
			if p1[1] > bmax[1] { bmax[1] = p1[1] }
			if p1[2] > bmax[2] { bmax[2] = p1[2] }
			found = true
		case rt.Quad:
			bb := rt.quad_bounding_box(o)
			if bb.x.min < bmin[0] { bmin[0] = bb.x.min }
			if bb.y.min < bmin[1] { bmin[1] = bb.y.min }
			if bb.z.min < bmin[2] { bmin[2] = bb.z.min }
			if bb.x.max > bmax[0] { bmax[0] = bb.x.max }
			if bb.y.max > bmax[1] { bmax[1] = bb.y.max }
			if bb.z.max > bmax[2] { bmax[2] = bb.z.max }
			found = true
		}
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

// frame_editor_camera_horizontal fits the whole scene in view and looks at center.
// Camera is aligned to the horizontal plane (pitch=0, world-up).
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

	// Horizontal framing from a fixed-height camera:
	// fit XY extents by FOV, then add Z half-extent so near/far spread remains visible.
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

	// Keep free-fly state in sync for callers that toggle mode later.
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

// default_volume_from_scene_scale returns box_min, box_max, and translate for a new volume
// so the volume is a 1:1 cube scaled to the scene (not too small in large scenes, not too big in small ones).
// When the scene has no bounds, returns a unit cube at origin.
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
	if obj, got := GetSceneObject(sm, idx); got {
		#partial switch s in obj {
		case core.SceneSphere:
			return s, true
		}
	}
	return core.SceneSphere{}, false
}

GetSceneObject :: proc(sm: ^SceneManager, idx: int) -> (obj: EditorObject, ok: bool) {
	if sm == nil { return EditorObject{}, false }
	if idx < 0 || idx >= len(sm.objects) { return EditorObject{}, false }
	return sm.objects[idx], true
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
	if obj, got := GetSceneObject(sm, idx); got {
		#partial switch qu in obj {
		case rt.Quad:
			return qu, true
		}
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
// world is a slice (e.g. r_world[:] or world[:]). Skips the ground plane (see core.is_ground_heuristic).
LoadFromWorld :: proc(sm: ^SceneManager, world: []rt.Object) {
	if sm == nil { return }
	clear(&sm.objects)
	for obj in world {
		switch o in obj {
		case rt.Sphere:
			if core.is_ground_heuristic(o.center[1], o.radius) {
				continue
			}
			append(&sm.objects, rt.sphere_to_scene_sphere(o))
		case rt.Quad:
			append(&sm.objects, o)
		case rt.ConstantMedium:
			// Volumes are not editable in the scene manager; they remain in r_world for rendering.
			continue
		}
	}
}
