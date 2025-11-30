package main

import "core:math"
import "core:fmt"

material :: union{
    lambertian,
    metalic,
    dieletric,
}

lambertian :: struct{
    albedo : [3]f32,
}

metalic :: struct{
    albedo : [3]f32,
    fuzz : f32,
}

dieletric :: struct{
    ref_idx : f32,
}

scatter :: proc (mat : material, r_in : ray, rec : hit_record, attenuation : ^[3]f32, scattered : ^ray, rng: ^ThreadRNG) -> bool {
    scattered := scattered
    attenuation := attenuation
    switch m in mat {
    case lambertian:
        scatter_direction := rec.normal + vector_random_unit(rng)

        // Catch degenerate scatter direction
        if vector_near_zero(scatter_direction) {
            scatter_direction = rec.normal
        }
        scattered^ = ray{rec.p, scatter_direction}
        attenuation^ = m.albedo
        return true
    case metalic:
        reflected := vector_reflect(r_in.dir, rec.normal)
        reflected = unit_vector(reflected) + m.fuzz * vector_random_unit(rng)
        scattered^ = ray{rec.p, reflected}
        attenuation^ = m.albedo
        return dot(scattered.dir, rec.normal) > 0
    case dieletric:
        attenuation^ = [3]f32{1.0, 1.0, 1.0}
        ri := rec.front_face ? 1.0/m.ref_idx : m.ref_idx

        unit_direction := unit_vector(r_in.dir)

        cos_theta := math.min(dot(-unit_direction, rec.normal), 1.0)
        sin_theta := math.sqrt(1.0 - cos_theta*cos_theta)

        cannot_refract := ri * sin_theta > 1.0
        direction := [3]f32{}

        if cannot_refract || reflectance(cos_theta, ri) > random_float(rng) {
            direction = vector_reflect(unit_direction, rec.normal)
        }
        else{
            direction = vector_refract(unit_direction, rec.normal, ri)
        }

        scattered^ = ray{rec.p, direction}
        return true
    }
    return false
}

reflectance :: proc (cosine : f32, ref_idx : f32) -> f32 {
    // Use Schlick's approximation for reflectance.
    r0 := (1-ref_idx) / (1+ref_idx)
    r0 = r0*r0
    return r0 + (1-r0)*math.pow((1 - cosine), 5)
}