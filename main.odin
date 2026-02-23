package main

import "core:fmt"
import "core:os"
import "RT_Weekend:util"
import "RT_Weekend:raytrace"
import "RT_Weekend:ui"

main :: proc() {
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
    initial_editor: ^util.EditorLayout = nil
    if len(args.ConfigPath) > 0 {
        if loaded, ok := util.load_config(args.ConfigPath); ok {
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
        } else {
            fmt.fprintf(os.stderr, "Failed to load config: %s\n", args.ConfigPath)
        }
    }

    fmt.printf("Ray Tracer Configuration:\n")
    fmt.printf("  Image size: %dx%d pixels\n", image_width, image_height)
    fmt.printf("  Samples per pixel: %d\n", samples_per_pixel)
    fmt.printf("  Threads: %d\n", thread_count)

    util.print_system_info()

    camera: ^raytrace.Camera
    world: [dynamic]raytrace.Object

    if len(args.ScenePath) > 0 {
        cam, w, ok := raytrace.load_scene(args.ScenePath, image_width, image_height, samples_per_pixel)
        if !ok {
            fmt.fprintf(os.stderr, "Failed to load scene: %s\n", args.ScenePath)
            return
        }
        camera = cam
        world = w
    } else {
        camera, world = raytrace.setup_scene(image_width, image_height, samples_per_pixel, number_of_spheres)
    }

    if len(args.SaveScenePath) > 0 {
        if !raytrace.save_scene(args.SaveScenePath, camera, world) {
            fmt.fprintf(os.stderr, "Failed to save scene: %s\n", args.SaveScenePath)
        }
    }

    ui.run_app(camera, world, thread_count, initial_editor, args.SaveConfigPath)
}
