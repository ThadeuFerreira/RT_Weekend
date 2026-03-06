package raytrace

import "RT_Weekend:core"

// convert_world_to_edit_spheres converts rt.Object spheres to core.SceneSphere for the edit view.
// Skips the ground plane (center.y < -100) and Cube objects.
// Caller must delete the returned array.
convert_world_to_edit_spheres :: proc(world: [dynamic]Object) -> [dynamic]core.SceneSphere {
	result := make([dynamic]core.SceneSphere)
	for obj in world {
		s, ok := obj.(Sphere)
		if !ok { continue }
		if s.center[1] < -100 { continue } // skip ground plane
		ss := core.SceneSphere{center = s.center, center1 = s.center1, radius = s.radius, is_moving = s.is_moving}
		switch m in s.material {
		case lambertian:
			ss.material_kind = .Lambertian
			ss.albedo = texture_value(m.albedo, 0, 0, {0, 0, 0})
		case metallic:
			ss.material_kind = .Metallic
			ss.albedo = m.albedo
			ss.fuzz = m.fuzz
		case dielectric:
			ss.material_kind = .Dielectric
			ss.ref_idx = m.ref_idx
		}
		append(&result, ss)
	}
	return result
}

// build_world_from_scene converts shared scene spheres to raytrace Objects.
// Prepends a ground plane. When ground_texture is nil, uses grey ConstantTexture; otherwise uses the given texture.
// Caller owns and must delete the returned dynamic array.
build_world_from_scene :: proc(scene_objects: []core.SceneSphere, ground_texture: ^Texture = nil) -> [dynamic]Object {
	world := make([dynamic]Object)

	ground_tex: Texture = ConstantTexture{color = {0.5, 0.5, 0.5}}
	if ground_texture != nil {
		ground_tex = ground_texture^
	}
	append(&world, Object(Sphere{
		center   = {0, -1000, 0},
		radius   = 1000,
		material = lambertian{albedo = ground_tex},
	}))

	for s in scene_objects {
		mat: material
		switch s.material_kind {
		case .Lambertian:
			mat = material(lambertian{albedo = ConstantTexture{color = s.albedo}})
		case .Metallic:
			fuzz := s.fuzz
			if fuzz <= 0 { fuzz = 0.1 }
			mat = material(metallic{albedo = s.albedo, fuzz = fuzz})
		case .Dielectric:
			ref_idx := s.ref_idx
			if ref_idx <= 0 { ref_idx = 1.5 }
			mat = material(dielectric{ref_idx = ref_idx})
		case:
			mat = material(lambertian{albedo = ConstantTexture{color = s.albedo}})
		}
		append(&world, Object(Sphere{
			center    = s.center,
			center1   = s.center1,
			radius    = s.radius,
			material  = mat,
			is_moving = s.is_moving,
		}))
	}

	return world
}
