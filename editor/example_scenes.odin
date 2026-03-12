package editor

import "core:math"
import "RT_Weekend:core"
import "RT_Weekend:raytrace"
import "RT_Weekend:util"

// ExampleScene is a named scene builder used by the Examples menu.
// build() returns (spheres, quads, camera, ground_texture, include_ground, volumes).
// When ground_texture is nil, build_world_from_scene uses default grey ground.
// When volumes is non-nil, caller must delete(volumes); volumes are copied into app.e_volumes and appended to world.
ExampleScene :: struct {
    label: string,
    build: proc() -> (
        spheres: []core.SceneSphere,
        quads: []raytrace.Quad,
        camera: core.CameraParams,
        ground_texture: raytrace.Texture,
        include_ground: bool,
        volumes: []core.SceneVolume,
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
    {label = "Volume Smoke",                build = build_volume_smoke_scene},
    {label = "The Next Week Final",         build = build_next_week_final_scene},
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
    volumes: []core.SceneVolume,
) {
    rng := util.create_thread_rng(42)
    result := make([dynamic]core.SceneSphere)
    place_weekend_grid_spheres(&rng, &result, WeekendGridParams{})
    return result[:], nil, WEEKEND_CAMERA, nil, true, nil
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
    volumes: []core.SceneVolume,
) {
    rng := util.create_thread_rng(42)
    result := make([dynamic]core.SceneSphere)
    place_weekend_grid_spheres(&rng, &result, WeekendGridParams{lambertian_moving = true})
    return result[:], nil, WEEKEND_CAMERA, nil, true, nil
}

// build_next_week_texture_checker_scene returns the same grid with a checker ground texture.
// Caller must delete the returned slice.
build_next_week_texture_checker_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
    volumes: []core.SceneVolume,
) {
    rng := util.create_thread_rng(42)
    result := make([dynamic]core.SceneSphere)
    place_weekend_grid_spheres(&rng, &result, WeekendGridParams{})
    gt := raytrace.CheckerTexture{
        scale = 0.32,
        even  = {0.2, 0.3, 0.1},
        odd   = {0.9, 0.9, 0.9},
    }
    return result[:], nil, WEEKEND_CAMERA, gt, true, nil
}

// build_next_week_quads_scene returns the RTNW quad demo scene:
// five colored quads and a camera framing them.
build_next_week_quads_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
    volumes: []core.SceneVolume,
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

    return nil, result_quads[:], quad_camera, nil, false, nil
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
    volumes: []core.SceneVolume,
) {
    result := make([dynamic]core.SceneSphere)
    append(&result, core.SceneSphere{
        center        = {0, 2, 0},
        radius        = 2,
        material_kind = .Lambertian,
        albedo        = core.NoiseTexture{scale = 4},
    })
    return result[:], nil, TURBULENCE_CAMERA, core.NoiseTexture{scale = 4}, true, nil
}

cornell_box_walls :: proc(result_quads: ^[dynamic]raytrace.Quad) {
    white := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.73, 0.73, 0.73}},
    })
    green := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.12, 0.45, 0.15}},
    })
    red := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.65, 0.05, 0.05}},
    })
    
    // Left wall (green), right wall (red) per benchmark convention.
    append(result_quads, raytrace.make_quad(
        [3]f32{555, 0, 0},
        [3]f32{0, 555, 0},
        [3]f32{0, 0, 555},
        green,
    ))
    append(result_quads, raytrace.make_quad(
        [3]f32{0, 0, 0},
        [3]f32{0, 555, 0},
        [3]f32{0, 0, 555},
        red,
    ))
    // Room shell.
    append(result_quads, raytrace.make_quad(
        [3]f32{0, 0, 0},
        [3]f32{555, 0, 0},
        [3]f32{0, 0, 555},
        white,
    ))
    append(result_quads, raytrace.make_quad(
        [3]f32{555, 555, 555},
        [3]f32{-555, 0, 0},
        [3]f32{0, 0, -555},
        white,
    ))
    append(result_quads, raytrace.make_quad(
        [3]f32{0, 0, 555},
        [3]f32{555, 0, 0},
        [3]f32{0, 555, 0},
        white,
    ))
}

// cornell_box_boxes adds two inner boxes (as quads) with the given materials.
// Tall box: local (0,0,0)-(165,330,165), rotate_y 15°, translate (265,0,295).
// Short box: local (0,0,0)-(165,165,165), rotate_y -18°, translate (130,0,65).
cornell_box_boxes :: proc(result_quads: ^[dynamic]raytrace.Quad, material1: raytrace.material, material2: raytrace.material) {
    tr1 := raytrace.mat4_mul(
        raytrace.mat4_translate([3]f32{265, 0, 295}),
        raytrace.mat4_rotate_y(15.0 * math.PI / 180.0),
    )
    raytrace.append_box_transformed(
        result_quads,
        [3]f32{0, 0, 0},
        [3]f32{165, 330, 165},
        material1,
        tr1,
    )
    tr2 := raytrace.mat4_mul(
        raytrace.mat4_translate([3]f32{130, 0, 65}),
        raytrace.mat4_rotate_y(-18.0 * math.PI / 180.0),
    )
    raytrace.append_box_transformed(
        result_quads,
        [3]f32{0, 0, 0},
        [3]f32{165, 165, 165},
        material2,
        tr2,
    )
}

// Cornell Box: unit room [0,1]^3, area light on ceiling, and two inner boxes.
// No ground plane; only emitter contributes illumination.
build_cornell_box_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
    volumes: []core.SceneVolume,
) {
    result_quads := make([dynamic]raytrace.Quad)

    cornell_box_walls(&result_quads)

    // Ceiling area light.
    light_mat := raytrace.material(raytrace.diffuse_light{emit = {15, 15, 15}})
    append(&result_quads, raytrace.make_quad(
        [3]f32{343, 554, 332},
        [3]f32{-130, 0, 0},
        [3]f32{0, 0, -105},
        light_mat,
    ))

    white := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.73, 0.73, 0.73}},
    })

    cornell_box_boxes(&result_quads, white, white)

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

    return nil, result_quads[:], cornell_camera, nil, false, nil
}

// build_volume_smoke_scene returns Cornell box walls + light and two SceneVolumes (smoke boxes).
// No inner box quads — the volumes define the boxes and fog; load path builds ConstantMediums.
// Volumes use Cornell scale (room 0..555): same box layout as cornell_box_boxes (tall and short boxes).
// Returns an owned volumes slice so the caller can delete(volumes); both entries are always valid.
build_volume_smoke_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
    volumes: []core.SceneVolume,
) {
    result_quads := make([dynamic]raytrace.Quad)
    cornell_box_walls(&result_quads)

    // Ceiling area light.
    light_mat := raytrace.material(raytrace.diffuse_light{emit = {7, 7, 7}})
    append(&result_quads, raytrace.make_quad(
        [3]f32{113, 554, 127},
        [3]f32{330, 0, 0},
        [3]f32{0, 0, 305},
        light_mat,
    ))

    result_volumes := make([dynamic]core.SceneVolume)
    // Owned slice: caller must delete(volumes). Ensures both volumes are valid and scale is correct.
    append(&result_volumes, core.SceneVolume{
        box_min      = {0, 0, 0},
        box_max      = {165, 330, 165},
        rotate_y_deg = 15,
        translate    = {265, 0, 295},
        density      = 0.01,
        albedo       = {0, 0, 0},
    })
    append(&result_volumes, core.SceneVolume{
        box_min      = {0, 0, 0},
        box_max      = {165, 165, 165},
        rotate_y_deg = -18,
        translate    = {130, 0, 65},
        density      = 0.01,
        albedo       = {1, 1, 1},
    })

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

    return nil, result_quads[:], cornell_camera, nil, false, result_volumes[:]
}

// NEXT_WEEK_FINAL_CAMERA is the camera for "The Next Week Final" scene.
NEXT_WEEK_FINAL_CAMERA :: core.CameraParams{
    lookfrom      = {478, 278, -600},
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

// build_next_week_final_scene returns the complex final scene from "Ray Tracing: The Next Week".
// Features:
//   - Ground made of 400 boxes (20x20 grid) with random heights
//   - Ceiling area light
//   - Moving sphere (motion blur)
//   - Glass sphere (dielectric)
//   - Metal sphere
//   - Subsurface reflection sphere (volume inside dielectric)
//   - Global mist (thin volume covering everything)
//   - Earth texture sphere
//   - Perlin noise texture sphere
//   - Cluster of 1000 small white spheres with BVH and transform
//
// The scene is parameterized for different quality levels when used programmatically,
// but the example scene uses fixed settings for the full experience.
//
// Caller must delete the returned slices.
build_next_week_final_scene :: proc() -> (
    spheres: []core.SceneSphere,
    quads: []raytrace.Quad,
    camera: core.CameraParams,
    ground_texture: raytrace.Texture,
    include_ground: bool,
    volumes: []core.SceneVolume,
) {
    rng := util.create_thread_rng(42)

    result_quads := make([dynamic]raytrace.Quad)
    result_spheres := make([dynamic]core.SceneSphere)

    // Ground material: greenish (from RTNW final_scene)
    ground_mat := raytrace.material(raytrace.lambertian{
        albedo = raytrace.ConstantTexture{color = {0.48, 0.83, 0.53}},
    })

    // 1. Build ground from 20x20 boxes with random heights
    boxes_per_side := 20
    w := f32(100.0)
    for i in 0..<boxes_per_side {
        for j in 0..<boxes_per_side {
            x0 := -1000.0 + f32(i) * w
            z0 := -1000.0 + f32(j) * w
            y0 := f32(0.0)
            x1 := x0 + w
            // Random height between 1 and 101
            y1 := util.random_float_range(&rng, 1.0, 101.0)
            z1 := z0 + w

            // Append box as 6 quads
            raytrace.append_box(&result_quads, [3]f32{x0, y0, z0}, [3]f32{x1, y1, z1}, ground_mat)
        }
    }

    // 2. Ceiling area light
    light_mat := raytrace.material(raytrace.diffuse_light{emit = {7, 7, 7}})
    append(&result_quads, raytrace.make_quad(
        [3]f32{123, 554, 147},
        [3]f32{300, 0, 0},
        [3]f32{0, 0, 265},
        light_mat,
    ))

    // 3. Moving sphere (motion blur) - brownish Lambertian
    center1 := [3]f32{400, 400, 200}
    center2 := center1 + [3]f32{30, 0, 0}
    append(&result_spheres, core.SceneSphere{
        center        = center1,
        center1       = center2,
        radius        = 50,
        material_kind = .Lambertian,
        albedo        = core.ConstantTexture{color = {0.7, 0.3, 0.1}},
        is_moving     = true,
    })

    // 4. Glass sphere (dielectric)
    append(&result_spheres, core.SceneSphere{
        center        = {260, 150, 45},
        radius        = 50,
        material_kind = .Dielectric,
        ref_idx       = 1.5,
    })

    // 5. Metal sphere - bluish, high fuzz
    append(&result_spheres, core.SceneSphere{
        center        = {0, 150, 145},
        radius        = 50,
        material_kind = .Metallic,
        albedo        = core.ConstantTexture{color = {0.8, 0.8, 0.9}},
        fuzz          = 1.0,
    })

    // 6. Subsurface reflection sphere: volume inside a dielectric sphere
    // We add the boundary dielectric sphere as a regular sphere
    // and create a SceneVolume for the interior participating medium
    // The sphere is at (360, 150, 145) with radius 70
    append(&result_spheres, core.SceneSphere{
        center        = {360, 150, 145},
        radius        = 70,
        material_kind = .Dielectric,
        ref_idx       = 1.5,
    })

    // 7. Cluster of 1000 small white spheres
    // These will be added as a volume with transform in the volumes slice
    // For now, we create the SceneVolume that represents this cluster
    // The cluster is 1000 spheres of radius 10 in a box [0,165]^3, rotated 15deg, translated to (-100,270,395)

    // 8. Earth texture sphere and perlin noise sphere
    // These need to be added as SceneSpheres
    // Earth at (400, 200, 400), radius 100
    // Perlin sphere at (220, 280, 300), radius 80

    append(&result_spheres, core.SceneSphere{
        center        = {400, 200, 400},
        radius        = 100,
        material_kind = .Lambertian,
        albedo        = core.ImageTexture{path = "assets/textures/earthmap1k.jpg"},
        texture_kind  = .Image,
        image_path    = "assets/textures/earthmap1k.jpg",
    })

    append(&result_spheres, core.SceneSphere{
        center        = {220, 280, 300},
        radius        = 80,
        material_kind = .Lambertian,
        albedo        = core.NoiseTexture{scale = 0.2},
    })

    // Create volumes slice
    // Volume 0: Subsurface sphere interior (at 360, 150, 145, radius ~65 to fit inside dielectric)
    // Volume 1: Global mist (thin fog covering everything) - a huge box
    // Volume 2: Cluster of 1000 spheres (as a box volume with density representing the spheres)
    volumes_out := make([dynamic]core.SceneVolume)

    // Subsurface sphere volume - blue fog inside the dielectric sphere
    // Approximated as a box containing the sphere volume
    // The sphere is at (360, 150, 145) with radius 70
    // We create a box slightly smaller than the sphere
    append(&volumes_out, core.SceneVolume{
        box_min      = {360 - 65, 150 - 65, 145 - 65},
        box_max      = {360 + 65, 150 + 65, 145 + 65},
        rotate_y_deg = 0,
        translate    = {0, 0, 0},
        density      = 0.2,
        albedo       = {0.2, 0.4, 0.9},
    })

    // Global mist - a very thin volume covering a large area
    // This covers the entire scene with very low density
    append(&volumes_out, core.SceneVolume{
        box_min      = {-1000, -100, -1000},
        box_max      = {1000, 600, 1000},
        rotate_y_deg = 0,
        translate    = {0, 0, 0},
        density      = 0.0001,
        albedo       = {1, 1, 1},
    })

    // Cluster of 1000 small spheres represented as a volume
    // Box from (0,0,0) to (165,165,165), rotated 15deg, translated to (-100,270,395)
    // Using white material
    append(&volumes_out, core.SceneVolume{
        box_min      = {0, 0, 0},
        box_max      = {165, 165, 165},
        rotate_y_deg = 15,
        translate    = {-100, 270, 395},
        density      = 0.01,
        albedo       = {0.73, 0.73, 0.73},
    })

    return result_spheres[:], result_quads[:], NEXT_WEEK_FINAL_CAMERA, nil, false, volumes_out[:]
}