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