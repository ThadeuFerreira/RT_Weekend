package raytrace

import "core:math"
import "RT_Weekend:util"

//CPU Raytracer functions//

// Gamma correction for sRGB display (linear -> gamma 2)
linear_to_gamma :: proc(linear: f32) -> f32 {
    return math.sqrt(math.max(linear, 0.0))
}

// Small functions - compiler should inline automatically
vector_length_squared :: proc(v : [3]f32) -> f32 {
    return v[0]*v[0] + v[1]*v[1] + v[2]*v[2]
}

vector_length :: proc(v : [3]f32) -> f32 {
    return math.sqrt_f32(vector_length_squared(v))
}

vector_near_zero :: proc(v : [3]f32) -> bool {
    s := f32(1e-8)
    return (math.abs(v[0]) < s) && (math.abs(v[1]) < s) && (math.abs(v[2]) < s)
}

vector_reflect :: proc(v : [3]f32, n : [3]f32) -> [3]f32 {
    return v - 2*dot(v, n)*n
}

vector_refract :: proc(uv : [3]f32, n : [3]f32, etai_over_etat : f32) -> [3]f32 {
    cos_theta := math.min(dot(-uv, n), 1.0)
    r_out_perp := etai_over_etat * (uv + cos_theta*n)
    r_out_parallel := -math.sqrt(math.abs(1.0 - vector_length_squared(r_out_perp))) * n
    return r_out_perp + r_out_parallel
}

vector_random :: proc(rng: ^util.ThreadRNG) -> [3]f32 {
    return [3]f32{util.random_float(rng), util.random_float(rng), util.random_float(rng)}
}

vector_random_range :: proc(rng: ^util.ThreadRNG, min : f32, max : f32) -> [3]f32 {
    return [3]f32{util.random_float_range(rng, min, max), util.random_float_range(rng, min, max), util.random_float_range(rng, min, max)}
}

vector_random_unit :: proc(rng: ^util.ThreadRNG) -> [3]f32{
    for true {
        p := vector_random_range(rng, -1, 1)
        l := vector_length_squared(p)
        if  l <= 1 && l > math.F32_EPSILON {
            return p/l
        }
    }
    return [3]f32{}
}

vector_random_on_hemisphere :: proc(rng: ^util.ThreadRNG, normal : [3]f32) -> [3]f32 {
    on_unit_sphere := vector_random_unit(rng)
    if dot(on_unit_sphere, normal) > 0.0 {
        return on_unit_sphere
    } else {
        return -on_unit_sphere
    }
}

vector_random_in_unit_disk :: proc(rng: ^util.ThreadRNG) -> [3]f32 {
    for true {
        p := [3]f32{util.random_float_range(rng, -1, 1), util.random_float_range(rng, -1, 1), 0}
        if vector_length_squared(p) < 1 {
            return p
        }
    }
    return [3]f32{}
}


hit_sphere :: proc (sphere : Sphere, r : ray,  ray_t : Interval, rec : ^hit_record) -> bool {
    current_center := sphere_center_at(sphere, r.time)
    oc := current_center - r.origin
    a := vector_length_squared(r.dir)
    h := dot(r.dir, oc)
    c := vector_length_squared(oc) - sphere.radius*sphere.radius
    discriminant := h*h - a*c

    if discriminant < 0 {
        return false
    }
    discriminant = math.sqrt_f32(discriminant)
    root := (h - discriminant) / a
    if !interval_surrounds(ray_t, root) {
        root = (h + discriminant) / a
        if !interval_surrounds(ray_t, root) {
            return false
        }
    }

    rec.material = sphere.material

    rec.t = root
    rec.p = ray_at(r, rec.t)
    outward_normal := (rec.p - current_center) / sphere.radius

    set_face_normal(rec, r, outward_normal)
    rec.u, rec.v = sphere_get_uv(outward_normal)

    return true
}

// hit_quad tests a ray against a planar quad (Q + α*u + β*v, α,β in [0,1]).
// Matches RTNW: ray-plane intersection then interior test using cached w.
hit_quad :: proc(q: Quad, r: ray, ray_t: Interval, rec: ^hit_record) -> bool {
    denom := dot(q.normal, r.dir)
    if math.abs(denom) < 1e-8 {
        return false
    }
    t := (q.D - dot(q.normal, r.origin)) / denom
    if t < ray_t.min || t > ray_t.max {
        return false
    }
    intersection := ray_at(r, t)
    planar_hitpt := intersection - q.Q

    alpha := dot(q.w, cross(planar_hitpt, q.v))
    beta  := dot(q.w, cross(q.u, planar_hitpt))
    if alpha < 0 || alpha > 1 || beta < 0 || beta > 1 {
        return false
    }

    rec.t = t
    rec.p = intersection
    rec.material = q.material
    set_face_normal(rec, r, q.normal)
    rec.u = alpha
    rec.v = beta
    return true
}


ray :: struct {
    origin : [3]f32,
    dir : [3]f32,
    time : f32,
}

ray_at :: proc(r : ray, t : f32) -> [3]f32 {
    return r.origin + t*r.dir
}

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
// ray_color_linear: same as ray_color but uses bvh_hit_linear when linear_nodes is provided.
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

unit_vector :: proc(v : [3]f32) -> [3]f32 {
    return v / vector_length(v)
}

normalize_vec3 :: proc(v : [3]f32) -> [3]f32 {
    mag := math.sqrt_f32(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
    return v / mag
}

cross :: proc(u : [3]f32, v : [3]f32) -> [3]f32 {
    return [3]f32{u[1]*v[2] - u[2]*v[1], u[2]*v[0] - u[0]*v[2], u[0]*v[1] - u[1]*v[0]}
}
dot :: proc(u : [3]f32, v : [3]f32) -> f32 {
    return u[0]*v[0] + u[1]*v[1] + u[2]*v[2]
}
