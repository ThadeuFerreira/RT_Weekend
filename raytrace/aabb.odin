package raytrace

import "core:math"

AABB :: struct {
    x: Interval,
    y: Interval,
    z: Interval,
}

// AABB padding delta so flat quads have non-zero volume (avoids numerical issues in BVH).
AABB_PAD_DELTA :: 0.0001

// aabb_pad_to_minimums ensures no side is narrower than AABB_PAD_DELTA.
aabb_pad_to_minimums :: proc(box: ^AABB) {
    if interval_size(box.x) < AABB_PAD_DELTA {
        box.x = interval_expand(box.x, AABB_PAD_DELTA)
    }
    if interval_size(box.y) < AABB_PAD_DELTA {
        box.y = interval_expand(box.y, AABB_PAD_DELTA)
    }
    if interval_size(box.z) < AABB_PAD_DELTA {
        box.z = interval_expand(box.z, AABB_PAD_DELTA)
    }
}

aabb_union :: proc(box0: AABB, box1: AABB) -> AABB {
    return AABB{
        x = Interval{
            math.min(box0.x.min, box1.x.min),
            math.max(box0.x.max, box1.x.max),
        },
        y = Interval{
            math.min(box0.y.min, box1.y.min),
            math.max(box0.y.max, box1.y.max),
        },
        z = Interval{
            math.min(box0.z.min, box1.z.min),
            math.max(box0.z.max, box1.z.max),
        },
    }
}

// aabb_surface_area returns 2*(dx*dy + dy*dz + dz*dx).
// Returns 0 for empty / degenerate boxes (where any dimension is negative).
aabb_surface_area :: proc(box: AABB) -> f32 {
    dx := box.x.max - box.x.min
    dy := box.y.max - box.y.min
    dz := box.z.max - box.z.min
    if dx < 0 || dy < 0 || dz < 0 { return 0 }
    return 2.0 * (dx*dy + dy*dz + dz*dx)
}

aabb_hit :: proc(box: AABB, r: ray, ray_t: Interval) -> bool {
    tmin := ray_t.min
    tmax := ray_t.max

    for axis in 0..<3 {
        ax: Interval
        dir: f32
        origin: f32

        switch axis {
        case 0:
            ax = box.x
            dir = r.dir[0]
            origin = r.origin[0]
        case 1:
            ax = box.y
            dir = r.dir[1]
            origin = r.origin[1]
        case 2:
            ax = box.z
            dir = r.dir[2]
            origin = r.origin[2]
        }

        if math.abs(dir) < 1e-8 {
            if origin < ax.min || origin > ax.max {
                return false
            }
        } else {
            invD := 1.0 / dir
            t0 := (ax.min - origin) * invD
            t1 := (ax.max - origin) * invD

            if t0 > t1 {
                t0, t1 = t1, t0
            }

            tmin = math.max(tmin, t0)
            tmax = math.min(tmax, t1)

            if tmax <= tmin {
                return false
            }
        }
    }
    return true
}

// aabb_hit_fast is like aabb_hit but uses precomputed inverse direction.
// It keeps a robust zero-direction slab check so thin AABBs (e.g. quads) are reliable.
aabb_hit_fast :: proc(box: AABB, dir: [3]f32, inv_dir: [3]f32, origin: [3]f32, ray_t: Interval) -> bool {
    tmin := ray_t.min
    tmax := ray_t.max

    axes := [3]Interval{box.x, box.y, box.z}
    for axis in 0..<3 {
        if math.abs(dir[axis]) < 1e-8 {
            if origin[axis] < axes[axis].min || origin[axis] > axes[axis].max {
                return false
            }
            continue
        }
        invD := inv_dir[axis]
        o    := origin[axis]
        t0   := (axes[axis].min - o) * invD
        t1   := (axes[axis].max - o) * invD
        if t0 > t1 { t0, t1 = t1, t0 }
        tmin = math.max(tmin, t0)
        tmax = math.min(tmax, t1)
        if tmax <= tmin { return false }
    }
    return true
}

// aabb_from_points builds an AABB from two corner points.
aabb_from_points :: proc(p, q: [3]f32) -> AABB {
	return AABB{
		x = Interval{math.min(p[0], q[0]), math.max(p[0], q[0])},
		y = Interval{math.min(p[1], q[1]), math.max(p[1], q[1])},
		z = Interval{math.min(p[2], q[2]), math.max(p[2], q[2])},
	}
}
