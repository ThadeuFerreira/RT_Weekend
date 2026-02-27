package raytrace

import "core:fmt"
import "core:math"
import "core:strings"
import "core:thread"
import "core:sync"
import "core:time"
import "RT_Weekend:core"
import "RT_Weekend:util"

degrees_to_radians :: proc(degrees: f32) -> f32 {
    return degrees * (math.PI / 180.0)
}

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

    vfov : f32,
    lookfrom : [3]f32,
    lookat : [3]f32,
    vup : [3]f32,

    defocus_angle : f32,
    focus_dist : f32,

    defocus_disk_u : [3]f32,
    defocus_disk_v : [3]f32,

    max_depth : int,
}

Tile :: struct {
    start_x, start_y: int,
    end_x, end_y: int,
}

TileWorkQueue :: struct {
    tiles: []Tile,
    next_tile: i32,
    completed: i32,
    total_tiles: int,
}

ParallelRenderContext :: struct {
    camera:            ^Camera,
    world:             [dynamic]Object,
    buffer:            ^TestPixelBuffer,
    work_queue:        ^TileWorkQueue,
    thread_id:         int,
    rng:               util.ThreadRNG,
    bvh_root:          ^BVHNode,
    // Linear BVH: flat array used by bvh_hit_linear (Step 1).
    // Workers use this when non-nil (faster, cache-friendly, GPU-uploadable).
    linear_bvh:        []LinearBVHNode,
    breakdown:         ^ThreadRenderingBreakdown,
    thread_time:       ^f64,
    thread_tile_count: ^int,
}

RenderSession :: struct {
    camera:                      ^Camera,
    pixel_buffer:                TestPixelBuffer,
    work_queue:                  TileWorkQueue,
    threads:                     []^thread.Thread,
    heap_contexts:               []^ParallelRenderContext,
    bvh_root:                    ^BVHNode,
    // Flat linear BVH shared across all worker threads (read-only after build).
    linear_bvh:                  []LinearBVHNode,
    timing:                      ParallelTimingBreakdown,
    thread_tile_times:           [dynamic]f64,
    thread_tile_counts:          [dynamic]int,
    thread_rendering_breakdowns: [dynamic]ThreadRenderingBreakdown,
    num_threads:                 int,
    start_time:                  time.Time,
    // GPU renderer — nil when using the CPU path.
    gpu_renderer:                ^GpuRenderer,
    use_gpu:                     bool,
    last_profile:                RenderProfileSummary,
}

// Default camera
// If no scene is loaded, the camera is at {8, 2, 3} with this configuration
make_camera :: proc(image_width : int, image_height : int, samples_per_pixel : int) -> ^Camera {

    cam := new(Camera)
    cam.aspect_ratio = f32(image_width) / f32(image_height)
    cam.image_width = image_width
    cam.image_height = image_height
    cam.samples_per_pixel = samples_per_pixel
    cam.pixel_samples_scale = 1.0 / f32(samples_per_pixel)
    cam.max_depth = 20

    cam.vfov = 20.0
    cam.lookfrom = [3]f32{8, 2, 3}
    cam.lookat = [3]f32{0, 0, 0}
    cam.vup = [3]f32{0, 1, 0}

    cam.defocus_angle = 0.6
    cam.focus_dist = 10.0

    return cam
}

// apply_scene_camera copies shared camera params into the raytrace Camera. Call init_camera(cam) after this.
apply_scene_camera :: proc(cam: ^Camera, params: ^core.CameraParams) {
    cam.lookfrom      = params.lookfrom
    cam.lookat        = params.lookat
    cam.vup           = params.vup
    cam.vfov          = params.vfov
    cam.defocus_angle = params.defocus_angle
    cam.focus_dist    = params.focus_dist
    cam.max_depth     = params.max_depth
}

// copy_camera_to_scene_params fills shared camera params from a raytrace Camera (e.g. at startup).
copy_camera_to_scene_params :: proc(params: ^core.CameraParams, cam: ^Camera) {
    params.lookfrom      = cam.lookfrom
    params.lookat        = cam.lookat
    params.vup           = cam.vup
    params.vfov          = cam.vfov
    params.defocus_angle = cam.defocus_angle
    params.focus_dist    = cam.focus_dist
    params.max_depth     = cam.max_depth
}

init_camera :: proc(c :^Camera){

    c.center = c.lookfrom

    theta := degrees_to_radians(c.vfov)
    h := math.tan(theta/2)
    c.viewport_height = 2*h*c.focus_dist
    c.viewport_width = c.viewport_height*(f32(c.image_width) / f32(c.image_height))

    c.w = unit_vector(c.lookfrom - c.lookat)
    c.u = unit_vector(cross(c.vup, c.w))
    c.v = cross(c.w, c.u)

    c.viewport_u = c.viewport_width * c.u
    c.viewport_v = -c.viewport_height * c.v

    c.pixel_delta_u = c.viewport_u / f32(c.image_width)
    c.pixel_delta_v = c.viewport_v / f32(c.image_height)

    c.viewport_upper_left = c.center - (c.focus_dist * c.w) - 0.5*(c.viewport_u + c.viewport_v)
    c.pixel00_loc = c.viewport_upper_left + 0.5*(c.pixel_delta_u + c.pixel_delta_v)

    defocus_radius := c.focus_dist*math.tan(degrees_to_radians(c.defocus_angle*0.5))
    c.defocus_disk_u = defocus_radius * c.u
    c.defocus_disk_v = defocus_radius * c.v
}

get_ray :: proc(camera : ^Camera, u : f32, v : f32, rng: ^util.ThreadRNG) -> ray {
    offset := sample_square(rng)
    pixel_sample := camera.pixel00_loc + (u+offset[0])*camera.pixel_delta_u + (v + offset[1])*camera.pixel_delta_v

    ray_origin := (camera.defocus_angle <= 0)? camera.center : defocus_disk_sample(camera, rng)
    ray_direction := pixel_sample - ray_origin

    return ray{ray_origin, ray_direction}
}

// pixel_to_ray returns a deterministic ray through the center of pixel (px, py).
// No antialiasing jitter, no depth-of-field. Intended for mouse picking only.
pixel_to_ray :: proc(camera: ^Camera, px, py: f32) -> ray {
    pixel_world := camera.pixel00_loc +
                   px * camera.pixel_delta_u +
                   py * camera.pixel_delta_v
    return ray{camera.center, pixel_world - camera.center}
}

defocus_disk_sample :: proc(c : ^Camera, rng: ^util.ThreadRNG) -> [3]f32 {
    p := vector_random_in_unit_disk(rng)
    return c.center +(p[0]*c.defocus_disk_u) + (p[1]*c.defocus_disk_v)
}

sample_square :: proc(rng: ^util.ThreadRNG) -> [3]f32 {
    return [3]f32{util.random_float(rng) -0.5, util.random_float(rng) -0.5, 0}
}

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

            x = end_x
        }
        y += tile_size
    }

    return tiles[:]
}

render_tile :: proc(ctx: ^ParallelRenderContext, tile: Tile) {
    camera := ctx.camera
    world := ctx.world
    buffer := ctx.buffer
    rng := &ctx.rng

    thread_breakdown := ctx.breakdown

    for y in tile.start_y..<tile.end_y {
        for x in tile.start_x..<tile.end_x {
            {
                pixel_setup_scope := PROFILE_SCOPE(&thread_breakdown.pixel_setup_time)
                defer PROFILE_SCOPE_END(pixel_setup_scope)

                pixel_color := [3]f32{0, 0, 0}

                for s in 0..<camera.samples_per_pixel {
                    r: ray
                    {
                        get_ray_scope := PROFILE_SCOPE(&thread_breakdown.get_ray_time)
                        defer PROFILE_SCOPE_END(get_ray_scope)
                        r = get_ray(camera, f32(x), f32(y), rng)
                        thread_breakdown.total_rays += 1
                    }

                    color := ray_color_linear(r, camera.max_depth, world, rng, thread_breakdown, ctx.bvh_root, ctx.linear_bvh)

                    pixel_color += color
                    thread_breakdown.total_samples += 1
                }

                set_pixel(buffer, x, y, pixel_color)
            }
        }
    }
}

worker_thread :: proc(t: ^thread.Thread) {
    ctx := (^ParallelRenderContext)(t.data)

    thread_start := time.now()
    tiles_rendered := 0

    for {
        tile_index := sync.atomic_add(&ctx.work_queue.next_tile, 1)
        if tile_index >= i32(ctx.work_queue.total_tiles) {
            break
        }

        tile := ctx.work_queue.tiles[tile_index]
        render_tile(ctx, tile)
        tiles_rendered += 1

        sync.atomic_add(&ctx.work_queue.completed, 1)
    }

    thread_end := time.now()
    thread_elapsed := time.diff(thread_start, thread_end)
    thread_seconds := time.duration_seconds(thread_elapsed)

    if ctx.thread_time != nil {
        ctx.thread_time^ = thread_seconds
    }
    if ctx.thread_tile_count != nil {
        ctx.thread_tile_count^ = tiles_rendered
    }
}

start_render :: proc(camera: ^Camera, world: [dynamic]Object, num_threads: int) -> ^RenderSession {
    session := new(RenderSession)
    session.camera = camera
    session.num_threads = num_threads
    session.start_time = time.now()

    session.timing = start_parallel_timing()

    session.timing.buffer_creation = start_timer()
    session.pixel_buffer = create_test_pixel_buffer(camera.image_width, camera.image_height)
    stop_timer(&session.timing.buffer_creation)

    session.timing.tile_generation = start_timer()
    tile_size := 32
    tiles := generate_tiles(camera.image_width, camera.image_height, tile_size)
    stop_timer(&session.timing.tile_generation)

    session.work_queue = TileWorkQueue{
        tiles      = tiles,
        next_tile  = 0,
        completed  = 0,
        total_tiles = len(tiles),
    }

    session.timing.bvh_construction = start_timer()
    world_slice := world[:]
    session.bvh_root = build_bvh(world_slice)
    // Build the flat linear BVH from the recursive tree.
    // Workers use bvh_hit_linear (iterative) instead of bvh_hit (recursive).
    session.linear_bvh = flatten_bvh(session.bvh_root, world_slice)
    stop_timer(&session.timing.bvh_construction)

    session.timing.context_setup = start_timer()
    session.threads       = make([]^thread.Thread, num_threads)
    session.heap_contexts = make([]^ParallelRenderContext, num_threads)

    session.thread_tile_times           = make([dynamic]f64, num_threads)
    session.thread_tile_counts          = make([dynamic]int, num_threads)
    session.thread_rendering_breakdowns = make([dynamic]ThreadRenderingBreakdown, num_threads)

    base_seed: u64 = 12345
    for i in 0..<num_threads {
        ctx := new(ParallelRenderContext)
        ctx^ = ParallelRenderContext{
            camera            = camera,
            world             = world,
            buffer            = &session.pixel_buffer,
            work_queue        = &session.work_queue,
            thread_id         = i,
            rng               = util.create_thread_rng(base_seed + u64(i)),
            bvh_root          = session.bvh_root,
            linear_bvh        = session.linear_bvh,
            breakdown         = &session.thread_rendering_breakdowns[i],
            thread_time       = &session.thread_tile_times[i],
            thread_tile_count = &session.thread_tile_counts[i],
        }
        session.heap_contexts[i] = ctx
    }
    stop_timer(&session.timing.context_setup)

    session.timing.thread_creation = start_timer()
    session.timing.rendering = start_timer()
    for i in 0..<num_threads {
        t := thread.create(worker_thread)
        t.data = session.heap_contexts[i]
        session.threads[i] = t
        thread.start(t)
    }
    stop_timer(&session.timing.thread_creation)

    return session
}

// free_session releases the remaining allocations left over after finish_render:
// the pixel buffer, the tile list, and the session struct itself.
// Must only be called after finish_render returns.
free_session :: proc(session: ^RenderSession) {
    if session == nil { return }
    delete(session.pixel_buffer.pixels)
    delete(session.work_queue.tiles)
    free(session)
}

// get_render_profile returns the profile for the last completed render for this session.
// Call after finish_render; returns nil if session is nil.
get_render_profile :: proc(session: ^RenderSession) -> ^RenderProfileSummary {
    if session == nil { return nil }
    return &session.last_profile
}

get_render_progress :: proc(session: ^RenderSession) -> f32 {
    if session.use_gpu {
        r := session.gpu_renderer
        if r == nil { return 1.0 }
        cur, tot := gpu_renderer_get_samples(r)
        if tot == 0 { return 1.0 }
        return f32(cur) / f32(tot)
    }
    if session.work_queue.total_tiles == 0 {
        return 1.0
    }
    completed := sync.atomic_load(&session.work_queue.completed)
    return f32(completed) / f32(session.work_queue.total_tiles)
}

// finish_render joins all worker threads and frees session resources. It blocks until
// every tile has been processed — there is no abort/cancel signal. If the user closes
// the window mid-render, the UI still calls this and the process can hang for several
// seconds on large renders (e.g. 4K @ 500 spp) until the tile queue is drained.
// Future work: add an atomic "abort" flag so workers exit early and join quickly.
//
// GPU path: no threads to join. Destroys the GPU renderer and frees BVH memory.
finish_render :: proc(session: ^RenderSession) {
    if session.use_gpu {
        stop_timer(&session.timing.total)
        aggregate_into_summary(&session.timing, nil, &session.last_profile)
        // GPU path: only buffer_creation and bvh_construction were timed in start_render_auto; other phases stay zero.
        if session.gpu_backend != nil {
            gpu_backend_destroy(session.gpu_backend)
            session.gpu_backend = nil
        }
        if session.linear_bvh != nil {
            delete(session.linear_bvh)
            session.linear_bvh = nil
        }
        if session.bvh_root != nil {
            free_bvh(session.bvh_root)
            session.bvh_root = nil
        }
        if session.threads != nil       { delete(session.threads);       session.threads = nil }
        if session.heap_contexts != nil { delete(session.heap_contexts); session.heap_contexts = nil }
        delete(session.thread_tile_times)
        delete(session.thread_tile_counts)
        delete(session.thread_rendering_breakdowns)
        fmt.println("[GPU] Render complete")
        return
    }

    stop_timer(&session.timing.rendering)

    session.timing.thread_join = start_timer()
    for i in 0..<session.num_threads {
        thread.join(session.threads[i])
        thread.destroy(session.threads[i])
    }
    delete(session.threads)
    session.threads = nil

    for i in 0..<session.num_threads {
        free(session.heap_contexts[i])
    }
    delete(session.heap_contexts)
    session.heap_contexts = nil

    if session.linear_bvh != nil {
        delete(session.linear_bvh)
        session.linear_bvh = nil
    }
    if session.bvh_root != nil {
        free_bvh(session.bvh_root)
        session.bvh_root = nil
    }

    fmt.println("")
    fmt.println("Per-Thread Statistics:")
    fmt.println("  Thread | Tiles | Time (s) | Tiles/sec")
    separator_line := strings.repeat("-", 45)
    fmt.printf("  %s\n", separator_line)
    total_thread_time := 0.0
    for i in 0..<session.num_threads {
        tiles      := session.thread_tile_counts[i]
        thread_time := session.thread_tile_times[i]
        total_thread_time += thread_time
        tiles_per_sec := 0.0
        if thread_time > 0 {
            tiles_per_sec = f64(tiles) / thread_time
        }
        fmt.printf("  %6d | %5d | %8.3f | %10.2f\n", i, tiles, thread_time, tiles_per_sec)
    }
    avg_thread_time := total_thread_time / f64(session.num_threads)
    fmt.printf("  Average thread time: %.3f s\n", avg_thread_time)
    fmt.println("")

    rendering_breakdown := RenderingBreakdown{}
    for i in 0..<session.num_threads {
        rb := session.thread_rendering_breakdowns[i]
        rendering_breakdown.get_ray_time        += rb.get_ray_time
        rendering_breakdown.ray_color_time      += rb.ray_color_time
        rendering_breakdown.intersection_time   += rb.intersection_time
        rendering_breakdown.scatter_time        += rb.scatter_time
        rendering_breakdown.background_time     += rb.background_time
        rendering_breakdown.pixel_setup_time    += rb.pixel_setup_time
        rendering_breakdown.total_samples       += rb.total_samples
        rendering_breakdown.total_rays          += rb.total_rays
        rendering_breakdown.total_intersections += rb.total_intersections
    }

    delete(session.thread_tile_times)
    delete(session.thread_tile_counts)
    delete(session.thread_rendering_breakdowns)

    stop_timer(&session.timing.thread_join)

    total_tiles := session.work_queue.total_tiles
    print_parallel_timing_breakdown(
        &session.timing,
        session.camera.image_width,
        session.camera.image_height,
        session.camera.samples_per_pixel,
        session.num_threads,
        total_tiles,
    )

    rendering_time := get_elapsed_seconds(session.timing.rendering)
    aggregate_into_summary(&session.timing, &rendering_breakdown, &session.last_profile)

    print_rendering_breakdown(&rendering_breakdown, rendering_time)
}

// start_render_auto starts a render session using the GPU compute-shader path when
// use_gpu=true and the GPU backend initialises successfully, otherwise falls back
// to the standard CPU multi-threaded path.
//
// GPU path:
//   Builds the pixel buffer and BVH (needed for GPU upload) without spawning any
//   CPU worker threads.  gpu_backend_init compiles the shader and uploads the scene.
//   If GPU init fails the partial session is cleaned up and start_render is called.
//
// CPU path (use_gpu=false or GPU init failure):
//   Identical to calling start_render directly.
start_render_auto :: proc(
    cam:         ^Camera,
    world:       [dynamic]Object,
    num_threads: int,
    use_gpu:     bool,
) -> ^RenderSession {
    if !use_gpu {
        return start_render(cam, world, num_threads)
    }

    // Build session without spawning CPU worker threads.
    session := new(RenderSession)
    session.camera      = cam
    session.num_threads = 0
    session.start_time  = time.now()
    session.timing      = start_parallel_timing()

    session.timing.buffer_creation = start_timer()
    session.pixel_buffer = create_test_pixel_buffer(cam.image_width, cam.image_height)
    stop_timer(&session.timing.buffer_creation)

    session.timing.bvh_construction = start_timer()
    world_slice       := world[:]
    session.bvh_root   = build_bvh(world_slice)
    session.linear_bvh = flatten_bvh(session.bvh_root, world_slice)
    stop_timer(&session.timing.bvh_construction)

    // Initialise empty slices so finish_render never dereferences nil.
    session.threads                     = make([]^thread.Thread, 0)
    session.heap_contexts               = make([]^ParallelRenderContext, 0)
    session.thread_tile_times           = make([dynamic]f64, 0)
    session.thread_tile_counts          = make([dynamic]int, 0)
    session.thread_rendering_breakdowns = make([dynamic]ThreadRenderingBreakdown, 0)

    // Try to initialise the GPU renderer (platform-aware factory).
    renderer := create_gpu_renderer(cam, world_slice, session.linear_bvh, cam.samples_per_pixel)
    if renderer != nil {
        session.gpu_renderer = renderer
        session.use_gpu      = true
        fmt.println("[GPU] Init OK — GPU rendering enabled")
        return session
    }

    // GPU init failed: clean up the partial session and fall back to CPU.
    fmt.println("[GPU] Init failed — falling back to CPU")
    delete(session.pixel_buffer.pixels)
    if session.linear_bvh != nil { delete(session.linear_bvh) }
    if session.bvh_root   != nil { free_bvh(session.bvh_root)  }
    delete(session.threads)
    delete(session.heap_contexts)
    delete(session.thread_tile_times)
    delete(session.thread_tile_counts)
    delete(session.thread_rendering_breakdowns)
    free(session)

    return start_render(cam, world, num_threads)
}
