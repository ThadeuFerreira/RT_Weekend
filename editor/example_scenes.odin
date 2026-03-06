package editor

import "core:math"
import "RT_Weekend:core"
import "RT_Weekend:raytrace"
import "RT_Weekend:util"

// ExampleScene is a named scene builder used by the Examples menu.
// build() returns (spheres, camera, ground_texture). When ground_texture is nil, build_world_from_scene uses default grey ground.
ExampleScene :: struct {
    label: string,
    build: proc() -> (spheres: []core.SceneSphere, camera: core.CameraParams, ground_texture: raytrace.Texture),
}

// EXAMPLE_SCENES is the static registry of built-in example scenes.
EXAMPLE_SCENES := []ExampleScene{
    {label = "Weekend Final Scene",       build = build_weekend_final_scene},
    {label = "Next Week: Bouncing Balls", build = build_next_week_bouncing_scene},
    {label = "Next Week: Checkers Texture", build = build_next_week_texture_checker_scene},
}

WEEKEND_CAMERA :: core.CameraParams{
    lookfrom      = {13, 2, 3},
    lookat        = {0, 0, 0},
    vup           = {0, 1, 0},
    vfov          = 20,
    defocus_angle = 0.6,
    focus_dist    = 10,
    max_depth     = 50,
    shutter_open  = 0,
    shutter_close = 1,
}

// build_weekend_final_scene returns the final scene from "Ray Tracing in One Weekend".
// Uses a fixed seed (42) for deterministic output. Caller must delete the returned slice.
// Ground plane is NOT included — build_world_from_scene auto-prepends it.
build_weekend_final_scene :: proc() -> (spheres: []core.SceneSphere, camera: core.CameraParams, ground_texture: raytrace.Texture) {
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
                sphere.albedo = core.ConstantTexture{color = {r1 * r2, g1 * g2, b1 * b2}}
            } else if choose_mat < 0.95 {
                // Metallic
                sphere.material_kind = .Metallic
                sphere.albedo = core.ConstantTexture{color = {
                    util.random_float_range(&rng, 0.5, 1),
                    util.random_float_range(&rng, 0.5, 1),
                    util.random_float_range(&rng, 0.5, 1),
                }}
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
        albedo        = core.ConstantTexture{color = {0.4, 0.2, 0.1}},
    })
    append(&result, core.SceneSphere{
        center        = {4, 1, 0},
        radius        = 1.0,
        material_kind = .Metallic,
        albedo        = core.ConstantTexture{color = {0.7, 0.6, 0.5}},
        fuzz          = 0.0,
    })

    return result[:], WEEKEND_CAMERA, nil
}

// build_next_week_bouncing_scene returns the bouncing balls scene from "Ray Tracing: The Next Week" Chapter 2.
// Lambertian small spheres are moving (motion blur); metallic and dielectric are static.
// Uses the same fixed seed (42) and grid as build_weekend_final_scene. Caller must delete the returned slice.
build_next_week_bouncing_scene :: proc() -> (spheres: []core.SceneSphere, camera: core.CameraParams, ground_texture: raytrace.Texture) {
    rng := util.create_thread_rng(42)

    result := make([dynamic]core.SceneSphere)

    for a in -11..<11 {
        for b in -11..<11 {
            choose_mat := util.random_float(&rng)
            cx := f32(a) + 0.9 * util.random_float(&rng)
            cz := f32(b) + 0.9 * util.random_float(&rng)

            // Skip spheres too close to the big center sphere position
            dx2 := cx - 4
            dy2 := f32(0.2) - 0.2
            dz2 := cz - 0
            dist2 := math.sqrt(dx2*dx2 + dy2*dy2 + dz2*dz2)
            if dist2 <= 0.9 { continue }

            sphere: core.SceneSphere
            sphere.center = {cx, 0.2, cz}
            sphere.radius = 0.2

            if choose_mat < 0.8 {
                // Lambertian — moving sphere
                r1 := util.random_float(&rng)
                r2 := util.random_float(&rng)
                g1 := util.random_float(&rng)
                g2 := util.random_float(&rng)
                b1 := util.random_float(&rng)
                b2 := util.random_float(&rng)
                sphere.material_kind = .Lambertian
                sphere.albedo = core.ConstantTexture{color={r1 * r2, g1 * g2, b1 * b2}}
                sphere.is_moving = true
                sphere.center1 = sphere.center + [3]f32{0, util.random_float_range(&rng, 0, 0.5), 0}
            } else if choose_mat < 0.95 {
                // Metallic — static
                sphere.material_kind = .Metallic
                sphere.albedo = core.ConstantTexture{color={
                    util.random_float_range(&rng, 0.5, 1),
                    util.random_float_range(&rng, 0.5, 1),
                    util.random_float_range(&rng, 0.5, 1),
                }}
                sphere.fuzz = util.random_float_range(&rng, 0, 0.5)
            } else {
                // Dielectric — static
                sphere.material_kind = .Dielectric
                sphere.ref_idx = 1.5
            }

            append(&result, sphere)
        }
    }

    // Three large spheres (non-moving)
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
        albedo        = core.ConstantTexture{color = {0.4, 0.2, 0.1}},
    })
    append(&result, core.SceneSphere{
        center        = {4, 1, 0},
        radius        = 1.0,
        material_kind = .Metallic,
        albedo        = core.ConstantTexture{color = {0.7, 0.6, 0.5}},
        fuzz          = 0.0,
    })

    return result[:], WEEKEND_CAMERA, nil
}


build_next_week_texture_checker_scene :: proc() -> (spheres: []core.SceneSphere, camera: core.CameraParams, ground_texture: raytrace.Texture) {
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
                sphere.albedo = core.ConstantTexture{color = {r1 * r2, g1 * g2, b1 * b2}}
            } else if choose_mat < 0.95 {
                // Metallic
                sphere.material_kind = .Metallic
                sphere.albedo = core.ConstantTexture{color = {
                    util.random_float_range(&rng, 0.5, 1),
                    util.random_float_range(&rng, 0.5, 1),
                    util.random_float_range(&rng, 0.5, 1),
                }}
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
        albedo        = core.ConstantTexture{color = {0.4, 0.2, 0.1}},
    })
    append(&result, core.SceneSphere{
        center        = {4, 1, 0},
        radius        = 1.0,
        material_kind = .Metallic,
        albedo        = core.ConstantTexture{color = {0.7, 0.6, 0.5}},
        fuzz          = 0.0,
    })

    gt := raytrace.CheckerTexture{
        scale = 0.32,
        even  = {0.2, 0.3, 0.1},
        odd   = {0.9, 0.9, 0.9},
    }

    return result[:], WEEKEND_CAMERA, gt
}