package main

import "core:fmt"
import "core:math"
import "core:os"
import rt "RT_Weekend:raytrace"

EPS :: f32(1e-4)

expect :: proc(cond: bool, msg: string) {
	if !cond {
		fmt.fprintf(os.stderr, "FAIL: %s\n", msg)
		os.exit(1)
	}
}

nearly_eq3 :: proc(a, b: [3]f32) -> bool {
	return math.abs(a[0]-b[0]) <= EPS &&
		math.abs(a[1]-b[1]) <= EPS &&
		math.abs(a[2]-b[2]) <= EPS
}

test_aabb_hit_cases :: proc() {
	box := rt.AABB{
		x = rt.Interval{0, 1},
		y = rt.Interval{0, 1},
		z = rt.Interval{0, 1},
	}
	ray_t := rt.Interval{0.001, math.inf_f32(1.0)}

	// Straight hit through the center.
	{
		r := rt.ray{origin = {0.5, 0.5, -1}, dir = {0, 0, 1}}
		expect(rt.aabb_hit(box, r, ray_t), "center hit should intersect")
	}

	// Miss: parallel to Z slab but outside X range.
	{
		r := rt.ray{origin = {1.2, 0.5, -1}, dir = {0, 0, 1}}
		expect(!rt.aabb_hit(box, r, ray_t), "parallel outside slab should miss")
	}

	// Grazing an edge should still count as hit (robust slab handling).
	{
		r := rt.ray{origin = {0, 0.5, -1}, dir = {0, 0, 1}}
		expect(rt.aabb_hit(box, r, ray_t), "edge-grazing ray should intersect")
	}

	// Through a corner.
	{
		r := rt.ray{origin = {-1, -1, -1}, dir = {1, 1, 1}}
		expect(rt.aabb_hit(box, r, ray_t), "corner ray should intersect")
	}
}

test_transform_round_trip :: proc() {
	tr := rt.make_object_transform_trs(
		[3]f32{2.0, -1.0, 0.5},
		[3]f32{0.2, 0.8, -0.15},
		[3]f32{1.5, 0.5, 2.0},
	)

	p_obj := [3]f32{0.3, 0.7, -0.2}
	p_world := rt.mat4_transform_point(tr.object_to_world, p_obj)
	p_obj_back := rt.mat4_transform_point(tr.world_to_object, p_world)
	expect(nearly_eq3(p_obj, p_obj_back), "TRS inverse should recover original point")

	v_obj := [3]f32{1, 0, 0}
	v_world := rt.mat4_transform_vector(tr.object_to_world, v_obj)
	expect(rt.vector_length(v_world) > 0, "transformed vector must stay non-zero")
}

main :: proc() {
	test_aabb_hit_cases()
	test_transform_round_trip()
	fmt.println("PASS: aabb + transform tests")
}
