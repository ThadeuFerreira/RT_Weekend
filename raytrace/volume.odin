package raytrace

import "core:math"
import "RT_Weekend:core"
import "RT_Weekend:util"

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

// boundary_hit_interval returns (t_entry, t_exit, ok) for a ray through a closed boundary (e.g. box).
// Used by ConstantMedium to get the segment inside the volume. ok false if ray misses the boundary.
@(private)
boundary_hit_interval :: proc(bvh: ^BVHNode, r: ray, ray_t: Interval) -> (t_entry, t_exit: f32, ok: bool) {
	closest1: f32 = math.inf_f32(1)
	rec1: hit_record
	// Boundary BVH contains only geometry (no volumes); nil rng is ok.
	if !bvh_hit(bvh, r, Interval{ray_t.min, math.inf_f32(1)}, &rec1, &closest1, nil) {
		return 0, 0, false
	}
	t_entry = rec1.t
	closest2: f32 = math.inf_f32(1)
	rec2: hit_record
	eps: f32 = 0.0001
	if bvh_hit(bvh, r, Interval{t_entry + eps, math.inf_f32(1)}, &rec2, &closest2, nil) {
		t_exit = rec2.t
	} else {
		// Ray origin is inside the volume: the single hit above is the exit face.
		// Re-interpret: t_exit = that exit hit, t_entry = start of the ray segment (clamped).
		// The caller guards t_entry >= t_exit so a zero-length segment is skipped safely.
		t_exit = t_entry
		t_entry = math.max(ray_t.min, 0.001)
	}
	return t_entry, t_exit, true
}

// constant_medium_hit implements probabilistic volumetric scattering: sample free path, scatter or pass through.
constant_medium_hit :: proc(vol: ConstantMedium, r: ray, ray_t: Interval, rec: ^hit_record, closest_so_far: ^f32, rng: ^util.ThreadRNG) -> bool {
	t_entry, t_exit, ok := boundary_hit_interval(vol.boundary_bvh, r, ray_t)
	if !ok do return false
	t_entry = math.max(t_entry, ray_t.min)
	t_exit  = math.min(t_exit, ray_t.max)
	if t_entry >= t_exit do return false
	segment_length := t_exit - t_entry
	// Exponential distribution: hit_distance = -ln(1 - U) / density; use 1-U to avoid ln(0).
	u := util.random_float(rng)
	if u >= 1.0 - 1e-7 do return false
	hit_distance := -math.ln(1.0 - u) / vol.density
	if hit_distance >= segment_length do return false
	t_scatter := t_entry + hit_distance
	if t_scatter >= closest_so_far^ do return false
	rec.p = ray_at(r, t_scatter)
	rec.t = t_scatter
	rec.material = isotropic{albedo = vol.albedo}
	rec.normal = vector_random_unit(rng)
	rec.front_face = true
	rec.u, rec.v = 0, 0
	closest_so_far^ = t_scatter
	return true
}
