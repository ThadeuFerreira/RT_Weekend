package main

global_interval_empty : Interval = make_interval()
global_interval_universe : Interval = make_interval(0hfff00000_00000000, 0h7ff00000_00000000)

Interval :: struct {
    min : f32,
    max : f32,
}

make_interval :: proc(min : f32 = 0h7ff00000_00000000, max : f32 = 0hfff00000_00000000) -> Interval {
    return Interval{min, max}
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
