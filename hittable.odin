package main

import "core:fmt"

hit_record :: struct {
    p : [3]f32,
    normal : [3]f32,
    t : f32,
    front_face : bool,
}

Object :: union {
    Sphere,
}

set_face_normal :: proc(rec : ^hit_record, r : ray, outward_normal : [3]f32) {
    rec.front_face = dot(r.dir, outward_normal) < 0
    if rec.front_face {
        rec.normal = outward_normal
    } else {
        rec.normal = -outward_normal
    }
}

make_hittable_slice :: proc($N :$I) -> [N]$T {
    return [N]$T{}
}
 
//virtual bool hit(const ray& r, double ray_tmin, double ray_tmax, hit_record& rec) const = 0;


hit :: proc(r : ray, ray_t : Interval, rec : ^hit_record, object : Object) -> bool{
    hit_anything := false
    closest_so_far := ray_t.max
    switch s in object {
    case Sphere:
        return hit_sphere(s, r, Interval{ray_t.min, closest_so_far}, rec)
    }
    return false
}
