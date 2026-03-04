package editor

import "core:math"
import "RT_Weekend:core"
import "RT_Weekend:util"

// ExampleScene is a named scene builder used by the Examples menu.
ExampleScene :: struct {
    label: string,
    build: proc() -> (spheres: []core.SceneSphere, camera: core.CameraParams),
}

// EXAMPLE_SCENES is the static registry of built-in example scenes.
EXAMPLE_SCENES := []ExampleScene{
    {label = "Weekend Final Scene", build = build_weekend_final_scene},
}

WEEKEND_CAMERA :: core.CameraParams{
    lookfrom      = {13, 2, 3},
    lookat        = {0, 0, 0},
    vup           = {0, 1, 0},
    vfov          = 20,
    defocus_angle = 0.6,
    focus_dist    = 10,
    max_depth     = 50,
}

// build_weekend_final_scene returns the final scene from "Ray Tracing in One Weekend".
// Uses a fixed seed (42) for deterministic output. Caller must delete the returned slice.
// Ground plane is NOT included — build_world_from_scene auto-prepends it.
build_weekend_final_scene :: proc() -> (spheres: []core.SceneSphere, camera: core.CameraParams) {
    rng := util.create_thread_rng(42)

    result := make([dynamic]core.SceneSphere)

    for a in -11..<11 {
        for b in -11..<11 {
            choose_mat := util.random_float(&rng)
            cx := f32(a) + 0.9 * util.random_float(&rng)
            cz := f32(b) + 0.9 * util.random_float(&rng)

            // Skip spheres too close to the big center sphere position
            dx := cx - 4
            dz := cz - 0.2
            dist := math.sqrt(dx*dx + dz*dz + f32(0.2-0.9)*(f32(0.2-0.9)))
            _ = dist
            dx2 := cx - 4
            dy2 := f32(0.2) - 0.2
            dz2 := cz - 0
            dist2 := math.sqrt(dx2*dx2 + dy2*dy2 + dz2*dz2)
            if dist2 <= 0.9 { continue }

            sphere: core.SceneSphere
            sphere.center = {cx, 0.2, cz}
            sphere.radius = 0.2

            if choose_mat < 0.8 {
                // Lambertian
                r1 := util.random_float(&rng)
                r2 := util.random_float(&rng)
                g1 := util.random_float(&rng)
                g2 := util.random_float(&rng)
                b1 := util.random_float(&rng)
                b2 := util.random_float(&rng)
                sphere.material_kind = .Lambertian
                sphere.albedo = {r1 * r2, g1 * g2, b1 * b2}
            } else if choose_mat < 0.95 {
                // Metallic
                sphere.material_kind = .Metallic
                sphere.albedo = {
                    util.random_float_range(&rng, 0.5, 1),
                    util.random_float_range(&rng, 0.5, 1),
                    util.random_float_range(&rng, 0.5, 1),
                }
                sphere.fuzz = util.random_float_range(&rng, 0, 0.5)
            } else {
                // Dielectric
                sphere.material_kind = .Dielectric
                sphere.ref_idx = 1.5
            }

            append(&result, sphere)
        }
    }

    // Three large spheres
    append(&result, core.SceneSphere{
        center        = {0, 1, 0},
        radius        = 1.0,
        material_kind = .Dielectric,
        ref_idx       = 1.5,
    })
    append(&result, core.SceneSphere{
        center        = {-4, 1, 0},
        radius        = 1.0,
        material_kind = .Lambertian,
        albedo        = {0.4, 0.2, 0.1},
    })
    append(&result, core.SceneSphere{
        center        = {4, 1, 0},
        radius        = 1.0,
        material_kind = .Metallic,
        albedo        = {0.7, 0.6, 0.5},
        fuzz          = 0.0,
    })

    return result[:], WEEKEND_CAMERA
}
