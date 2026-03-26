package raytrace

import "RT_Weekend:util"

hit_record :: struct {
    p : [3]f32,
    normal : [3]f32,
    material : material,
    t : f32,
    front_face : bool,
    u: f32,
    v: f32,
}

// ConstantMedium wraps a boundary (BVH of geometry) and implements probabilistic volumetric scattering.
// Uses isotropic phase function; density controls mean free path.
ConstantMedium :: struct {
	boundary_bvh: ^BVHNode,
	density:      f32,
	albedo:       [3]f32,
}

Object :: union {
	Sphere,
	Quad,
	ConstantMedium,
}

object_bounding_box :: proc(obj: Object) -> AABB {
	switch o in obj {
	case Sphere:
		return sphere_bounding_box(o)
	case Quad:
		return quad_bounding_box(o)
	case ConstantMedium:
		if o.boundary_bvh != nil {
			return o.boundary_bvh.bbox
		}
		return AABB{x = Interval{0, 0}, y = Interval{0, 0}, z = Interval{0, 0}}
	}
	return AABB{x = Interval{0, 0}, y = Interval{0, 0}, z = Interval{0, 0}}
}

set_face_normal :: proc(rec : ^hit_record, r : ray, outward_normal : [3]f32) {
	rec.front_face = dot(r.dir, outward_normal) < 0
	if rec.front_face {
		rec.normal = outward_normal
	} else {
		rec.normal = -outward_normal
	}
}

hit :: proc(r: ray, ray_t: Interval, rec: ^hit_record, object: Object, closest_so_far: ^f32, rng: ^util.ThreadRNG = nil) -> bool {
	temp_rec := hit_record{}
	switch s in object {
	case Sphere:
		if hit_sphere(s, r, Interval{ray_t.min, closest_so_far^}, &temp_rec) {
			rec^ = temp_rec
			closest_so_far^ = temp_rec.t
			return true
		}
	case Quad:
		if hit_quad(s, r, Interval{ray_t.min, closest_so_far^}, &temp_rec) {
			rec^ = temp_rec
			closest_so_far^ = temp_rec.t
			return true
		}
	case ConstantMedium:
		if rng == nil do return false
		return constant_medium_hit(s, r, ray_t, rec, closest_so_far, rng)
	}
	return false
}
