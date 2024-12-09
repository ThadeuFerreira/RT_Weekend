package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:strconv"

vector_length :: proc(v : [3]f32) -> f32 {
    return math.sqrt_f32(vector_length_squared(v))
}

vector_length_squared :: proc(v : [3]f32) -> f32 {
    return v[0]*v[0] + v[1]*v[1] + v[2]*v[2]
}

vector_near_zero :: proc(v : [3]f32) -> bool {
    // Return true if the vector is close to zero in all dimensions.
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

vector_random :: proc() -> [3]f32 {
    return [3]f32{random_float(), random_float(), random_float()}
}

vector_random_range :: proc(min : f32, max : f32) -> [3]f32 {
    return [3]f32{random_float_range(min, max), random_float_range(min, max), random_float_range(min, max)}
}

vector_random_unit :: proc() -> [3]f32{
    for true {
        p := vector_random_range(-1, 1)
        l := vector_length_squared(p)
        if  l <= 1 && l > math.F32_EPSILON {
            return p/l
        }
    }
    return [3]f32{}
}

vector_random_on_hemisphere :: proc(normal : [3]f32) -> [3]f32 {
    on_unit_sphere := vector_random_unit()
    if dot(on_unit_sphere, normal) > 0.0 {
        return on_unit_sphere
    } else {
        return -on_unit_sphere
    }
}

vector_random_in_unit_disk :: proc() -> [3]f32 {
    for true {
        p := [3]f32{random_float_range(-1, 1), random_float_range(-1, 1), 0}
        if vector_length_squared(p) < 1 {
            return p
        }
    }
    return [3]f32{}
}


hit_sphere :: proc (sphere : Sphere, r : ray,  ray_t : Interval, rec : ^hit_record) -> bool {
    oc := sphere.center - r.orig
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
    outward_normal := (rec.p - sphere.center) / sphere.radius

    set_face_normal(rec, r, outward_normal)

    return true
    
}


ray :: struct {
    orig : [3]f32,
    dir : [3]f32,
}

ray_at :: proc(r : ray, t : f32) -> [3]f32 {
    return r.orig + t*r.dir
}

ray_color :: proc(r : ray, depth : int , world : [dynamic]Object) -> [3]f32 {
    if depth <= 0 {
        return [3]f32{0,0,0}
    }
    ray_t := Interval{0.001, infinity}
    hr := hit_record{}
    closest_so_far := ray_t.max
    hit_anything := false
    for o in world {
        
        if hit(r, ray_t, &hr, o, &closest_so_far) {
            hit_anything = true
        }
    }
    if hit_anything{
        scattered := ray{}
        attenuation := [3]f32{}
        if scatter(hr.material, r, hr, &attenuation, &scattered) {
            return attenuation * ray_color(scattered, depth - 1, world)
        }
        return [3]f32{0,0,0}
    }
    unit_direction := unit_vector(r.dir)
    a := 0.5 * (unit_direction[1] + 1.0)
    ones := [3]f32{1.0, 1.0, 1.0}
    color := [3]f32{0.5,0.7,1}
    return (1.0-a)*ones + a*color
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

