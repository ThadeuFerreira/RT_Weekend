package editor

import "core:math"
import "RT_Weekend:core"
import "RT_Weekend:raytrace"
import "RT_Weekend:util"

// ExampleScene is a named scene builder used by the Examples menu.
// build() returns (spheres, quads, camera, ground_texture, include_ground).
// When ground_texture is nil, build_world_from_scene uses default grey ground.
ExampleScene :: struct {
    label: string,
    build: proc() -> (
        spheres: []core.SceneSphere,
        quads: []raytrace.Quad,
        camera: core.CameraParams,
        ground_texture: raytrace.Texture,
        include_ground: bool,
    ),
}

// EXAMPLE_SCENES is the static registry of built-in example scenes.
EXAMPLE_SCENES := []ExampleScene{
    {label = "Weekend Final Scene",         build = build_weekend_final_scene},
    {label = "Next Week: Bouncing Balls",   build = build_next_week_bouncing_scene},
    {label = "Next Week: Checkers Texture", build = build_next_week_texture_checker_scene},
    {label = "Next Week: Quads",            build = build_next_week_quads_scene},
    {label = "Next Week: Turbulence",       build = build_next_week_turbulence_scene},
    {label = "Cornell Box",                 build = build_cornell_box_scene},
}

// WEEKEND_CAMERA is the default for in-memory example scenes. Scene files loaded from disk with no "background" field get the same default (sky) in persistence.load_scene for backward compat.
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
    background    = core.CAMERA_BACKGROUND_SKY,
}

// WeekendGridParams configures the shared "One Weekend" grid of small spheres + three large spheres.
WeekendGridParams :: struct {
    lambertian_moving: bool, // when true, Lambertian small spheres get motion blur (center1 offset in Y)
}

// place_weekend_grid_spheres appends the standard grid of small spheres plus the three large spheres.
// Uses the given rng (seed 42 recommended for deterministic output). Caller owns result.
place_weekend_grid_spheres :: proc(rng: ^util.ThreadRNG, result: ^[dynamic]core.SceneSphere, params: WeekendGridParams) {
    for a in -11..<11 {
        for b in -11..<11 {
            choose_mat := util.random_float(rng)
            cx := f32(a) + 0.9 * util.random_float(rng)
            cz := f32(b) + 0.9 * util.random_float(rng)

            dx2 := cx - 4
            dy2 := f32(0.2) - 0.2
            dz2 := cz - 0
            dist2 := math.sqrt(dx2*dx2 + dy2*dy2 + dz2*dz2)
            if dist2 <= 0.9 { continue }

            sphere: core.SceneSphere
            sphere.center = {cx, 0.2, cz}
            sphere.radius = 0.2

            if choose_mat < 0.8 {
                r1 := util.random_float(rng)
                r2 := util.random_float(rng)
                g1 := util.random_float(rng)
                g2 := util.random_float(rng)
                b1 := util.random_float(rng)
                b2 := util.random_float(rng)
                sphere.material_kind = .Lambertian
                sphere.albedo = core.ConstantTexture{color = {r1 * r2, g1 * g2, b1 * b2}}
                if params.lambertian_moving {
                    sphere.is_moving = true
                    sphere.center1 = sphere.center + [3]f32{0, util.random_float_range(rng, 0, 0.5), 0}
                }
            } else if choose_mat < 0.95 {
                sphere.material_kind = .Metallic
                sphere.albedo = core.ConstantTexture{color = {
                    util.random_float_range(rng, 0.5, 1),
                    util.random_float_range(rng, 0.5, 1),
                    util.random_float_range(rng, 0.5, 1),
                }}
                sphere.fuzz = util.random_float_range(rng, 0, 0.5)
            } else {
                sphere.material_kind = .Dielectric
                sphere.ref_idx = 1.5
            }

            append(result, sphere)
        }
    }

    append(result, core.SceneSphere{
        center        = {0, 1, 0},
        radius        = 1.0,
        material_kind = .Dielectric,
        ref_idx       = 1.5,
    })
    append(result, core.SceneSphere{
        center        = {-4, 1, 0},
        radius        = 1.0,
        material_kind = .Lambertian,
        albedo        = core.ConstantTexture{color = {0.4, 0.2, 0.1}},
    })
    append(result, core.SceneSphere{
        center        = {4, 1, 0},
        radius        = 1.0,
        material_kind = .Metallic,
        albedo        = core.ConstantTexture{color = {0.7, 0.6, 0.5}},
        fuzz          = 0.0,
    })
}

// build_weekend_final_scene returns the final scene from "Ray Tracing in One Weekend".
// Uses a fixed seed (42) for deterministic output. Caller must delete the returned slice.
// Ground plane is NOT included — build_world_from_scene auto-prepends it.
build_weekend_final_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
) {
    rng := util.create_thread_rng(42)
    result := make([dynamic]core.SceneSphere)
    place_weekend_grid_spheres(&rng, &result, WeekendGridParams{})
    return result[:], nil, WEEKEND_CAMERA, nil, true
}

// build_next_week_bouncing_scene returns the bouncing balls scene from "Ray Tracing: The Next Week" Chapter 2.
// Lambertian small spheres are moving (motion blur); metallic and dielectric are static.
// Uses the same fixed seed (42) and grid as build_weekend_final_scene. Caller must delete the returned slice.
build_next_week_bouncing_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
) {
    rng := util.create_thread_rng(42)
    result := make([dynamic]core.SceneSphere)
    place_weekend_grid_spheres(&rng, &result, WeekendGridParams{lambertian_moving = true})
    return result[:], nil, WEEKEND_CAMERA, nil, true
}

// build_next_week_texture_checker_scene returns the same grid with a checker ground texture.
// Caller must delete the returned slice.
build_next_week_texture_checker_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
) {
    rng := util.create_thread_rng(42)
    result := make([dynamic]core.SceneSphere)
    place_weekend_grid_spheres(&rng, &result, WeekendGridParams{})
    gt := raytrace.CheckerTexture{
        scale = 0.32,
        even  = {0.2, 0.3, 0.1},
        odd   = {0.9, 0.9, 0.9},
    }
    return result[:], nil, WEEKEND_CAMERA, gt, true
}

// build_next_week_quads_scene returns the RTNW quad demo scene:
// five colored quads and a camera framing them.
build_next_week_quads_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
) {
    result_quads := make([dynamic]raytrace.Quad)

    left_red := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {1.0, 0.2, 0.2}},
    })
    back_green := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.2, 1.0, 0.2}},
    })
    right_blue := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.2, 0.2, 1.0}},
    })
    upper_orange := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {1.0, 0.5, 0.0}},
    })
    lower_teal := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.2, 0.8, 0.8}},
    })

    append(&result_quads, raytrace.make_quad(
        [3]f32{-3, -2, 5},
        [3]f32{0, 0, -4},
        [3]f32{0, 4, 0},
        left_red,
    ))
    append(&result_quads, raytrace.make_quad(
        [3]f32{-2, -2, 0},
        [3]f32{4, 0, 0},
        [3]f32{0, 4, 0},
        back_green,
    ))
    append(&result_quads, raytrace.make_quad(
        [3]f32{3, -2, 1},
        [3]f32{0, 0, 4},
        [3]f32{0, 4, 0},
        right_blue,
    ))
    append(&result_quads, raytrace.make_quad(
        [3]f32{-2, 3, 1},
        [3]f32{4, 0, 0},
        [3]f32{0, 0, 4},
        upper_orange,
    ))
    append(&result_quads, raytrace.make_quad(
        [3]f32{-2, -3, 5},
        [3]f32{4, 0, 0},
        [3]f32{0, 0, -4},
        lower_teal,
    ))

    quad_camera := core.CameraParams{
        lookfrom      = {0, 0, 9},
        lookat        = {0, 0, 0},
        vup           = {0, 1, 0},
        vfov          = 80,
        defocus_angle = 0,
        focus_dist    = 10,
        max_depth     = 50,
        shutter_open  = 0,
        shutter_close = 1,
        background    = core.CAMERA_BACKGROUND_SKY,
    }

    return nil, result_quads[:], quad_camera, nil, false
}

TURBULENCE_CAMERA :: core.CameraParams{
    lookfrom      = {13, 2, 3},
    lookat        = {0, 0, 0},
    vup           = {0, 1, 0},
    vfov          = 20,
    defocus_angle = 0,
    focus_dist    = 10,
    max_depth     = 50,
    shutter_open  = 0,
    shutter_close = 1,
    background    = core.CAMERA_BACKGROUND_SKY,
}

// build_next_week_turbulence_scene returns the "perlin spheres" scene from "Ray Tracing: The Next Week".
// One sphere over a large ground sphere, both with a turbulence (noise) texture. Caller must delete the returned slice.
build_next_week_turbulence_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
) {
    result := make([dynamic]core.SceneSphere)
    append(&result, core.SceneSphere{
        center        = {0, 2, 0},
        radius        = 2,
        material_kind = .Lambertian,
        albedo        = core.NoiseTexture{scale = 4},
    })
    return result[:], nil, TURBULENCE_CAMERA, core.NoiseTexture{scale = 4}, true
}

// Cornell Box: unit room [0,1]^3, area light on ceiling, and two inner boxes.
// No ground plane; only emitter contributes illumination.
build_cornell_box_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
) {
    result_quads := make([dynamic]raytrace.Quad)

    white := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.73, 0.73, 0.73}},
    })
    green := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.12, 0.45, 0.15}},
    })
    red := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.65, 0.05, 0.05}},
    })
    light_mat := raytrace.material(raytrace.diffuse_light{emit = {15, 15, 15}})

    // Left wall (green), right wall (red) per benchmark convention.
    append(&result_quads, raytrace.make_quad(
        [3]f32{555, 0, 0},
        [3]f32{0, 555, 0},
        [3]f32{0, 0, 555},
        green,
    ))
    append(&result_quads, raytrace.make_quad(
        [3]f32{0, 0, 0},
        [3]f32{0, 555, 0},
        [3]f32{0, 0, 555},
        red,
    ))
    // Ceiling area light.
    append(&result_quads, raytrace.make_quad(
        [3]f32{343, 554, 332},
        [3]f32{-130, 0, 0},
        [3]f32{0, 0, -105},
        light_mat,
    ))
    // Room shell.
    append(&result_quads, raytrace.make_quad(
        [3]f32{0, 0, 0},
        [3]f32{555, 0, 0},
        [3]f32{0, 0, 555},
        white,
    ))
    append(&result_quads, raytrace.make_quad(
        [3]f32{555, 555, 555},
        [3]f32{-555, 0, 0},
        [3]f32{0, 0, -555},
        white,
    ))
    append(&result_quads, raytrace.make_quad(
        [3]f32{0, 0, 555},
        [3]f32{555, 0, 0},
        [3]f32{0, 555, 0},
        white,
    ))

    // Tall box: 0.2 x 0.65 x 0.2 at (0.3, 0.0, 0.2), rotated Y by +15 deg.
    {
        ts := raytrace.TransformStack{}
        raytrace.transform_stack_init(&ts)
        defer raytrace.transform_stack_destroy(&ts)

        center := [3]f32{265,0,295}
        raytrace.transform_stack_push_mul(&ts, raytrace.mat4_translate(center))
        raytrace.transform_stack_push_mul(&ts, raytrace.mat4_rotate_y(15.0 * math.PI / 180.0))
        raytrace.transform_stack_push_mul(&ts, raytrace.mat4_translate(-center))

        raytrace.append_box_transformed(
            &result_quads,
            [3]f32{265, 0.0, 295},
            [3]f32{430, 330, 460},
            white,
            raytrace.transform_stack_current(&ts),
        )
    }

    // Short box: 0.16 x 0.3 x 0.16 at (0.78, 0.0, 0.3), rotated Y by -18 deg.
    {
        ts := raytrace.TransformStack{}
        raytrace.transform_stack_init(&ts)
        defer raytrace.transform_stack_destroy(&ts)

        center := [3]f32{130,0,65}
        raytrace.transform_stack_push_mul(&ts, raytrace.mat4_translate(center))
        raytrace.transform_stack_push_mul(&ts, raytrace.mat4_rotate_y(-18.0 * math.PI / 180.0))
        raytrace.transform_stack_push_mul(&ts, raytrace.mat4_translate(-center))

        raytrace.append_box_transformed(
            &result_quads,
            [3]f32{130, 0.0, 65},
            [3]f32{295, 165, 230},
            white,
            raytrace.transform_stack_current(&ts),
        )
    }

    cornell_camera := core.CameraParams{
        lookfrom      = {278, 278, -800},
        lookat        = {278, 278, 0},
        vup           = {0, 1, 0},
        vfov          = 40,
        defocus_angle = 0,
        focus_dist    = 1.85,
        max_depth     = 50,
        shutter_open  = 0,
        shutter_close = 1,
        background    = {0, 0, 0},
    }

    return nil, result_quads[:], cornell_camera, nil, false
}

