package main

import "core:fmt"

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
        samples_per_pixel = 10
    }

    number_of_spheres := args.NumberOfSpheres
    if number_of_spheres <= 0 {
        number_of_spheres = 10
    }
    output_file := args.OutputFile
    if len(output_file) == 0 {
        output_file = "output"
    }

    print_system_info()

    test_mode := args.TestMode
    // Get core counts
    physical_cores := get_number_of_physical_cores()
    logical_cores := get_number_of_logical_cores()
    
    // Create list of thread counts to test
    thread_counts := [dynamic]int{}
    append(&thread_counts, 1)
    append(&thread_counts, 2)
    append(&thread_counts, physical_cores)
    if logical_cores != physical_cores {
        append(&thread_counts, logical_cores)
    }

    if test_mode {
        fmt.println("Running in test mode")
        //4K resolution
        image_width = 3840*2
        image_height = 2160*2
        fmt.println("4K resolution")
        fmt.println("Samples per pixel: ", samples_per_pixel)
        fmt.println("Number of spheres: ", number_of_spheres)
        fmt.println("Output file: ", output_file)
        
        timer := start_timer()
        test_mode_func(output_file, image_width, image_height)
        stop_timer(&timer)
        fmt.println("Test mode completed in: ", get_elapsed_seconds(timer))
        return
    }
    
    // Print configuration
    fmt.printf("Ray Tracer Configuration:\n")
    fmt.printf("  Image size: %dx%d pixels\n", image_width, image_height)
    fmt.printf("  Samples per pixel: %d\n", samples_per_pixel)
    fmt.printf("  Output file: %s\n\n", output_file)
    
    ray_trace_world(output_file, image_width, image_height, samples_per_pixel, number_of_spheres)
}