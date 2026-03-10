package raytrace

import "core:math"
import "RT_Weekend:util"

material :: union {
	lambertian,
	metallic,
	dielectric,
	diffuse_light,
}

lambertian :: struct {
    albedo: RTexture,
}

metallic :: struct{
    albedo : [3]f32,
    fuzz : f32,
}

dielectric :: struct {
	ref_idx: f32,
}

// diffuse_light emits light and does not scatter (no reflection).
diffuse_light :: struct {
	emit: [3]f32,
}

// emitted returns the color emitted by the surface at (u, v, p).
// Base default is black (all non-emitting materials); only diffuse_light returns a non-zero color.
emitted :: proc(mat: material, u, v: f32, p: [3]f32) -> [3]f32 {
	switch m in mat {
	case diffuse_light:
		return m.emit
	case lambertian, metallic, dielectric:
		return [3]f32{0, 0, 0}
	}
	return [3]f32{0, 0, 0}
}

scatter :: proc (mat : material, r_in : ray, rec : hit_record, attenuation : ^[3]f32, scattered : ^ray, rng: ^util.ThreadRNG) -> bool {
    switch m in mat {
    case lambertian:
        scatter_dir := rec.normal + vector_random_unit(rng)
        if vector_length_squared(scatter_dir) < 1e-16 {
            scatter_dir = rec.normal
        }
        scattered^ = ray{origin = rec.p, dir = scatter_dir, time = r_in.time}
        attenuation^ = texture_value_runtime(m.albedo, rec.u, rec.v, rec.p)
        return true
    case metallic:
        reflected := vector_reflect(r_in.dir, rec.normal)
        reflected = unit_vector(reflected) + m.fuzz * vector_random_unit(rng)
        scattered^ = ray{origin = rec.p, dir = reflected, time = r_in.time}
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

        scattered^ = ray{origin = rec.p, dir = direction, time = r_in.time}
        return true
	case diffuse_light:
		// Lights do not scatter.
		return false
	}
	return false
}

reflectance :: proc (cosine : f32, ref_idx : f32) -> f32 {
    r0 := (1-ref_idx) / (1+ref_idx)
    r0 = r0*r0
    return r0 + (1-r0)*math.pow((1 - cosine), 5)
}

// material_display_color returns a [3]f32 color for editor/preview visualization (no sampling context).
// For diffuse_light, emit is normalized by max component so HDR values (e.g. {15,15,15}) don't blow out the swatch.
material_display_color :: proc(mat: material) -> [3]f32 {
	switch m in mat {
	case lambertian:
		return texture_value_runtime(m.albedo, 0.5, 0.5, [3]f32{0, 0, 0})
	case metallic:
		return m.albedo
	case dielectric:
		return [3]f32{0.92, 0.92, 0.95}
	case diffuse_light:
		intensity := max(m.emit[0], max(m.emit[1], m.emit[2]))
		if intensity <= 0 do return [3]f32{0, 0, 0}
		return [3]f32{m.emit[0] / intensity, m.emit[1] / intensity, m.emit[2] / intensity}
	}
	return [3]f32{0.5, 0.5, 0.5}
}
