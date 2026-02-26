package raytrace

import "core:fmt"
import "core:strings"
import "core:time"

PROFILING_ENABLED :: #config(PROFILING_ENABLED, true)

Profile_Scope :: struct {
    start:    time.Time,
    field_ns: ^i64,
}

profile_scope_begin :: proc(field_ns: ^i64) -> Profile_Scope {
    return Profile_Scope{
        start    = time.now(),
        field_ns = field_ns,
    }
}

profile_scope_end :: proc(scope: Profile_Scope) {
    if scope.field_ns != nil {
        dt := time.diff(scope.start, time.now())
        scope.field_ns^ += time.duration_nanoseconds(dt)
    }
}

PROFILE_SCOPE :: proc(field_ns: ^i64) -> Profile_Scope {
    when PROFILING_ENABLED {
        return profile_scope_begin(field_ns)
    } else {
        return Profile_Scope{}
    }
}

PROFILE_SCOPE_END :: proc(scope: Profile_Scope) {
    when PROFILING_ENABLED {
        profile_scope_end(scope)
    }
}

Timer :: struct {
    start_time: time.Time,
    end_time: time.Time,
    elapsed: time.Duration,
}

start_timer :: proc() -> Timer {
    return Timer{start_time = time.now()}
}

stop_timer :: proc(timer: ^Timer) {
    timer.end_time = time.now()
    timer.elapsed = time.diff(timer.start_time, timer.end_time)
}

get_elapsed_seconds :: proc(timer: Timer) -> f64 {
    return time.duration_seconds(timer.elapsed)
}

get_elapsed_milliseconds :: proc(timer: Timer) -> f64 {
    return time.duration_milliseconds(timer.elapsed)
}

format_duration :: proc(timer: Timer) -> string {
    seconds := get_elapsed_seconds(timer)

    if seconds < 1.0 {
        ms := get_elapsed_milliseconds(timer)
        return fmt.tprintf("%.2f ms", ms)
    } else if seconds < 60.0 {
        return fmt.tprintf("%.2f s", seconds)
    } else {
        minutes := seconds / 60.0
        secs := seconds - (minutes * 60.0)
        return fmt.tprintf("%.0f m %.2f s", minutes, secs)
    }
}

print_timing_stats :: proc(timer: Timer, image_width: int, image_height: int, samples_per_pixel: int) {
    elapsed_seconds := get_elapsed_seconds(timer)
    total_pixels := image_width * image_height
    total_samples := total_pixels * samples_per_pixel

    separator := strings.repeat("=", 60)
    fmt.println("")
    fmt.println(separator)
    fmt.println("Performance Statistics:")
    fmt.println(separator)
    fmt.printf("  Total rendering time: %s\n", format_duration(timer))
    fmt.printf("  Image size: %dx%d pixels (%d total pixels)\n", image_width, image_height, total_pixels)
    fmt.printf("  Samples per pixel: %d\n", samples_per_pixel)
    fmt.printf("  Total samples: %d\n", total_samples)

    if elapsed_seconds > 0 {
        pixels_per_second := f64(total_pixels) / elapsed_seconds
        samples_per_second := f64(total_samples) / elapsed_seconds

        fmt.printf("  Rendering speed: %.2f pixels/sec\n", pixels_per_second)
        fmt.printf("  Sample rate: %.2f samples/sec\n", samples_per_second)

        if pixels_per_second > 1000 {
            fmt.printf("  Rendering speed: %.2f K pixels/sec\n", pixels_per_second / 1000.0)
        }
        if samples_per_second > 1000000 {
            fmt.printf("  Sample rate: %.2f M samples/sec\n", samples_per_second / 1000000.0)
        }
    }
    fmt.println(separator)
}

ParallelTimingBreakdown :: struct {
    buffer_creation: Timer,
    tile_generation: Timer,
    bvh_construction: Timer,
    context_setup: Timer,
    thread_creation: Timer,
    rendering: Timer,
    thread_join: Timer,
    total: Timer,
}

PhaseEntry :: struct {
    name:    string,
    seconds: f64,
    percent: f64,
}

RenderProfileSummary :: struct {
    total_seconds:       f64,
    phase_count:         int,
    phases:              [8]PhaseEntry,
    has_sample_breakdown: bool,
    sample_get_ray_pct:  f64,
    sample_intersection_pct: f64,
    sample_scatter_pct:  f64,
    sample_background_pct: f64,
    sample_pixel_setup_pct: f64,
    total_samples:       i64,
    total_rays:           i64,
    total_intersections:   i64,
}

start_parallel_timing :: proc() -> ParallelTimingBreakdown {
    total_timer := start_timer()
    return ParallelTimingBreakdown{total = total_timer}
}

print_parallel_timing_breakdown :: proc(breakdown: ^ParallelTimingBreakdown, image_width: int, image_height: int, samples_per_pixel: int, num_threads: int, total_tiles: int) {
    stop_timer(&breakdown.total)

    separator := strings.repeat("=", 70)
    fmt.println("")
    fmt.println(separator)
    fmt.println("Detailed Performance Breakdown:")
    fmt.println(separator)
    fmt.printf("  Configuration:\n")
    fmt.printf("    Image size: %dx%d pixels\n", image_width, image_height)
    fmt.printf("    Samples per pixel: %d\n", samples_per_pixel)
    fmt.printf("    Threads: %d\n", num_threads)
    fmt.printf("    Total tiles: %d\n", total_tiles)
    fmt.println("")

    total_seconds := get_elapsed_seconds(breakdown.total)

    fmt.printf("  Timing Breakdown:\n")
    fmt.printf("    Buffer creation:      %s (%.2f%%)\n",
        format_duration(breakdown.buffer_creation),
        (get_elapsed_seconds(breakdown.buffer_creation) / total_seconds) * 100.0)
    fmt.printf("    Tile generation:      %s (%.2f%%)\n",
        format_duration(breakdown.tile_generation),
        (get_elapsed_seconds(breakdown.tile_generation) / total_seconds) * 100.0)
    fmt.printf("    BVH construction:    %s (%.2f%%)\n",
        format_duration(breakdown.bvh_construction),
        (get_elapsed_seconds(breakdown.bvh_construction) / total_seconds) * 100.0)
    fmt.printf("    Context setup:       %s (%.2f%%)\n",
        format_duration(breakdown.context_setup),
        (get_elapsed_seconds(breakdown.context_setup) / total_seconds) * 100.0)
    fmt.printf("    Thread creation:     %s (%.2f%%)\n",
        format_duration(breakdown.thread_creation),
        (get_elapsed_seconds(breakdown.thread_creation) / total_seconds) * 100.0)
    fmt.printf("    Rendering (work):    %s (%.2f%%)\n",
        format_duration(breakdown.rendering),
        (get_elapsed_seconds(breakdown.rendering) / total_seconds) * 100.0)
    fmt.printf("    Thread join/cleanup: %s (%.2f%%)\n",
        format_duration(breakdown.thread_join),
        (get_elapsed_seconds(breakdown.thread_join) / total_seconds) * 100.0)
    fmt.println("")
    fmt.printf("  TOTAL TIME:            %s\n", format_duration(breakdown.total))
    fmt.println("")

    total_pixels := image_width * image_height
    total_samples := total_pixels * samples_per_pixel
    rendering_seconds := get_elapsed_seconds(breakdown.rendering)

    if rendering_seconds > 0 {
        pixels_per_second := f64(total_pixels) / rendering_seconds
        samples_per_second := f64(total_samples) / rendering_seconds

        fmt.printf("  Rendering Performance:\n")
        fmt.printf("    Pixels/sec: %.2f K\n", pixels_per_second / 1000.0)
        fmt.printf("    Samples/sec: %.2f M\n", samples_per_second / 1000000.0)

        overhead_seconds := total_seconds - rendering_seconds
        overhead_percent := (overhead_seconds / total_seconds) * 100.0
        fmt.printf("    Overhead: %.2f%% (%.2f s)\n", overhead_percent, overhead_seconds)
    }

    fmt.println(separator)
}

RenderingBreakdown :: struct {
    get_ray_time: i64,
    ray_color_time: i64,
    intersection_time: i64,
    scatter_time: i64,
    background_time: i64,
    pixel_setup_time: i64,
    total_samples: i64,
    total_rays: i64,
    total_intersections: i64,
}

ThreadRenderingBreakdown :: struct {
    get_ray_time: i64,
    ray_color_time: i64,
    intersection_time: i64,
    scatter_time: i64,
    background_time: i64,
    pixel_setup_time: i64,
    total_samples: i64,
    total_rays: i64,
    total_intersections: i64,
}

print_rendering_breakdown :: proc(breakdown: ^RenderingBreakdown, total_rendering_time: f64) {
    separator := strings.repeat("-", 70)
    fmt.println("")
    fmt.println("  Fine-Grained Rendering Breakdown:")
    fmt.println(separator)

    NANOSECONDS_PER_SECOND :: 1_000_000_000.0
    NANOSECONDS_PER_MILLISECOND :: 1_000_000.0
    NANOSECONDS_PER_MICROSECOND :: 1_000.0

    calculated_ray_color_time_ns := breakdown.intersection_time + breakdown.scatter_time + breakdown.background_time
    total_time_ns := breakdown.get_ray_time + calculated_ray_color_time_ns + breakdown.pixel_setup_time
    total_time_s := f64(total_time_ns) / NANOSECONDS_PER_SECOND

    if total_time_ns > 0 {
        get_ray_time_s := f64(breakdown.get_ray_time) / NANOSECONDS_PER_SECOND
        ray_color_time_s := f64(calculated_ray_color_time_ns) / NANOSECONDS_PER_SECOND
        intersection_time_s := f64(breakdown.intersection_time) / NANOSECONDS_PER_SECOND
        scatter_time_s := f64(breakdown.scatter_time) / NANOSECONDS_PER_SECOND
        background_time_s := f64(breakdown.background_time) / NANOSECONDS_PER_SECOND
        pixel_setup_time_s := f64(breakdown.pixel_setup_time) / NANOSECONDS_PER_SECOND

        fmt.printf("    Ray generation (get_ray):     %8.3f s (%5.2f%%) - %v calls\n",
            get_ray_time_s,
            (f64(breakdown.get_ray_time) / f64(total_time_ns)) * 100.0,
            breakdown.total_rays)
        fmt.printf("    Ray tracing (ray_color):      %8.3f s (%5.2f%%) - %v rays\n",
            ray_color_time_s,
            (f64(calculated_ray_color_time_ns) / f64(total_time_ns)) * 100.0,
            breakdown.total_rays)
        fmt.printf("    Intersection testing:         %8.3f s (%5.2f%%) - %v tests\n",
            intersection_time_s,
            (f64(breakdown.intersection_time) / f64(total_time_ns)) * 100.0,
            breakdown.total_intersections)
        fmt.printf("    Material scattering:          %8.3f s (%5.2f%%)\n",
            scatter_time_s,
            (f64(breakdown.scatter_time) / f64(total_time_ns)) * 100.0)
        fmt.printf("    Background computation:       %8.3f s (%5.2f%%)\n",
            background_time_s,
            (f64(breakdown.background_time) / f64(total_time_ns)) * 100.0)
        fmt.printf("    Pixel setup/write:            %8.3f s (%5.2f%%)\n",
            pixel_setup_time_s,
            (f64(breakdown.pixel_setup_time) / f64(total_time_ns)) * 100.0)
        fmt.println("")
        fmt.printf("    Total CPU time:          %8.3f s\n", total_time_s)
        fmt.printf("    Wall-clock rendering time:    %8.3f s\n", total_rendering_time)
        unaccounted_time_s := total_rendering_time - total_time_s
        fmt.printf("    CPU time vs Wall-clock time:             %8.3f s (%5.2f%%)\n",
            unaccounted_time_s,
            (unaccounted_time_s / total_rendering_time) * 100.0)
        fmt.println("")

        if breakdown.total_samples > 0 {
            avg_time_per_sample_ns := f64(total_time_ns) / f64(breakdown.total_samples)
            avg_time_per_sample_ms := avg_time_per_sample_ns / NANOSECONDS_PER_MILLISECOND
            fmt.printf("    Average time per sample:     %8.3f ms\n", avg_time_per_sample_ms)
        }
        if breakdown.total_rays > 0 {
            avg_time_per_ray_ns := f64(calculated_ray_color_time_ns) / f64(breakdown.total_rays)
            avg_time_per_ray_us := avg_time_per_ray_ns / NANOSECONDS_PER_MICROSECOND
            fmt.printf("    Average time per ray:         %8.3f μs\n", avg_time_per_ray_us)
        }
        if breakdown.total_intersections > 0 {
            avg_time_per_intersection_ns := f64(breakdown.intersection_time) / f64(breakdown.total_intersections)
            avg_time_per_intersection_us := avg_time_per_intersection_ns / NANOSECONDS_PER_MICROSECOND
            fmt.printf("    Average time per intersection: %8.3f μs\n", avg_time_per_intersection_us)
        }
    }
    fmt.println(separator)
}

aggregate_into_summary :: proc(
    parallel: ^ParallelTimingBreakdown,
    rendering: ^RenderingBreakdown,
    rendering_wall_s: f64,
    summary: ^RenderProfileSummary,
) {
    summary^ = {}
    total_seconds := get_elapsed_seconds(parallel.total)
    if total_seconds <= 0 { return }
    summary.total_seconds = total_seconds

    phases := []PhaseEntry{
        {"Buffer", get_elapsed_seconds(parallel.buffer_creation), (get_elapsed_seconds(parallel.buffer_creation) / total_seconds) * 100.0},
        {"Tiles", get_elapsed_seconds(parallel.tile_generation), (get_elapsed_seconds(parallel.tile_generation) / total_seconds) * 100.0},
        {"BVH", get_elapsed_seconds(parallel.bvh_construction), (get_elapsed_seconds(parallel.bvh_construction) / total_seconds) * 100.0},
        {"Context", get_elapsed_seconds(parallel.context_setup), (get_elapsed_seconds(parallel.context_setup) / total_seconds) * 100.0},
        {"Thread create", get_elapsed_seconds(parallel.thread_creation), (get_elapsed_seconds(parallel.thread_creation) / total_seconds) * 100.0},
        {"Render", get_elapsed_seconds(parallel.rendering), (get_elapsed_seconds(parallel.rendering) / total_seconds) * 100.0},
        {"Thread join", get_elapsed_seconds(parallel.thread_join), (get_elapsed_seconds(parallel.thread_join) / total_seconds) * 100.0},
    }
    for i in 0..<min(len(phases), len(summary.phases)) {
        summary.phases[i] = phases[i]
    }
    summary.phase_count = len(phases)

    if rendering != nil {
        calculated_ray_color_ns := rendering.intersection_time + rendering.scatter_time + rendering.background_time
        total_ns := rendering.get_ray_time + calculated_ray_color_ns + rendering.pixel_setup_time
        if total_ns > 0 {
            summary.has_sample_breakdown = true
            summary.sample_get_ray_pct = (f64(rendering.get_ray_time) / f64(total_ns)) * 100.0
            summary.sample_intersection_pct = (f64(rendering.intersection_time) / f64(total_ns)) * 100.0
            summary.sample_scatter_pct = (f64(rendering.scatter_time) / f64(total_ns)) * 100.0
            summary.sample_background_pct = (f64(rendering.background_time) / f64(total_ns)) * 100.0
            summary.sample_pixel_setup_pct = (f64(rendering.pixel_setup_time) / f64(total_ns)) * 100.0
            summary.total_samples = rendering.total_samples
            summary.total_rays = rendering.total_rays
            summary.total_intersections = rendering.total_intersections
        }
    }
}
