package main

material :: union{
    lambertian,
    metalic,
}

lambertian :: struct{
    albedo : [3]f32,
}

metalic :: struct{
    albedo : [3]f32,
    fuzz : f32,
}

scatter :: proc (mat : material, r_in : ray, rec : hit_record, attenuation : ^[3]f32, scattered : ^ray) -> bool {
    scattered := scattered
    attenuation := attenuation
    switch m in mat {
    case lambertian:
        scatter_direction := rec.normal + vector_random_unit()

        // Catch degenerate scatter direction
        if vector_near_zero(scatter_direction) {
            scatter_direction = rec.normal
        }
        scattered^ = ray{rec.p, scatter_direction}
        attenuation^ = m.albedo
        return true
    case metalic:
        reflected := vector_reflect(r_in.dir, rec.normal)
        scattered^ = ray{rec.p, reflected}
        attenuation^ = m.albedo
        return true
    }
    return false
}