package main

import "core:fmt"
import "core:os"
import "core:strings"



main :: proc() {
    args := Args{}
    
    if !parse_args_with_short_flags(&args) {
        return
    }
    
    // Set defaults
    image_width := args.Width
    if image_width <= 0 {
        image_width = 800
    }
    
    image_height := args.Height
    if image_height <= 0 {
        // Calculate from aspect ratio if not provided
        image_height = int(f32(image_width) / (16.0 / 9.0))
    }
    
    samples_per_pixel := args.Samples
    if samples_per_pixel <= 0 {
        samples_per_pixel = 80
    }

    number_of_spheres := args.NumberOfSpheres
    if number_of_spheres <= 0 {
        number_of_spheres = 100
    }
    output_file := args.OutputFile
    if len(output_file) == 0 {
        output_file = "output.ppm"
    }

    test_mode := args.TestMode
    if test_mode {
        fmt.println("Running in test mode")
    }
    
    // Print configuration
    fmt.printf("Ray Tracer Configuration:\n")
    fmt.printf("  Image size: %dx%d pixels\n", image_width, image_height)
    fmt.printf("  Samples per pixel: %d\n", samples_per_pixel)
    fmt.printf("  Output file: %s\n\n", output_file)
    
    ray_trace_world(output_file, image_width, image_height, samples_per_pixel, number_of_spheres)
}