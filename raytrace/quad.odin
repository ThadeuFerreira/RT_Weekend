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

// append_box appends the six faces of an axis-aligned 3D box to quads.
// The box is defined by two opposite vertices a and b (min/max are computed component-wise).
// Same convention as RTIW: front (z=max), right (x=max), back (z=min), left (x=min), top (y=max), bottom (y=min).
append_box :: proc(quads: ^[dynamic]Quad, a, b: [3]f32, mat: material) {
	min_x := math.min(a[0], b[0])
	max_x := math.max(a[0], b[0])
	min_y := math.min(a[1], b[1])
	max_y := math.max(a[1], b[1])
	min_z := math.min(a[2], b[2])
	max_z := math.max(a[2], b[2])

	dx := [3]f32{max_x - min_x, 0, 0}
	dy := [3]f32{0, max_y - min_y, 0}
	dz := [3]f32{0, 0, max_z - min_z}

	// front (z = max)
	append(quads, make_quad([3]f32{min_x, min_y, max_z}, dx, dy, mat))
	// right (x = max)
	append(quads, make_quad([3]f32{max_x, min_y, max_z}, [3]f32{-dz[0], -dz[1], -dz[2]}, dy, mat))
	// back (z = min)
	append(quads, make_quad([3]f32{max_x, min_y, min_z}, [3]f32{-dx[0], -dx[1], -dx[2]}, dy, mat))
	// left (x = min)
	append(quads, make_quad([3]f32{min_x, min_y, min_z}, dz, dy, mat))
	// top (y = max)
	append(quads, make_quad([3]f32{min_x, max_y, max_z}, dx, [3]f32{-dz[0], -dz[1], -dz[2]}, mat))
	// bottom (y = min)
	append(quads, make_quad([3]f32{min_x, min_y, min_z}, dx, dz, mat))
}

// append_box_transformed appends an axis-aligned box then applies a transform matrix to each face.
append_box_transformed :: proc(quads: ^[dynamic]Quad, a, b: [3]f32, mat: material, object_to_world: Mat4) {
	local_quads := make([dynamic]Quad)
	defer delete(local_quads)

	append_box(&local_quads, a, b, mat)

	for q in local_quads {
		p0 := q.Q
		p1 := q.Q + q.u
		p2 := q.Q + q.v

		w0 := mat4_transform_point(object_to_world, p0)
		w1 := mat4_transform_point(object_to_world, p1)
		w2 := mat4_transform_point(object_to_world, p2)

		append(quads, make_quad(w0, w1-w0, w2-w0, q.material))
	}
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
