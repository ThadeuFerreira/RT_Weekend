package raytrace

global_interval_empty : Interval = Interval{min = 0h7ff00000_00000000, max = 0hfff00000_00000000}
global_interval_universe : Interval = Interval{min = 0hfff00000_00000000, max =0h7ff00000_00000000}

Interval :: struct {
    min : f32,
    max : f32,
}


interval_size :: proc(i : Interval) -> f32 {
    return i.max - i.min
}

interval_contains :: proc(i : Interval, x : f32) -> bool {
    return i.min <= x && x <= i.max
}

interval_surrounds :: proc(i : Interval, x : f32) -> bool {
    return i.min < x && x < i.max
}

interval_clamp :: proc(i : Interval, x : f32) -> f32 {
    if x < i.min {
        return i.min
    }
    if x > i.max {
        return i.max
    }
    return x
}

// interval_expand expands the interval by delta (half on each side) so the new size is size + delta.
// Used to pad zero-thickness AABB dimensions to avoid numerical issues with flat quads.
interval_expand :: proc(i: Interval, delta: f32) -> Interval {
    half := delta * 0.5
    return Interval{min = i.min - half, max = i.max + half}
}
