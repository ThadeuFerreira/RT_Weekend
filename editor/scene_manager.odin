package editor

import rl "vendor:raylib"
import "RT_Weekend:core"

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
		switch s in obj {
		case core.SceneSphere:
			append(out, s)
		}
	}
}

AppendDefaultSphere :: proc(sm: ^SceneManager) {
	if sm == nil { return }
	s := core.SceneSphere{center = {0, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = {0.7, 0.7, 0.7}}
	append(&sm.objects, s)
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
		switch s in sm.objects[i] {
		case core.SceneSphere:
			center := rl.Vector3{s.center[0], s.center[1], s.center[2]}
			hit    := rl.GetRayCollisionSphere(ray, center, s.radius)
			if hit.hit && hit.distance > 0 && hit.distance < best_dist {
				best_dist = hit.distance
				best_idx  = i
			}
		}
	}
	return best_idx
}

GetSceneSphere :: proc(sm: ^SceneManager, idx: int) -> (s: core.SceneSphere, ok: bool) {
	if sm == nil { return core.SceneSphere{}, false }
	if idx < 0 || idx >= len(sm.objects) { return core.SceneSphere{}, false }
	switch s in sm.objects[idx] {
	case core.SceneSphere:
		return s, true
	case:
		return core.SceneSphere{}, false
	}
}

SetSceneSphere :: proc(sm: ^SceneManager, idx: int, s: core.SceneSphere) {
	if sm == nil { return }
	if idx < 0 || idx >= len(sm.objects) { return }
	sm.objects[idx] = s
}
