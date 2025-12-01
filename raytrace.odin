package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:thread"
import "core:sync"
import "core:time"


// Pixel buffer for parallel test rendering
TestPixelBuffer :: struct {
    width: int,
    height: int,
    pixels: [][][3]f32,  // [height][width][3]f32
}

// Create a pixel buffer for test rendering
create_test_pixel_buffer :: proc(width: int, height: int) -> TestPixelBuffer {
    pixels := make([][][3]f32, height)
    for y in 0..<height {
        pixels[y] = make([][3]f32, width)
    }
    return TestPixelBuffer{width = width, height = height, pixels = pixels}
}

// Set a pixel color in the buffer
set_pixel :: proc(buffer: ^TestPixelBuffer, x: int, y: int, color: [3]f32) {
    if x >= 0 && x < buffer.width && y >= 0 && y < buffer.height {
        buffer.pixels[y][x] = color
    }
}

// Write pixel buffer to PPM file
write_buffer_to_ppm :: proc(buffer: ^TestPixelBuffer, file_name: string) {
    f, err := os.open(file_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0644)
    if err != os.ERROR_NONE {
        fmt.fprint(os.stderr, "Error opening file: %s\n", err)
        return
    }
    defer os.close(f)
    
    output_buffer := [8]byte{}
    fmt.fprint(f, "P3\n")
    fmt.fprint(f, strconv.write_int(output_buffer[:], i64(buffer.width), 10))
    fmt.fprint(f, " ")
    fmt.fprint(f, strconv.write_int(output_buffer[:], i64(buffer.height), 10))
    fmt.fprint(f, "\n255\n")
    
    sb := strings.Builder{}
    for y in 0..<buffer.height {
        for x in 0..<buffer.width {
            write_color(&sb, buffer.pixels[y][x])
        }
    }
    
    fmt.fprint(f, strings.to_string(sb))
}

// Thread work context for parallel rendering
TestRenderContext :: struct {
    thread_id: int,
    rng: ThreadRNG,
    buffer: ^TestPixelBuffer,
    start_y: int,
    end_y: int,
    image_width: int,
    image_height: int,
    camera: ^Camera,
}

ray_trace_world :: proc(output_file_name : string, image_width : int, image_height : int, samples_per_pixel : int, number_of_spheres : int, num_threads : int) {
    
    output := Output{image_file_name = fmt.tprintf("%s.ppm", output_file_name)}
    f, err := os.open(output.image_file_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0644)
    if err != os.ERROR_NONE {
        // handle error
        fmt.fprint(os.stderr, "Error opening file: %s\n", err)
        return
    }
    output.f = f

    world := make([dynamic]Object, 0, number_of_spheres)

    // Create RNG for scene generation
    scene_rng := create_thread_rng(54321)  // Fixed seed for deterministic scene generation

    ground_material := material(lambertian{[3]f32{0.5, 0.5, 0.5}})
    append(&world, Sphere{[3]f32{0, -1000, 0}, 1000, ground_material})

    num_spheres := 0
    for a in -11..<11 {
        for b in -11..<11 {
            choose_mat := random_float(&scene_rng)
            center := [3]f32{f32(a) + 0.9*random_float(&scene_rng), 0.2, f32(b) + 0.9*random_float(&scene_rng)}
            if vector_length(center - [3]f32{4, 0.2, 0}) > 0.9 {
                if choose_mat < 0.8 {
                    // diffuse
                    albedo := vector_random(&scene_rng) * vector_random(&scene_rng)
                    fmt.println(albedo)
                    material := material(lambertian{albedo})
                    append(&world, Sphere{center, 0.2, material})
                } else if choose_mat < 0.95 {
                    // metal
                    albedo := vector_random_range(&scene_rng, 0.5, 1)
                    fuzz := random_float_range(&scene_rng, 0, 0.5)
                    fmt.println(albedo)
                    material := material(metalic{albedo, fuzz})
                    append(&world, Sphere{center, 0.2, material})
                } else {
                    // glass
                    material := material(dieletric{1.5})
                    append(&world, Sphere{center, 0.2, material})
                }
                num_spheres += 1
            }
        }
        if num_spheres >= number_of_spheres {
            break
        }
    }

    for i in 0..<len(world) {

        obj := world[i]
        switch o in obj {
            case Sphere:
            mat := o.material
            //print pointer
            fmt.println(mat)
            fmt.println(&mat)
            case Cube:
                fmt.print("Cube")
        }
        
    }

    material1 := material(dieletric{1.5})
    append(&world, Sphere{[3]f32{0, 1, 0}, 1.0, material1})

    material2 := material(lambertian{[3]f32{0.4, 0.2, 0.1}})
    append(&world, Sphere{[3]f32{-4, 1, 0}, 1.0, material2})

    material3 := material(metalic{[3]f32{0.7, 0.6, 0.5}, 0.0})
    append(&world, Sphere{[3]f32{4, 1, 0}, 1.0, material3})

    cam := make_camera(image_width, image_height, samples_per_pixel)

    init_camera(cam)
    
    // Start timing
    timer := start_timer()
    fmt.println("Starting rendering...")
    
    // Render the scene using parallel rendering
    render_parallel(cam, output, world, num_threads)
    
    // Stop timing and display statistics
    stop_timer(&timer)
    print_timing_stats(timer, image_width, image_height, samples_per_pixel)
}


// Thread wrapper that captures context
thread_wrapper :: proc(ctx: ^TestRenderContext) {
    
}

// Package-level storage for thread context pointers (heap-allocated)
test_parallel_context_ptrs: []^TestRenderContext = nil
test_parallel_thread_counter: sync.Mutex
test_parallel_current_thread: int

//Generate a random noise texture and output it to file_name+test.ppm
test_mode_func :: proc(file_name : string, image_width : int, image_height : int) {
    output := Output{image_file_name = fmt.tprintf("%s_test.ppm", file_name)}
    f, err := os.open(output.image_file_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0644)
    if err != os.ERROR_NONE {
        // handle error
        fmt.fprint(os.stderr, "Error opening file: %s\n", err)
        return
    }
    output.f = f
    camera := make_camera(image_width, image_height, 1)

    buffer := [8]byte{}
    fmt.fprint(output.f, "P3\n")
    fmt.fprint(output.f, strconv.write_int(buffer[:], i64(camera.image_width),10))
    fmt.fprint(output.f, " ")
    fmt.fprint(output.f, strconv.write_int(buffer[:], i64(camera.image_height),10))
    fmt.fprint(output.f, "\n255\n")

    init_camera(camera)

    prng := create_thread_rng(54321)
    
    sb := strings.Builder{}
    for y in 0..<image_height {
        for x in 0..<image_width {
            random_r := random_float(&prng)
            random_g := random_float(&prng)
            random_b := random_float(&prng)
            color := [3]f32{random_r, random_g, random_b}
            pixel_color := camera.pixel_samples_scale * color
            write_color(&sb, pixel_color)
        }
    }
    
    fmt.fprint(output.f, strings.to_string(sb))
    os.close(output.f)
}