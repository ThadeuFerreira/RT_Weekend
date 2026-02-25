package editor

import rl "vendor:raylib"
import "RT_Weekend:scene"

// SceneManager is a thin wrapper around the editor-side object list.
// Stores scene.SceneSphere directly in EditorObject; no conversion on Get/Set.
// Single place to add adapters later (EditorObject polymorphism).
SceneManager :: struct {
	Objects: [dynamic]EditorObject,
}

new_scene_manager :: proc() -> ^SceneManager {
	sm := new(SceneManager)
	sm.Objects = make([dynamic]EditorObject)
	return sm
}

// Load from canonical scene representation
LoadFromSceneSpheres :: proc(sm: ^SceneManager, src: [dynamic]scene.SceneSphere) {
	if sm == nil { return }
	delete(sm.Objects)
	for i in 0..<len(src) {
		append(&sm.Objects, EditorObject{kind = .Sphere, sphere = src[i]})
	}
}

// ExportToSceneSpheres clears out and fills it with current sphere data. Caller owns out; no per-call allocation.
ExportToSceneSpheres :: proc(sm: ^SceneManager, out: ^[dynamic]scene.SceneSphere) {
	if sm == nil { clear(out); return }
	clear(out)
	for i in 0..<len(sm.Objects) {
		obj := sm.Objects[i]
		switch obj.kind {
		case .Sphere:
			append(out, obj.sphere)
		}
	}
}

AppendDefaultSphere :: proc(sm: ^SceneManager) {
	if sm == nil { return }
	s := scene.SceneSphere{center = {0, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = {0.7, 0.7, 0.7}}
	append(&sm.Objects, EditorObject{kind = .Sphere, sphere = s})
}

OrderedRemove :: proc(sm: ^SceneManager, idx: int) {
	if sm == nil { return }
	if idx < 0 || idx >= len(sm.Objects) { return }
	ordered_remove(&sm.Objects, idx)
}

PickSphereInManager :: proc(sm: ^SceneManager, ray: rl.Ray) -> int {
	if sm == nil { return -1 }
	best_idx  := -1
	best_dist := f32(1e30)
	for i in 0..<len(sm.Objects) {
		obj := sm.Objects[i]
		if obj.kind != .Sphere { continue }
		s := obj.sphere
		center := rl.Vector3{s.center[0], s.center[1], s.center[2]}
		hit    := rl.GetRayCollisionSphere(ray, center, s.radius)
		if hit.hit && hit.distance > 0 && hit.distance < best_dist {
			best_dist = hit.distance
			best_idx  = i
		}
	}
	return best_idx
}

GetSceneSphere :: proc(sm: ^SceneManager, idx: int) -> (ok: bool, s: scene.SceneSphere) {
	if sm == nil { return false, scene.SceneSphere{} }
	if idx < 0 || idx >= len(sm.Objects) { return false, scene.SceneSphere{} }
	obj := sm.Objects[idx]
	if obj.kind != .Sphere { return false, scene.SceneSphere{} }
	return true, obj.sphere
}

SetSceneSphere :: proc(sm: ^SceneManager, idx: int, s: scene.SceneSphere) {
	if sm == nil { return }
	if idx < 0 || idx >= len(sm.Objects) { return }
	obj := &sm.Objects[idx]
	if obj.kind != .Sphere { return }
	obj.sphere = s
}

