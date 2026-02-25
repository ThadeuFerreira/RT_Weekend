package editor

import rl "vendor:raylib"
import "RT_Weekend:scene"

// SceneManager is a thin wrapper around the editor-side object list.
// Initially stores the same SceneSphere array as the existing editor code, but
// provides a single place to add adapters later (EditorObject polymorphism).
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
	// replace contents
	delete(sm.Objects)
	for i in 0..<len(src) {
		// create a SphereObject and append as EditorObject
		sobj := FromSceneSphereValue(src[i])
		append(&sm.Objects, EditorObject{kind = .Sphere, sphere = sobj})
	}
}

ExportToSceneSpheres :: proc(sm: ^SceneManager) -> [dynamic]scene.SceneSphere {
	if sm == nil { return make([dynamic]scene.SceneSphere) }
	out := make([dynamic]scene.SceneSphere)
	for i in 0..<len(sm.Objects) {
		obj := sm.Objects[i]
		switch obj.kind {
		case .Sphere:
			append(&out, ToSceneSphereValue(obj.sphere))
		}
	}
	return out
}

AppendDefaultSphere :: proc(sm: ^SceneManager) {
	if sm == nil { return }
	s := scene.SceneSphere{center = {0, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = {0.7, 0.7, 0.7}}
	append(&sm.Objects, EditorObject{kind = .Sphere, sphere = FromSceneSphereValue(s)})
}

OrderedRemove :: proc(sm: ^SceneManager, idx: int) {
	if sm == nil { return }
	if idx < 0 || idx >= len(sm.Objects) { return }
	ordered_remove_local(&sm.Objects, idx)
}

// local helper since we can't mutate by name easily from other packages
ordered_remove_local :: proc(arr: ^[dynamic]EditorObject, idx: int) {
	if idx < 0 || idx >= len(arr^) { return }
	tmp := arr^
	new_arr := make([dynamic]EditorObject)
	for i := 0; i < idx; i += 1 {
		append(&new_arr, tmp[i])
	}
	for i := idx + 1; i < len(tmp); i += 1 {
		append(&new_arr, tmp[i])
	}
	arr^ = new_arr
}

PickSphereInManager :: proc(sm: ^SceneManager, ray: rl.Ray) -> int {
	if sm == nil { return -1 }
	best_idx  := -1
	best_dist := f32(1e30)
	for i in 0..<len(sm.Objects) {
		obj := sm.Objects[i]
		if obj.kind != .Sphere { continue }
		s := ToSceneSphereValue(obj.sphere)
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
	return true, ToSceneSphereValue(obj.sphere)
}

SetSceneSphere :: proc(sm: ^SceneManager, idx: int, s: scene.SceneSphere) {
	if sm == nil { return }
	if idx < 0 || idx >= len(sm.Objects) { return }
	obj := &sm.Objects[idx]
	if obj.kind != .Sphere { return }
	obj.sphere = FromSceneSphereValue(s)
}

