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

// Thread work context for parallel test rendering
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

ray_trace_world :: proc(output_file_name : string, image_width : int, image_height : int, samples_per_pixel : int, number_of_spheres : int) {
    
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
    
    // Render the scene
    render(cam, output, world)
    
    // Stop timing and display statistics
    stop_timer(&timer)
    print_timing_stats(timer, image_width, image_height, samples_per_pixel)
}



// Worker thread function for parallel test rendering
test_worker_thread :: proc(ctx: ^TestRenderContext) {
    timer := start_timer()
    if ctx == nil {
        fmt.fprintf(os.stderr, "[Thread ?] ERROR: ctx is nil\n")
        return
    }
    
    if ctx.buffer == nil {
        fmt.fprintf(os.stderr, "[Thread %d] ERROR: ctx.buffer is nil\n", ctx.thread_id)
        return
    }
    
    // Ensure bounds are valid
    start_y := ctx.start_y
    end_y := ctx.end_y

    if start_y < 0 {
        start_y = 0
    }
    if end_y > ctx.buffer.height {
        end_y = ctx.buffer.height
    }
    if end_y > ctx.image_height {
        end_y = ctx.image_height
    }
    
    // Render assigned row range
    for y in start_y..<end_y {
        for x in 0..<ctx.image_width {
            if x >= ctx.buffer.width {
                break
            }
            random_r := random_float(&ctx.rng)
            random_g := random_float(&ctx.rng)
            random_b := random_float(&ctx.rng)
            color := [3]f32{random_r, random_g, random_b}
            pixel_color := ctx.camera.pixel_samples_scale * color
            set_pixel(ctx.buffer, x, y, pixel_color)
        }
    }
    //add a delay of 1 second to test if there are any performance issues
    // time.sleep(1 * 1_000_000_000)
    stop_timer(&timer)
    fmt.println("Worker thread: ", ctx.thread_id, " completed in: ", get_elapsed_seconds(timer))
}

// Thread wrapper that captures context
thread_wrapper :: proc(ctx: ^TestRenderContext) {
    test_worker_thread(ctx)
}

// Package-level storage for thread context pointers (heap-allocated)
test_parallel_context_ptrs: []^TestRenderContext = nil
test_parallel_thread_counter: sync.Mutex
test_parallel_current_thread: int

// Worker that gets its index from mutex-protected counter
parallel_test_worker :: proc(t: ^thread.Thread) {
    sync.mutex_lock(&test_parallel_thread_counter)
    thread_id := test_parallel_current_thread
    test_parallel_current_thread += 1
    sync.mutex_unlock(&test_parallel_thread_counter)
    
    // Bounds check before accessing array
    if test_parallel_context_ptrs == nil {
        fmt.fprintf(os.stderr, "[Worker %d] ERROR: test_parallel_context_ptrs is nil\n", thread_id)
        return
    }
    
    if thread_id < 0 {
        fmt.fprintf(os.stderr, "[Worker %d] ERROR: thread_id is negative\n", thread_id)
        return
    }
    
    if thread_id >= len(test_parallel_context_ptrs) {
        fmt.fprintf(os.stderr, "[Worker %d] ERROR: thread_id %d >= len %d\n", thread_id, thread_id, len(test_parallel_context_ptrs))
        return
    }
    
    ctx_ptr := test_parallel_context_ptrs[thread_id]
    
    if ctx_ptr == nil {
        fmt.fprintf(os.stderr, "[Worker %d] ERROR: ctx_ptr is nil\n", thread_id)
        return
    }
    
    test_worker_thread(ctx_ptr)
}

// Parallel version of test mode function
test_mode_func_parallel :: proc(file_name: string, image_width: int, image_height: int, num_threads: int) {
    // Safety checks
    if num_threads <= 0 {
        fmt.fprintf(os.stderr, "Error: num_threads must be > 0, got %d\n", num_threads)
        return
    }
    if image_width <= 0 || image_height <= 0 {
        fmt.fprintf(os.stderr, "Error: Invalid image dimensions: %dx%d\n", image_width, image_height)
        return
    }
    
    // Create camera
    camera := make_camera(image_width, image_height, 1)
    init_camera(camera)
    
    // Create pixel buffer
    pixel_buffer := create_test_pixel_buffer(image_width, image_height)
    
    // Calculate rows per thread
    rows_per_thread := image_height / num_threads
    remainder_rows := image_height % num_threads
    
    // Create thread contexts (allocate on heap to persist across thread lifetime)
    context_ptrs := make([]^TestRenderContext, num_threads)
    threads := make([dynamic]^thread.Thread, 0, num_threads)
    
    // Distribute work among threads
    current_y := 0
    for thread_id in 0..<num_threads {
        start_y := current_y
        // Distribute remainder rows to first threads
        rows_for_this_thread := rows_per_thread
        if thread_id < remainder_rows {
            rows_for_this_thread += 1
        }
        end_y := start_y + rows_for_this_thread
        
        // Ensure end_y doesn't exceed image_height
        if end_y > image_height {
            end_y = image_height
        }
        
        // Create RNG with unique seed for this thread
        rng_seed := u64(thread_id * 1000 + 54321)
        thread_rng := create_thread_rng(rng_seed)
        
        // Allocate context on heap
        ctx := new(TestRenderContext)
        ctx^ = TestRenderContext{
            thread_id = thread_id,
            rng = thread_rng,
            buffer = &pixel_buffer,
            start_y = start_y,
            end_y = end_y,
            image_width = image_width,
            image_height = image_height,
            camera = camera,
        }
        context_ptrs[thread_id] = ctx
        
        current_y = end_y
    }
    
    // Store context pointers in package-level variable
    test_parallel_context_ptrs = context_ptrs
    
    // Reset counter
    sync.mutex_lock(&test_parallel_thread_counter)
    test_parallel_current_thread = 0
    sync.mutex_unlock(&test_parallel_thread_counter)
    
    // Launch threads
    for i in 0..<num_threads {
        t := thread.create(parallel_test_worker)
        thread.start(t)
        append(&threads, t)
    }

    // Wait for all threads to complete
    for t in threads {
        thread.join(t)
        thread.destroy(t)
    }
    
    // Write pixel buffer to file
    write_buffer_to_ppm(&pixel_buffer, file_name)
    
    // Clear package-level variable before cleanup
    test_parallel_context_ptrs = nil
    
    // Cleanup - free allocated contexts
    for ctx_ptr in context_ptrs {
        free(ctx_ptr)
    }
    delete(context_ptrs)
    delete(threads)
    free(camera)
}

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