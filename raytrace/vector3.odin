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


ray :: struct {
    origin : [3]f32,
    dir : [3]f32,
    time : f32,
}

ray_at :: proc(r : ray, t : f32) -> [3]f32 {
    return r.origin + t*r.dir
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
