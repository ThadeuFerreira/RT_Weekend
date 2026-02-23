package main

import "core:fmt"
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

    fmt.printf("Ray Tracer Configuration:\n")
    fmt.printf("  Image size: %dx%d pixels\n", image_width, image_height)
    fmt.printf("  Samples per pixel: %d\n", samples_per_pixel)
    fmt.printf("  Threads: %d\n", thread_count)

    util.print_system_info()

    camera, world := raytrace.setup_scene(image_width, image_height, samples_per_pixel, number_of_spheres)
    ui.run_app(camera, world, thread_count)
}
