package main

import "core:fmt"
import "core:strings"
import "core:time"

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
RenderingBreakdown :: struct {
    get_ray_time: f64,           // Time spent generating rays
    ray_color_time: f64,          // Time spent in ray_color (recursive tracing)
    intersection_time: f64,       // Time spent in intersection testing
    scatter_time: f64,            // Time spent in material scattering
    background_time: f64,         // Time spent computing background color
    pixel_setup_time: f64,        // Time spent setting up pixels
    total_samples: i64,           // Total number of samples processed
    total_rays: i64,              // Total number of rays traced
    total_intersections: i64,     // Total number of intersection tests
}

// Thread-local rendering breakdown (accumulated per thread, then merged)
ThreadRenderingBreakdown :: struct {
    get_ray_time: f64,
    ray_color_time: f64,
    intersection_time: f64,
    scatter_time: f64,
    background_time: f64,
    pixel_setup_time: f64,
    total_samples: i64,
    total_rays: i64,
    total_intersections: i64,
}

print_rendering_breakdown :: proc(breakdown: ^RenderingBreakdown, total_rendering_time: f64) {
    separator := strings.repeat("-", 70)
    fmt.println("")
    fmt.println("  Fine-Grained Rendering Breakdown:")
    fmt.println(separator)
    
    total_time := breakdown.get_ray_time + breakdown.ray_color_time + breakdown.intersection_time + 
                  breakdown.scatter_time + breakdown.background_time + breakdown.pixel_setup_time
    
    if total_time > 0 {
        fmt.printf("    Ray generation (get_ray):     %8.3f s (%5.2f%%) - %lld calls\n", 
            breakdown.get_ray_time, 
            (breakdown.get_ray_time / total_time) * 100.0,
            breakdown.total_rays)
        fmt.printf("    Ray tracing (ray_color):      %8.3f s (%5.2f%%) - %lld rays\n", 
            breakdown.ray_color_time,
            (breakdown.ray_color_time / total_time) * 100.0,
            breakdown.total_rays)
        fmt.printf("    Intersection testing:         %8.3f s (%5.2f%%) - %lld tests\n", 
            breakdown.intersection_time,
            (breakdown.intersection_time / total_time) * 100.0,
            breakdown.total_intersections)
        fmt.printf("    Material scattering:          %8.3f s (%5.2f%%)\n", 
            breakdown.scatter_time,
            (breakdown.scatter_time / total_time) * 100.0)
        fmt.printf("    Background computation:       %8.3f s (%5.2f%%)\n", 
            breakdown.background_time,
            (breakdown.background_time / total_time) * 100.0)
        fmt.printf("    Pixel setup/write:            %8.3f s (%5.2f%%)\n", 
            breakdown.pixel_setup_time,
            (breakdown.pixel_setup_time / total_time) * 100.0)
        fmt.println("")
        fmt.printf("    Total measured time:          %8.3f s\n", total_time)
        fmt.printf("    Wall-clock rendering time:    %8.3f s\n", total_rendering_time)
        fmt.printf("    Unaccounted time:             %8.3f s (%5.2f%%)\n",
            total_rendering_time - total_time,
            ((total_rendering_time - total_time) / total_rendering_time) * 100.0)
        fmt.println("")
        
        if breakdown.total_samples > 0 {
            avg_time_per_sample := total_time / f64(breakdown.total_samples)
            fmt.printf("    Average time per sample:     %8.3f ms\n", avg_time_per_sample * 1000.0)
        }
        if breakdown.total_rays > 0 {
            avg_time_per_ray := breakdown.ray_color_time / f64(breakdown.total_rays)
            fmt.printf("    Average time per ray:         %8.3f μs\n", avg_time_per_ray * 1000000.0)
        }
        if breakdown.total_intersections > 0 {
            avg_time_per_intersection := breakdown.intersection_time / f64(breakdown.total_intersections)
            fmt.printf("    Average time per intersection: %8.3f μs\n", avg_time_per_intersection * 1000000.0)
        }
    }
    fmt.println(separator)
}
