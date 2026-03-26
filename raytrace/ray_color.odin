package raytrace

import "core:math"
import "RT_Weekend:util"

// ray_color traces one ray: hit nothing → background; hit emitter → emission only or emission + scattered.
// background is the color when the ray misses the scene (e.g. pure black so only emitters light the scene).
ray_color :: proc(r: ray, depth: int, world: [dynamic]Object, rng: ^util.ThreadRNG, thread_breakdown: ^ThreadRenderingBreakdown = nil, bvh_root: ^BVHNode = nil, background: [3]f32 = {0, 0, 0}) -> [3]f32 {
    if depth <= 0 {
        return [3]f32{0, 0, 0}
    }
    ray_t := Interval{0.001, math.inf_f32(1.0)}
    hr := hit_record{}
    closest_so_far := ray_t.max
    hit_anything := false

    {
        field_ptr := thread_breakdown != nil ? &thread_breakdown.intersection_time : nil
        scope := PROFILE_SCOPE(field_ptr)
        defer PROFILE_SCOPE_END(scope)

        if bvh_root != nil {
            hit_anything = bvh_hit(bvh_root, r, ray_t, &hr, &closest_so_far, rng)
            if hit_anything && thread_breakdown != nil {
                thread_breakdown.total_intersections += 1
            }
        } else {
            for o in world {
                if hit(r, ray_t, &hr, o, &closest_so_far, rng) {
                    hit_anything = true
                    if thread_breakdown != nil {
                        thread_breakdown.total_intersections += 1
                    }
                }
                if thread_breakdown != nil {
                    thread_breakdown.total_intersections += 1
                }
            }
        }
    }

    if !hit_anything {
        field_ptr := thread_breakdown != nil ? &thread_breakdown.background_time : nil
        scope := PROFILE_SCOPE(field_ptr)
        defer PROFILE_SCOPE_END(scope)
        return background
    }

    color_from_emission := emitted(hr.material, hr.u, hr.v, hr.p)
    scattered := ray{}
    attenuation := [3]f32{}
    scatter_result: bool

    {
        field_ptr := thread_breakdown != nil ? &thread_breakdown.scatter_time : nil
        scope := PROFILE_SCOPE(field_ptr)
        defer PROFILE_SCOPE_END(scope)
        scatter_result = scatter(hr.material, r, hr, &attenuation, &scattered, rng)
    }

    if !scatter_result {
        return color_from_emission
    }
    color_from_scatter := attenuation * ray_color(scattered, depth - 1, world, rng, thread_breakdown, bvh_root, background)
    return color_from_emission + color_from_scatter
}

// ray_color_linear is the same as ray_color but prefers bvh_hit_linear
// (iterative, cache-friendly) over the recursive bvh_hit when a flat
// linear BVH is available.  Passing nil for linear_nodes falls back to
// the recursive path so the two implementations remain comparable.
ray_color_linear :: proc(
    r:              ray,
    depth:          int,
    world:          [dynamic]Object,
    rng:            ^util.ThreadRNG,
    thread_breakdown: ^ThreadRenderingBreakdown = nil,
    bvh_root:       ^BVHNode = nil,
    linear_nodes:   []LinearBVHNode = nil,
    background:     [3]f32 = {0, 0, 0},
) -> [3]f32 {
    if depth <= 0 { return [3]f32{0, 0, 0} }

    ray_t := Interval{0.001, math.inf_f32(1.0)}
    hr          := hit_record{}
    hit_anything := false
    closest      := ray_t.max

    {
        field_ptr := thread_breakdown != nil ? &thread_breakdown.intersection_time : nil
        scope := PROFILE_SCOPE(field_ptr)
        defer PROFILE_SCOPE_END(scope)

        if linear_nodes != nil && len(linear_nodes) > 0 {
            world_slice := world[:]
            hr, hit_anything = bvh_hit_linear(linear_nodes, world_slice, r, ray_t, rng)
            if hit_anything { closest = hr.t }
        } else if bvh_root != nil {
            hit_anything = bvh_hit(bvh_root, r, ray_t, &hr, &closest, rng)
        } else {
            for o in world {
                if hit(r, ray_t, &hr, o, &closest, rng) {
                    hit_anything = true
                }
            }
        }

        if hit_anything && thread_breakdown != nil {
            thread_breakdown.total_intersections += 1
        }
    }

    if !hit_anything {
        field_ptr := thread_breakdown != nil ? &thread_breakdown.background_time : nil
        scope := PROFILE_SCOPE(field_ptr)
        defer PROFILE_SCOPE_END(scope)
        return background
    }

    color_from_emission := emitted(hr.material, hr.u, hr.v, hr.p)
    scattered     := ray{}
    attenuation   := [3]f32{}
    scatter_result: bool

    {
        field_ptr := thread_breakdown != nil ? &thread_breakdown.scatter_time : nil
        scope := PROFILE_SCOPE(field_ptr)
        defer PROFILE_SCOPE_END(scope)
        scatter_result = scatter(hr.material, r, hr, &attenuation, &scattered, rng)
    }

    if !scatter_result {
        return color_from_emission
    }
    color_from_scatter := attenuation * ray_color_linear(scattered, depth - 1, world, rng, thread_breakdown, bvh_root, linear_nodes, background)
    return color_from_emission + color_from_scatter
}
