package main

import "core:fmt"
import "core:os"
import "RT_Weekend:core"
import "RT_Weekend:persistence"
import "RT_Weekend:editor"
import "RT_Weekend:raytrace"
import "RT_Weekend:util"

VERBOSE_OUTPUT :: #config(VERBOSE_OUTPUT, true)

main :: proc() {
    when util.TRACK_ALLOCATIONS {
        _track: util.Tracking_Allocator_State
        util.tracking_init(&_track, context.allocator)
        context.allocator = util.tracking_allocator(&_track)
        defer util.tracking_report_and_destroy(&_track)
    }

    args := util.Args{}

    if !util.parse_args_with_short_flags(&args) {
        return
    }

    image_width := args.Width
    if image_width <= 0 {
        image_width = 800
    }

    image_height := args.Height
    if image_height <= 0 {
        image_height = int(f32(image_width) / (16.0 / 9.0))
    }

    samples_per_pixel := args.Samples
    if samples_per_pixel <= 0 {
        samples_per_pixel = 10
    }

    number_of_spheres := args.NumberOfSpheres
    if number_of_spheres <= 0 {
        number_of_spheres = 10
    }

    thread_count := args.ThreadCount
    if thread_count <= 0 {
        thread_count = util.get_number_of_physical_cores()
        if thread_count <= 0 {
            thread_count = 1
        }
    }

    // Load config file if -config path given; override width/height/samples only when present and positive
    initial_editor: ^persistence.EditorLayout = nil
    initial_editor_view: ^persistence.EditorViewConfig = nil
    initial_presets: []persistence.LayoutPreset = nil
    if len(args.ConfigPath) > 0 {
        if loaded, ok := persistence.load_config(args.ConfigPath); ok {
            if loaded.width > 0 {
                image_width = loaded.width
            }
            if loaded.height > 0 {
                image_height = loaded.height
            }
            if loaded.samples_per_pixel > 0 {
                samples_per_pixel = loaded.samples_per_pixel
            }
            if loaded.editor != nil {
                initial_editor = loaded.editor
            }
            if loaded.editor_view != nil {
                initial_editor_view = loaded.editor_view
            }
            if loaded.presets != nil {
                initial_presets = loaded.presets
            }
        } else {
            fmt.fprintf(os.stderr, "Failed to load config: %s\n", args.ConfigPath)
        }
    }

    when VERBOSE_OUTPUT {
        fmt.printf("Ray Tracer Configuration:\n")
        fmt.printf("  Image size: %dx%d pixels\n", image_width, image_height)
        fmt.printf("  Samples per pixel: %d\n", samples_per_pixel)
        fmt.printf("  Threads: %d\n", thread_count)
        fmt.printf("  GPU mode: %v\n", args.UseGPU)
        util.print_system_info()
    }

    r_camera: ^raytrace.Camera
    r_world: [dynamic]raytrace.Object
    initial_volumes: [dynamic]core.SceneVolume = nil
    earth_img: ^raytrace.Texture_Image = nil

    if len(args.ScenePath) > 0 {
        if args.ScenePath == "earth" {
            earth_img = new(raytrace.Texture_Image)
            earth_img^ = raytrace.texture_image_init()
            if !raytrace.texture_image_load(earth_img, "assets/textures/earthmap1k.jpg") {
                fmt.fprintf(os.stderr, "Failed to load earth texture: assets/textures/earthmap1k.jpg\n")
                free(earth_img)
                return
            }
            when VERBOSE_OUTPUT {
                fmt.printf("[Main] Earth texture loaded: path=%q size=%dx%d\n",
                    "assets/textures/earthmap1k.jpg",
                    raytrace.texture_image_width(earth_img),
                    raytrace.texture_image_height(earth_img))
            }
            r_camera, r_world = raytrace.setup_earth_scene(image_width, image_height, samples_per_pixel, "assets/textures/earthmap1k.jpg", earth_img)
        } else {
            cam, w, vols, ok := persistence.load_scene(args.ScenePath, image_width, image_height, samples_per_pixel)
            if !ok {
                fmt.fprintf(os.stderr, "Warning: failed to load scene %s; using default scene (3 spheres).\n", args.ScenePath)
                r_camera, r_world = raytrace.setup_scene(image_width, image_height, samples_per_pixel, number_of_spheres)
            } else {
                r_camera = cam
                r_world = w
                initial_volumes = vols
            }
        }
    } else {
        r_camera = raytrace.make_camera(image_width, image_height, samples_per_pixel)
        r_world  = make([dynamic]raytrace.Object) // empty; edit view provides the scene
    }

    if len(args.SaveScenePath) > 0 {
        if !persistence.save_scene(args.SaveScenePath, r_camera, r_world) {
            fmt.fprintf(os.stderr, "Failed to save scene: %s\n", args.SaveScenePath)
        }
    }

    // Headless mode: -output/-o/-out given (or -headless flag) → render without window, save PNG.
    if len(args.OutputPath) > 0 || args.Headless {
        if len(args.OutputPath) == 0 {
            fmt.fprintf(os.stderr, "Error: -headless requires -output <path>\n")
            return
        }
        // Special test: "-scene test-rotation" exercises build_world_from_scene with editor-like camera + rotated sphere.
        if args.ScenePath == "test-rotation" {
            delete(r_world)
            free(r_camera)
            r_camera = raytrace.make_camera(image_width, image_height, samples_per_pixel)
            cam_params := core.CameraParams{
                lookfrom     = {8, 2, 3},
                lookat       = {0, 0, 0},
                vup          = {0, 1, 0},
                vfov         = 20,
                focus_dist   = 10,
                defocus_angle = 0.6,
                max_depth    = 20,
                background   = {1, 1, 1}, // white like editor default
            }
            raytrace.apply_scene_camera(r_camera, &cam_params)
            raytrace.init_camera(r_camera)
            // Editor default 3 spheres, second one (metallic blue at origin) has rotation added
            scene_spheres := []core.SceneSphere{
                {center = {-3, 0.5, 0}, center1 = {-3, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = core.ConstantTexture{color={0.8, 0.2, 0.2}}},
                {center = { 0, 0.5, 0}, center1 = { 0, 0.5, 0}, radius = 0.5, material_kind = .Metallic,   albedo = core.ConstantTexture{color={0.2, 0.2, 0.8}}, fuzz = 0.1, rotation_deg = {45, 0, 0}},
                {center = { 3, 0.5, 0}, center1 = { 3, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = core.ConstantTexture{color={0.2, 0.8, 0.2}}},
            }
            r_world = raytrace.build_world_from_scene(scene_spheres, raytrace.ConstantTexture{color = {0.5, 0.5, 0.5}}, nil, true)
            fmt.printf("[TestRot] world has %d objects (1 TransformedObject expected for metallic blue sphere)\n", len(r_world))
            for _wi in 0..<len(r_world) {
                #partial switch o in r_world[_wi] {
                case raytrace.Sphere:            fmt.printf("  [%d] Sphere center=%v r=%v\n", _wi, o.center, o.radius)
                case raytrace.Quad:              fmt.printf("  [%d] Quad\n", _wi)
                case raytrace.TransformedObject: fmt.printf("  [%d] TransformedObject transl=%v rot=%v bbox=(%v,%v)\n", _wi, o.translation, o.rotation_deg, [3]f32{o.bbox.x.min, o.bbox.y.min, o.bbox.z.min}, [3]f32{o.bbox.x.max, o.bbox.y.max, o.bbox.z.max})
                }
            }
        } else if len(args.ScenePath) == 0 {
            // No scene file: use procedural scene (same as editor default).
            raytrace.free_world_volumes(r_world)
            delete(r_world)
            free(r_camera)
            r_camera, r_world = raytrace.setup_scene(image_width, image_height, samples_per_pixel, number_of_spheres)
        }

        when VERBOSE_OUTPUT {
            fmt.printf("Headless render: %dx%d, %d spp, %d threads -> %s\n",
                image_width, image_height, samples_per_pixel, thread_count, args.OutputPath)
        }

        // GPU headless: without a GL context, gpu_backend_init will fail and
        // start_render_auto silently falls back to CPU — no extra handling needed.
        session := raytrace.start_render_auto(r_camera, r_world, thread_count, args.UseGPU)

        when VERBOSE_OUTPUT {
            last_pct := f32(-1.0)
            for {
                pct := raytrace.get_render_progress(session)
                if pct - last_pct >= 0.05 || pct >= 1.0 {
                    fmt.printf("\rProgress: %3.0f%%", pct * 100)
                    last_pct = pct
                }
                if pct >= 1.0 { break }
            }
            fmt.println("")
        } else {
            for raytrace.get_render_progress(session) < 1.0 {}
        }

        raytrace.finish_render(session)

        if !raytrace.write_buffer_to_png(&session.pixel_buffer, args.OutputPath, r_camera) {
            fmt.fprintf(os.stderr, "Failed to write PNG: %s\n", args.OutputPath)
        } else {
            when VERBOSE_OUTPUT {
                fmt.printf("Saved: %s\n", args.OutputPath)
            }
        }

        if len(args.ProfileOutputPath) > 0 {
            profile := raytrace.get_render_profile(session)
            if !raytrace.write_profile_json(args.ProfileOutputPath, profile) {
                fmt.fprintf(os.stderr, "Warning: failed to write profile: %s\n", args.ProfileOutputPath)
            }
        }

        raytrace.free_session(session)
        raytrace.free_world_volumes(r_world)
        delete(r_world)
        free(r_camera)
        if earth_img != nil {
            raytrace.texture_image_destroy(earth_img)
            free(earth_img)
        }
        return
    }

    editor.run_app(r_camera, r_world, thread_count, args.UseGPU, initial_editor, initial_editor_view, args.SaveConfigPath, initial_presets, initial_volumes)
    if initial_editor != nil {
        delete(initial_editor.panels)
        free(initial_editor)
    }
    if initial_editor_view != nil {
        free(initial_editor_view)
    }
    if initial_presets != nil {
        delete(initial_presets)
    }
    if earth_img != nil {
        raytrace.texture_image_destroy(earth_img)
        free(earth_img)
    }
}
