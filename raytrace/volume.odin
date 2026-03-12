package raytrace

import "core:math"
import "RT_Weekend:core"

// build_volume_from_scene_volume creates a ConstantMedium from a scene volume definition.
// Builds an axis-aligned box (6 quads) in local space, applies rotate_y then translate,
// builds a BVH over the box faces, and wraps it with the given density and albedo.
// Caller must free the returned object's boundary_bvh via free_volume_object or free_world_volumes.
build_volume_from_scene_volume :: proc(v: core.SceneVolume, allocator := context.allocator) -> Object {
	white := lambertian{albedo = ConstantTexture{color = [3]f32{0.73, 0.73, 0.73}}}
	quads := make([dynamic]Quad, allocator)
	defer delete(quads)
	rot_rad := degrees_to_radians(v.rotate_y_deg)
	tr := mat4_mul(mat4_translate(v.translate), mat4_rotate_y(rot_rad))
	append_box_transformed(&quads, v.box_min, v.box_max, white, tr)
	objs := make([dynamic]Object, 0, 6, allocator)
	defer delete(objs)
	for q in quads {
		append(&objs, Object(q))
	}
	bvh: ^BVHNode
	when USE_SAH_BVH {
		bvh = build_bvh_sah(objs[:], allocator)
	} else {
		bvh = build_bvh(objs[:], allocator)
	}
	density := v.density
	if density <= 0 { density = 0.01 }
	return Object(ConstantMedium{boundary_bvh = bvh, density = density, albedo = v.albedo})
}

// free_volume_object frees the boundary BVH of a ConstantMedium. Call when discarding a single volume.
free_volume_object :: proc(obj: Object, allocator := context.allocator) {
	if vol, ok := obj.(ConstantMedium); ok && vol.boundary_bvh != nil {
		free_bvh(vol.boundary_bvh, allocator)
	}
}

// free_world_volumes frees all ConstantMedium boundary BVHs in the world. Call before deleting the world slice.
free_world_volumes :: proc(world: [dynamic]Object, allocator := context.allocator) {
	for obj in world {
		free_volume_object(obj, allocator)
	}
}
