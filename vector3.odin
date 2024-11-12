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

vector_random :: proc() -> [3]f32 {
    return [3]f32{random_float(), random_float(), random_float()}
}

vector_random_range :: proc(min : f32, max : f32) -> [3]f32 {
    return [3]f32{random_float_range(min, max), random_float_range(min, max), random_float_range(min, max)}
}



Sphere :: struct {
    center : [3]f32,
    radius : f32,
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

ray_color :: proc(r : ray, world : []Object) -> [3]f32 {
    hr := hit_record{}
    ray_t := Interval{0, infinity}
    for o in world {
        if hit(r, ray_t, &hr, o) {
            N := unit_vector(hr.normal)
            r := 0.5*[3]f32{N[0]+1.0, N[1]+1.0, N[2]+1.0}
            return r
        }
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
// inline double dot(const vec3& u, const vec3& v) {
//     return u.e[0] * v.e[0]
//          + u.e[1] * v.e[1]
//          + u.e[2] * v.e[2];
// }

dot :: proc(u : [3]f32, v : [3]f32) -> f32 {
    return u[0]*v[0] + u[1]*v[1] + u[2]*v[2]
}

