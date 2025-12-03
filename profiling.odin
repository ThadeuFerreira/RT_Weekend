package main

import "core:fmt"
import "core:strings"
import "core:time"

// Compile-time profiling switch
// Can be overridden via -define:PROFILING_ENABLED=true/false
PROFILING_ENABLED :: #config(PROFILING_ENABLED, true)

// Profile scope for zero-cost profiling
Profile_Scope :: struct {
    start:    time.Time,
    field_ns: ^i64,
}

// Internal helper to begin profiling a scope
profile_scope_begin :: proc(field_ns: ^i64) -> Profile_Scope {
    return Profile_Scope{
        start    = time.now(),
        field_ns = field_ns,
    }
}

// Internal helper to end profiling a scope
profile_scope_end :: proc(scope: Profile_Scope) {
    if scope.field_ns != nil {
        dt := time.diff(scope.start, time.now())
        scope.field_ns^ += time.duration_nanoseconds(dt)
    }
}

// Zero-cost profiling scope begin (compiles out when PROFILING_ENABLED is false)
PROFILE_SCOPE :: proc(field_ns: ^i64) -> Profile_Scope {
    when PROFILING_ENABLED {
        return profile_scope_begin(field_ns)
    } else {
        // Zero-cost dummy - compiler removes this entirely
        return Profile_Scope{}
    }
}

// Zero-cost profiling scope end (compiles out when PROFILING_ENABLED is false)
PROFILE_SCOPE_END :: proc(scope: Profile_Scope) {
    when PROFILING_ENABLED {
        profile_scope_end(scope)
    }
}

// Timing utilities for performance measurement

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

// Detailed timing breakdown for parallel rendering
ParallelTimingBreakdown :: struct {
    buffer_creation: Timer,
    tile_generation: Timer,
    bvh_construction: Timer,
    context_setup: Timer,
    thread_creation: Timer,
    rendering: Timer,        // Time from thread start to all tiles complete
    progress_monitoring: Timer,  // Time spent in progress loop
    thread_join: Timer,
    file_writing: Timer,
    total: Timer,
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
    fmt.printf("    Progress monitoring:  %s (%.2f%%)\n", 
        format_duration(breakdown.progress_monitoring),
        (get_elapsed_seconds(breakdown.progress_monitoring) / total_seconds) * 100.0)
    fmt.printf("    Thread join/cleanup:  %s (%.2f%%)\n", 
        format_duration(breakdown.thread_join),
        (get_elapsed_seconds(breakdown.thread_join) / total_seconds) * 100.0)
    fmt.printf("    File writing:        %s (%.2f%%)\n", 
        format_duration(breakdown.file_writing),
        (get_elapsed_seconds(breakdown.file_writing) / total_seconds) * 100.0)
    fmt.println("")
    fmt.printf("  TOTAL TIME:            %s\n", format_duration(breakdown.total))
    fmt.println("")
    
    // Calculate efficiency metrics
    total_pixels := image_width * image_height
    total_samples := total_pixels * samples_per_pixel
    rendering_seconds := get_elapsed_seconds(breakdown.rendering)
    
    if rendering_seconds > 0 {
        pixels_per_second := f64(total_pixels) / rendering_seconds
        samples_per_second := f64(total_samples) / rendering_seconds
        
        fmt.printf("  Rendering Performance:\n")
        fmt.printf("    Pixels/sec: %.2f K\n", pixels_per_second / 1000.0)
        fmt.printf("    Samples/sec: %.2f M\n", samples_per_second / 1000000.0)
        
        // Calculate overhead
        overhead_seconds := total_seconds - rendering_seconds
        overhead_percent := (overhead_seconds / total_seconds) * 100.0
        fmt.printf("    Overhead: %.2f%% (%.2f s)\n", overhead_percent, overhead_seconds)
    }
    
    fmt.println(separator)
}

// Fine-grained rendering timing breakdown
// All times stored in nanoseconds (i64) for precision
RenderingBreakdown :: struct {
    get_ray_time: i64,           // Time spent generating rays (nanoseconds)
    ray_color_time: i64,          // Time spent in ray_color (recursive tracing) (nanoseconds)
    intersection_time: i64,       // Time spent in intersection testing (nanoseconds)
    scatter_time: i64,            // Time spent in material scattering (nanoseconds)
    background_time: i64,         // Time spent computing background color (nanoseconds)
    pixel_setup_time: i64,        // Time spent setting up pixels (nanoseconds)
    total_samples: i64,           // Total number of samples processed
    total_rays: i64,              // Total number of rays traced
    total_intersections: i64,     // Total number of intersection tests
}

// Thread-local rendering breakdown (accumulated per thread, then merged)
// All times stored in nanoseconds (i64) for precision
ThreadRenderingBreakdown :: struct {
    get_ray_time: i64,            // Time in nanoseconds
    ray_color_time: i64,          // Time in nanoseconds
    intersection_time: i64,       // Time in nanoseconds
    scatter_time: i64,            // Time in nanoseconds
    background_time: i64,         // Time in nanoseconds
    pixel_setup_time: i64,        // Time in nanoseconds
    total_samples: i64,
    total_rays: i64,
    total_intersections: i64,
}

print_rendering_breakdown :: proc(breakdown: ^RenderingBreakdown, total_rendering_time: f64) {
    separator := strings.repeat("-", 70)
    fmt.println("")
    fmt.println("  Fine-Grained Rendering Breakdown:")
    fmt.println(separator)
    
    // Convert nanoseconds to seconds for calculations
    NANOSECONDS_PER_SECOND :: 1_000_000_000.0
    NANOSECONDS_PER_MILLISECOND :: 1_000_000.0
    NANOSECONDS_PER_MICROSECOND :: 1_000.0
    
    // Calculate ray_color_time as sum of nested operations (to avoid double-counting)
    // ray_color_time = intersection_time + scatter_time + background_time
    calculated_ray_color_time_ns := breakdown.intersection_time + breakdown.scatter_time + breakdown.background_time
    
    // Total time excludes the separately measured ray_color_time to avoid double-counting
    // We use the calculated ray_color_time for display, but don't double-count in total
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
