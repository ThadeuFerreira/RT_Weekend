package raytrace

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"

import "RT_Weekend:util"

// cpu_backend.odin — CPU tile-based renderer as a RenderBackend.
//
// Wraps the existing multi-threaded tile renderer behind the RenderBackendApi
// vtable so the editor/headless code path is backend-agnostic.
//
// The CPU backend is "fire and forget": start_render spawns worker threads that
// pull tiles from a shared queue.  tick() is a no-op.  readback() converts the
// shared float pixel buffer to gamma-corrected RGBA bytes.

// CPUBackendState holds the data that the CPU vtable procs need beyond
// what's already in the RenderSession.  Kept minimal — most state lives in
// the session itself (pixel_buffer, work_queue, threads, etc.).
CPUBackendState :: struct {
    session: ^RenderSession,
}

// ── vtable procs ─────────────────────────────────────────────────────────────

@(private) _cpu_tick :: proc(state: rawptr) {
    // Workers run autonomously; nothing to do per frame.
}

@(private) _cpu_readback :: proc(state: rawptr, out: [][4]u8) {
    s := (^CPUBackendState)(state)
    session := s.session
    buf := &session.pixel_buffer
    cam := session.r_camera
    clamp := Interval{0.0, 0.999}

    for y in 0..<buf.height {
        for x in 0..<buf.width {
            raw := buf.pixels[y * buf.width + x] * cam.pixel_samples_scale

            r := linear_to_gamma(raw[0])
            g := linear_to_gamma(raw[1])
            b := linear_to_gamma(raw[2])

            idx := y * buf.width + x
            out[idx] = {
                u8(interval_clamp(clamp, r) * 255.0),
                u8(interval_clamp(clamp, g) * 255.0),
                u8(interval_clamp(clamp, b) * 255.0),
                255,
            }
        }
    }
}

@(private) _cpu_get_progress :: proc(state: rawptr) -> f32 {
    s := (^CPUBackendState)(state)
    session := s.session
    if session.work_queue.total_tiles == 0 { return 1.0 }
    completed := sync.atomic_load(&session.work_queue.completed)
    return f32(completed) / f32(session.work_queue.total_tiles)
}

@(private) _cpu_get_samples :: proc(state: rawptr) -> (int, int) {
    s := (^CPUBackendState)(state)
    session := s.session
    completed := int(sync.atomic_load(&session.work_queue.completed))
    return completed, session.work_queue.total_tiles
}

@(private) _cpu_finish :: proc(state: rawptr, session: ^RenderSession) {
    stop_timer(&session.timing.rendering)
    util.trace_scope_end(session.trace_render_scope)

    join_trace := util.trace_scope_begin("Render.ThreadJoin", "render")
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

    when VERBOSE_OUTPUT {
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
    }

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
    util.trace_scope_end(join_trace)

    total_tiles := session.work_queue.total_tiles
    when VERBOSE_OUTPUT {
        print_parallel_timing_breakdown(
            &session.timing,
            session.r_camera.image_width,
            session.r_camera.image_height,
            session.r_camera.samples_per_pixel,
            session.num_threads,
            total_tiles,
        )
    }

    rendering_time := get_elapsed_seconds(session.timing.rendering)
    aggregate_into_summary(&session.timing, &rendering_breakdown, &session.last_profile)

    when VERBOSE_OUTPUT {
        print_rendering_breakdown(&rendering_breakdown, rendering_time)
    }
}

@(private) _cpu_destroy :: proc(state: rawptr) {
    s := (^CPUBackendState)(state)
    free(s)
}

CPU_BACKEND_API :: RenderBackendApi{
    tick           = _cpu_tick,
    readback       = _cpu_readback,
    get_progress   = _cpu_get_progress,
    get_samples    = _cpu_get_samples,
    finish         = _cpu_finish,
    destroy        = _cpu_destroy,
}

// create_cpu_backend allocates the CPU backend state for a session.
create_cpu_backend :: proc(session: ^RenderSession) -> ^RenderBackend {
    s := new(CPUBackendState)
    s.session = session

    b := new(RenderBackend)
    b.api   = CPU_BACKEND_API
    b.state = s
    b.kind  = .CPU
    return b
}
