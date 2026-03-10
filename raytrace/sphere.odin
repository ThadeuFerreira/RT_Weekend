package raytrace

import "core:math"

// Sphere is a sphere primitive with optional linear motion blur (center → center1 over t in [0,1]).
Sphere :: struct {
	center:    [3]f32,
	center1:   [3]f32, // end position (t=1); only used when is_moving
	radius:    f32,
	material:  material,
	is_moving: bool,
}

sphere_center_at :: proc(s: Sphere, time: f32) -> [3]f32 {
	if !s.is_moving { return s.center }
	return s.center + time * (s.center1 - s.center)
}

// sphere_get_uv returns (u, v) texture coordinates for a unit-sphere surface point p.
// p is the normalized hit point relative to sphere center (outward_normal for a sphere).
// Follows Ray Tracing: The Next Week Ch.4: theta = acos(-p.y), phi = atan2(-p.z, p.x) + π.
sphere_get_uv :: proc(p: [3]f32) -> (u, v: f32) {
	theta := math.acos(-p.y)
	phi   := math.atan2(-p.z, p.x) + math.PI
	u = phi / (2.0 * math.PI)
	v = theta / math.PI
	return
}

sphere_bounding_box :: proc(s: Sphere) -> AABB {
	r := s.radius
	box0 := AABB{
		x = Interval{s.center[0] - r, s.center[0] + r},
		y = Interval{s.center[1] - r, s.center[1] + r},
		z = Interval{s.center[2] - r, s.center[2] + r},
	}
	if !s.is_moving { return box0 }
	box1 := AABB{
		x = Interval{s.center1[0] - r, s.center1[0] + r},
		y = Interval{s.center1[1] - r, s.center1[1] + r},
		z = Interval{s.center1[2] - r, s.center1[2] + r},
	}
	return aabb_union(box0, box1)
}
