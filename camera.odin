package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:thread"
import "core:sync"
import "core:time"

Camera :: struct{
    aspect_ratio : f32,
    image_width : int,
    image_height : int,
    focal_length : f32,
    viewport_height : f32,
    viewport_width : f32,
    center : [3]f32,
    viewport_u : [3]f32,
    viewport_v : [3]f32,
    pixel_delta_u : [3]f32,
    pixel_delta_v : [3]f32,
    u : [3]f32,
    v : [3]f32,
    w : [3]f32,
    viewport_upper_left : [3]f32,
    pixel00_loc : [3]f32,

    samples_per_pixel : int,
    pixel_samples_scale : f32,

    
    vfov : f32, // Point camera is looking from
    lookfrom : [3]f32,// Vertical view angle (field of view)
    lookat : [3]f32,// Point camera is looking at
    vup : [3]f32,// Camera-relative "up" direction
    
    // double defocus_angle = 0;  // Variation angle of rays through each pixel
    // double focus_dist = 10;    // Distance from camera lookfrom point to plane of perfect focus
    defocus_angle : f32,
    focus_dist : f32,

    defocus_disk_u : [3]f32,
    defocus_disk_v : [3]f32,

    max_depth : int,
}

Output :: struct{
    image_file_name : string,
    f : os.Handle,
}

// Tile structure for parallel rendering
Tile :: struct {
    start_x, start_y: int,
    end_x, end_y: int,
}

// Atomic work queue for dynamic tile distribution
TileWorkQueue :: struct {
    tiles: []Tile,
    next_tile: i32,       // Atomic counter
    completed: i32,       // Atomic counter for progress
    total_tiles: int,
}

make_camera :: proc(image_width : int, image_height : int, samples_per_pixel : int) -> ^Camera {

    cam := new(Camera)
    // Use provided parameters
    cam.aspect_ratio = f32(image_width) / f32(image_height)
    cam.image_width = image_width
    cam.image_height = image_height
    cam.samples_per_pixel = samples_per_pixel
    cam.pixel_samples_scale = 1.0 / f32(samples_per_pixel)
    cam.max_depth = 20

    cam.vfov = 20.0
    cam.lookfrom = [3]f32{13, 2, 3}
    cam.lookat = [3]f32{0, 0, 0}
    cam.vup = [3]f32{0, 1, 0}

    cam.defocus_angle = 0.6
    cam.focus_dist = 10.0
    
    
    return cam
}

init_camera :: proc(c :^Camera){

    c.center = c.lookfrom

    theta := degrees_to_radians(c.vfov)
    h := math.tan(theta/2)
    c.viewport_height = 2*h*c.focus_dist
    c.viewport_width = c.viewport_height*(f32(c.image_width) / f32(c.image_height))

    // Calculate the u,v,w unit basis vectors for the camera coordinate frame.
    c.w = unit_vector(c.lookfrom - c.lookat)
    c.u = unit_vector(cross(c.vup, c.w))
    c.v = cross(c.w, c.u)

    // Calculate the vectors across the horizontal and down the vertical viewport edges.
    c.viewport_u = c.viewport_width * c.u
    c.viewport_v = -c.viewport_height * c.v
    
    // Calculate the horizontal and vertical delta vectors from pixel to pixel.
    c.pixel_delta_u = c.viewport_u / f32(c.image_width)
    c.pixel_delta_v = c.viewport_v / f32(c.image_height)

    // Calculate the location of the upper left pixel.  
    c.viewport_upper_left = c.center - (c.focus_dist * c.w) - 0.5*(c.viewport_u + c.viewport_v)
    c.pixel00_loc = c.viewport_upper_left + 0.5*(c.pixel_delta_u + c.pixel_delta_v)

    // Calculate the defocus disk vectors
    defocus_radius := c.focus_dist*math.tan(degrees_to_radians(c.defocus_angle*0.5))
    c.defocus_disk_u = defocus_radius * c.u
    c.defocus_disk_v = defocus_radius * c.v
}

render :: proc(camera : ^Camera, output : Output, world : [dynamic]Object){
    f := output.f
    buffer := [8]byte{}
    fmt.fprint(f, "P3\n")
    fmt.fprint(f, strconv.write_int(buffer[:], i64(camera.image_width), 10))
    fmt.fprint(f, " ")
    fmt.fprint(f, strconv.write_int(buffer[:], i64(camera.image_height), 10))
    fmt.fprint(f, "\n255\n")

    // Create RNG instance for rendering
    rng := create_thread_rng(12345)  // Fixed seed for deterministic results

    sb := strings.Builder{}
    for j in 0..<camera.image_height {
        //Progress bar
        v := j*20/camera.image_height
        print_progress_bar(v, 20)
        for i in 0..<camera.image_width {
            pixel_color := [3]f32{0, 0, 0}
            for s in 0..<camera.samples_per_pixel {
                r := get_ray(camera, f32(i),f32(j), &rng)
                pixel_color += ray_color(r, camera.max_depth, world, &rng)
            }
            pixel_color = pixel_color * camera.pixel_samples_scale
            write_color(&sb, pixel_color)
        }
    }


    fmt.fprint(f, strings.to_string(sb))
    os.close(f)
}

// Parallel rendering function
render_parallel :: proc(camera: ^Camera, output: Output, world: [dynamic]Object, num_threads: int) {
    // Create pixel buffer
    pixel_buffer := create_test_pixel_buffer(camera.image_width, camera.image_height)
    
    // Generate tiles (32x32 pixels per tile)
    tile_size := 32
    tiles := generate_tiles(camera.image_width, camera.image_height, tile_size)
    
    // Create work queue
    work_queue := TileWorkQueue{
        tiles = tiles,
        next_tile = 0,
        completed = 0,
        total_tiles = len(tiles),
    }
    
    // Create worker thread contexts
    contexts := make([]ParallelRenderContext, num_threads)
    threads := make([]^thread.Thread, num_threads)
    
    base_seed: u64 = 12345
    
    for i in 0..<num_threads {
        contexts[i] = ParallelRenderContext{
            camera = camera,
            world = world,  // Copy world array (read-only, safe to copy)
            buffer = &pixel_buffer,
            work_queue = &work_queue,
            thread_id = i,
            rng_seed = base_seed,
        }
    }
    
    // Spawn worker threads
    // Allocate contexts on heap so threads can access them
    heap_contexts := make([]^ParallelRenderContext, num_threads)
    for i in 0..<num_threads {
        heap_contexts[i] = new(ParallelRenderContext)
        heap_contexts[i]^ = contexts[i]
    }
    
    // Set global context array for threads to access
    parallel_render_contexts = heap_contexts
    parallel_thread_counter = 0
    
    for i in 0..<num_threads {
        threads[i] = thread.create(worker_thread)
        thread.start(threads[i])
    }
    
    // Wait for completion with progress updates
    total_tiles := work_queue.total_tiles
    last_progress := 0
    
    for {
        completed := sync.atomic_load(&work_queue.completed)
        
        // Update progress bar
        if total_tiles > 0 {
            progress := (int(completed) * 20) / total_tiles
            if progress != last_progress {
                print_progress_bar(progress, 20)
                last_progress = progress
            }
        }
        
        if int(completed) >= total_tiles {
            break
        }
        
        // Small sleep to avoid busy-waiting
        time.sleep(time.Millisecond * 50)
    }
    
    // Wait for all threads to finish
    for i in 0..<num_threads {
        thread.join(threads[i])
        thread.destroy(threads[i])
    }
    
    // Clean up heap-allocated contexts
    for i in 0..<num_threads {
        free(heap_contexts[i])
    }
    delete(heap_contexts)
    parallel_render_contexts = nil
    
    // Write buffer to file
    write_buffer_to_ppm(&pixel_buffer, output.image_file_name)
    os.close(output.f)
}

get_ray :: proc(camera : ^Camera, u : f32, v : f32, rng: ^ThreadRNG) -> ray {
    // Construct a camera ray originating from the defocus disk and directed at a randomly
    // sampled point around the pixel location i, j.
    offset := sample_square(rng)
    pixel_sample := camera.pixel00_loc + (u+offset[0])*camera.pixel_delta_u + (v + offset[1])*camera.pixel_delta_v

    ray_origin := (camera.defocus_angle <= 0)? camera.center : defocus_disk_sample(camera, rng)
    ray_direction := pixel_sample - ray_origin

    return ray{ray_origin, ray_direction}
}

defocus_disk_sample :: proc(c : ^Camera, rng: ^ThreadRNG) -> [3]f32 {
    p := vector_random_in_unit_disk(rng)
    return c.center +(p[0]*c.defocus_disk_u) + (p[1]*c.defocus_disk_v)
}

sample_square :: proc(rng: ^ThreadRNG) -> [3]f32 {
    return [3]f32{random_float(rng) -0.5, random_float(rng) -0.5, 0}
}

// Parallel render context for worker threads
ParallelRenderContext :: struct {
    camera: ^Camera,
    world: [dynamic]Object,  // Copy of world (read-only)
    buffer: ^TestPixelBuffer,
    work_queue: ^TileWorkQueue,
    thread_id: int,
    rng_seed: u64,
}

// Generate tiles for parallel rendering
generate_tiles :: proc(image_width: int, image_height: int, tile_size: int) -> []Tile {
    tiles := [dynamic]Tile{}
    
    y := 0
    for y < image_height {
        x := 0
        for x < image_width {
            start_x := x
            start_y := y
            end_x := min(start_x + tile_size, image_width)
            end_y := min(start_y + tile_size, image_height)
            
            append(&tiles, Tile{start_x = start_x, start_y = start_y, end_x = end_x, end_y = end_y})
            
            x = end_x  // Skip to next tile
        }
        y += tile_size  // Skip to next row of tiles
    }
    
    return tiles[:]
}

// Render a single tile to the pixel buffer
render_tile :: proc(ctx: ^ParallelRenderContext, tile: Tile) {
    camera := ctx.camera
    world := ctx.world
    buffer := ctx.buffer
    
    // Create per-thread RNG with unique seed
    rng := create_thread_rng(ctx.rng_seed + u64(ctx.thread_id * 1000000))
    
    // Render all pixels in this tile
    for y in tile.start_y..<tile.end_y {
        for x in tile.start_x..<tile.end_x {
            pixel_color := [3]f32{0, 0, 0}
            for s in 0..<camera.samples_per_pixel {
                r := get_ray(camera, f32(x), f32(y), &rng)
                pixel_color += ray_color(r, camera.max_depth, world, &rng)
            }
            pixel_color = pixel_color * camera.pixel_samples_scale
            set_pixel(buffer, x, y, pixel_color)
        }
    }
}

// Package-level storage for parallel render contexts (used during parallel rendering)
parallel_render_contexts: []^ParallelRenderContext = nil
parallel_thread_counter: i32 = 0

// Worker thread function
worker_thread :: proc(t: ^thread.Thread) {
    // Get thread index from atomic counter
    // atomic_add returns the value BEFORE the addition, so we use it directly
    // First thread: counter=0, atomic_add returns 0, counter becomes 1, index=0 ✓
    // Second thread: counter=1, atomic_add returns 1, counter becomes 2, index=1 ✓
    thread_index := int(sync.atomic_add(&parallel_thread_counter, 1))
    
    // Bounds check (should never fail, but safety first)
    if thread_index < 0 || thread_index >= len(parallel_render_contexts) {
        fmt.fprintf(os.stderr, "ERROR: Invalid thread index %d (max: %d)\n", thread_index, len(parallel_render_contexts))
        return
    }
    
    // Access context from shared array
    ctx := parallel_render_contexts[thread_index]
    
    for {
        // Atomically fetch next tile index
        tile_index := sync.atomic_add(&ctx.work_queue.next_tile, 1)
        
        if tile_index >= i32(ctx.work_queue.total_tiles) {
            break  // No more work
        }
        
        // Get the tile
        tile := ctx.work_queue.tiles[tile_index]
        
        // Render the tile
        render_tile(ctx, tile)
        
        // Atomically increment completed counter
        sync.atomic_add(&ctx.work_queue.completed, 1)
    }
}