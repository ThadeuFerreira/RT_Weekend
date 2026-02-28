package main

import "core:fmt"
import "core:os"
import "RT_Weekend:persistence"
import "RT_Weekend:editor"
import "RT_Weekend:raytrace"
import "RT_Weekend:util"

VERBOSE_OUTPUT :: #config(VERBOSE_OUTPUT, true)

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
    initial_editor: ^persistence.EditorLayout = nil
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

    if len(args.ScenePath) > 0 {
        cam, w, ok := persistence.load_scene(args.ScenePath, image_width, image_height, samples_per_pixel)
        if !ok {
            fmt.fprintf(os.stderr, "Failed to load scene: %s\n", args.ScenePath)
            return
        }
        r_camera = cam
        r_world = w
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
        // No scene file: use procedural scene (same as editor default).
        if len(args.ScenePath) == 0 {
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
        delete(r_world)
        free(r_camera)
        return
    }

    editor.run_app(r_camera, r_world, thread_count, args.UseGPU, initial_editor, args.SaveConfigPath, initial_presets)
    if initial_editor != nil {
        delete(initial_editor.panels)
        free(initial_editor)
    }
    if initial_presets != nil {
        delete(initial_presets)
    }
}
