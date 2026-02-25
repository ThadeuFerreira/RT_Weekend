package raytrace

import "core:math"
import "RT_Weekend:util"

material :: union{
    lambertian,
    metallic,
    dielectric,
}

lambertian :: struct{
    albedo : [3]f32,
}

metallic :: struct{
    albedo : [3]f32,
    fuzz : f32,
}

dielectric :: struct{
    ref_idx : f32,
}

scatter :: proc (mat : material, r_in : ray, rec : hit_record, attenuation : ^[3]f32, scattered : ^ray, rng: ^util.ThreadRNG) -> bool {
    scattered := scattered
    attenuation := attenuation
    switch m in mat {
    case lambertian:
        scatter_dir := rec.normal + vector_random_unit(rng)
        if vector_length_squared(scatter_dir) < 1e-16 {
            scatter_dir = rec.normal
        }
        scattered^ = ray{rec.p, scatter_dir}
        attenuation^ = m.albedo
        return true
    case metallic:
        reflected := vector_reflect(r_in.dir, rec.normal)
        reflected = unit_vector(reflected) + m.fuzz * vector_random_unit(rng)
        scattered^ = ray{rec.p, reflected}
        attenuation^ = m.albedo
        return dot(scattered.dir, rec.normal) > 0
    case dielectric:
        attenuation^ = [3]f32{1.0, 1.0, 1.0}
        ri := rec.front_face ? 1.0/m.ref_idx : m.ref_idx

        unit_direction := unit_vector(r_in.dir)
        neg_unit_dir := -unit_direction
        cos_theta := math.min(dot(neg_unit_dir, rec.normal), 1.0)
        sin_theta_sq := 1.0 - cos_theta*cos_theta
        sin_theta := math.sqrt(sin_theta_sq)

        cannot_refract := ri * sin_theta > 1.0
        use_reflection := cannot_refract || (reflectance(cos_theta, ri) > util.random_float(rng))

        direction: [3]f32
        if use_reflection {
            direction = vector_reflect(unit_direction, rec.normal)
        } else {
            direction = vector_refract(unit_direction, rec.normal, ri)
        }

        scattered^ = ray{rec.p, direction}
        return true
    }
    return false
}

reflectance :: proc (cosine : f32, ref_idx : f32) -> f32 {
    r0 := (1-ref_idx) / (1+ref_idx)
    r0 = r0*r0
    return r0 + (1-r0)*math.pow((1 - cosine), 5)
}
