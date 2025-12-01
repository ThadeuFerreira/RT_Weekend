package main

import "core:fmt"
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
    if test_mode {
        fmt.println("Running in test mode")
        //4K resolution
        image_width = 3840*2
        image_height = 2160*2
        fmt.println("4K resolution")
        fmt.println("Samples per pixel: ", samples_per_pixel)
        fmt.println("Number of spheres: ", number_of_spheres)
        fmt.println("Output file: ", output_file)
        
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
        
        // Run tests with different thread counts
        timings := [dynamic]f64{}
        for num_threads in thread_counts {
            fmt.printf("\nTesting with %d core(s)...\n", num_threads)
            output_filename := fmt.tprintf("%s_test_%dcores.ppm", output_file, num_threads)
            
            timer := start_timer()
            test_mode_func_parallel(output_filename, image_width, image_height, num_threads)
            stop_timer(&timer)
            
            elapsed := get_elapsed_seconds(timer)
            append(&timings, elapsed)
            print_timing_stats(timer, image_width, image_height, 1)
        }
        
        // Print comparison summary
        separator := strings.repeat("=", 60)
        fmt.println()
        fmt.println(separator)
        fmt.println("Performance Comparison Summary:")
        fmt.println(separator)
        if len(timings) > 0 {
            baseline_time := timings[0]  // 1 core time
            for num_threads, i in thread_counts {
                if i < len(timings) {
                    elapsed := timings[i]
                    speedup := baseline_time / elapsed
                    fmt.printf("  %d core(s): %.2f s (%.2fx speedup vs 1 core)\n", num_threads, elapsed, speedup)
                }
            }
        }
        fmt.println(strings.repeat("=", 60))
        
        delete(thread_counts)
        delete(timings)
        return
    }
    
    // Print configuration
    fmt.printf("Ray Tracer Configuration:\n")
    fmt.printf("  Image size: %dx%d pixels\n", image_width, image_height)
    fmt.printf("  Samples per pixel: %d\n", samples_per_pixel)
    fmt.printf("  Output file: %s\n\n", output_file)
    
    ray_trace_world(output_file, image_width, image_height, samples_per_pixel, number_of_spheres)
}