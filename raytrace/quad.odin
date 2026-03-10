package raytrace

import "core:math"

// Quad is a planar quadrilateral: corner Q and edge vectors u, v. Points on the quad are Q + α*u + β*v for α,β in [0,1].
// normal, D (plane n·x = D), and w = cross(u,v)/length_squared(cross(u,v)) for interior test (RTIW).
Quad :: struct {
	Q:        [3]f32,
	u:        [3]f32,
	v:        [3]f32,
	material: material,
	normal:   [3]f32,
	D:        f32,
	w:        [3]f32, // cross(u,v)/length_squared(cross(u,v)) so dot(w, cross(P-Q, v)) = α, dot(w, cross(u, P-Q)) = β
}

// quad_refresh_cached recomputes derived plane/cache fields from Q, u, v.
quad_refresh_cached :: proc(q: ^Quad) {
	n := cross(q.u, q.v)
	norm := unit_vector(n)
	len_sq := dot(n, n)
	w_vec: [3]f32
	if len_sq >= 1e-16 {
		w_vec = n / len_sq
	}
	q.normal = norm
	q.D = dot(norm, q.Q)
	q.w = w_vec
}

// make_quad builds a Quad from corner Q and edge vectors u, v; computes normal, D, and w (RTIW convention).
make_quad :: proc(Q, u, v: [3]f32, mat: material) -> Quad {
	q := Quad{
		Q        = Q,
		u        = u,
		v        = v,
		material = mat,
	}
	quad_refresh_cached(&q)
	return q
}

aabb_from_points :: proc(p, q: [3]f32) -> AABB {
	return AABB{
		x = Interval{math.min(p[0], q[0]), math.max(p[0], q[0])},
		y = Interval{math.min(p[1], q[1]), math.max(p[1], q[1])},
		z = Interval{math.min(p[2], q[2]), math.max(p[2], q[2])},
	}
}

// quad_geometry_equal returns true if two quads have the same shape (Q, u, v, normal, D).
// Used by BVH flatten when full Quad equality fails (e.g. material union comparison).
quad_geometry_equal :: proc(a, b: Quad) -> bool {
    return a.Q == b.Q && a.u == b.u && a.v == b.v && a.normal == b.normal && a.D == b.D
}

// quad_bounding_box returns the AABB of the four vertices and applies aabb_pad_to_minimums.
quad_bounding_box :: proc(q: Quad) -> AABB {
	bbox_diagonal1 := aabb_from_points(q.Q, q.Q + q.u + q.v)
	bbox_diagonal2 := aabb_from_points(q.Q + q.u, q.Q + q.v)
	box := aabb_union(bbox_diagonal1, bbox_diagonal2)
	aabb_pad_to_minimums(&box)
	return box
}

// Axis-aligned rectangle helpers: plane at constant k, extent [a0,a1] x [b0,b1] in the two varying axes.
// xy_rect: z = k (floor/ceiling); xz_rect: y = k (wall); yz_rect: x = k (wall).
xy_rect :: proc(x0, x1, y0, y1, k: f32, mat: material) -> Object {
	q := make_quad([3]f32{x0, y0, k}, [3]f32{x1 - x0, 0, 0}, [3]f32{0, y1 - y0, 0}, mat)
	return Object(q)
}
xz_rect :: proc(x0, x1, z0, z1, k: f32, mat: material) -> Object {
	q := make_quad([3]f32{x0, k, z0}, [3]f32{x1 - x0, 0, 0}, [3]f32{0, 0, z1 - z0}, mat)
	return Object(q)
}
yz_rect :: proc(y0, y1, z0, z1, k: f32, mat: material) -> Object {
	q := make_quad([3]f32{k, y0, z0}, [3]f32{0, y1 - y0, 0}, [3]f32{0, 0, z1 - z0}, mat)
	return Object(q)
}
