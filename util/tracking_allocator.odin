// Leak-detection wrapper around mem.Tracking_Allocator.
// Enabled by default in debug builds (ODIN_DEBUG=true), disabled in release.
// Override with -define:TRACK_ALLOCATIONS=true/false.
//
// Usage in main():
//
//   when util.TRACK_ALLOCATIONS {
//       _track: util.Tracking_Allocator_State
//       util.tracking_init(&_track, context.allocator)
//       context.allocator = util.tracking_allocator(&_track)
//       defer util.tracking_report_and_destroy(&_track)
//   }
//
// Note: worker threads receive runtime.default_context() and bypass the tracker.
// All long-lived main-thread allocations (panels, BVH, scene, undo history) are covered.
package util

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

TRACK_ALLOCATIONS :: #config(TRACK_ALLOCATIONS, ODIN_DEBUG)

Tracking_Allocator_State :: struct {
    tracker: mem.Tracking_Allocator,
}

tracking_init :: proc(state: ^Tracking_Allocator_State, backing: mem.Allocator) {
    when TRACK_ALLOCATIONS {
        mem.tracking_allocator_init(&state.tracker, backing)
    }
}

tracking_allocator :: proc(state: ^Tracking_Allocator_State) -> mem.Allocator {
    when TRACK_ALLOCATIONS {
        return mem.tracking_allocator(&state.tracker)
    } else {
        return context.allocator
    }
}

// Prints a one-line summary to stdout and writes a full report to logs/memory_YYYYMMDD_HHMMSS.txt
// when leaks or bad frees are detected. Uses stack buffers throughout to avoid heap allocations
// that would corrupt the report. Destroys the tracker on exit.
tracking_report_and_destroy :: proc(state: ^Tracking_Allocator_State) {
    when TRACK_ALLOCATIONS {
        defer mem.tracking_allocator_destroy(&state.tracker)

        leak_count     := len(state.tracker.allocation_map)
        bad_free_count := len(state.tracker.bad_free_array)

        if leak_count == 0 && bad_free_count == 0 {
            fmt.println("[Memory] No leaks detected.")
            return
        }

        // Build timestamp without heap allocation.
        now := time.now()
        year, month, day   := time.date(now)
        hour, min, sec     := time.clock_from_time(now)

        path_buf: [128]byte
        path := fmt.bprintf(path_buf[:], "logs/memory_%04d%02d%02d_%02d%02d%02d.txt",
            year, int(month), day, hour, min, sec)

        _ = os.make_directory("logs")

        fd, open_err := os.open(path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o644)
        if open_err == os.ERROR_NONE {
            defer os.close(fd)

            line_buf: [512]byte
            line: string

            line = fmt.bprintf(line_buf[:], "=== MEMORY REPORT ===\nLeaks: %d   Bad frees: %d\n\n",
                leak_count, bad_free_count)
            _, _ = os.write(fd, transmute([]byte)line)

            for _, entry in state.tracker.allocation_map {
                line = fmt.bprintf(line_buf[:], "[LEAK]  %6d bytes  %s:%d\n",
                    entry.size, entry.location.file_path, entry.location.line)
                _, _ = os.write(fd, transmute([]byte)line)
            }

            for entry in state.tracker.bad_free_array {
                line = fmt.bprintf(line_buf[:], "[BAD FREE]  %p  %s:%d\n",
                    entry.memory, entry.location.file_path, entry.location.line)
                _, _ = os.write(fd, transmute([]byte)line)
            }
        }

        fmt.printf("[Memory] %d leak(s), %d bad free(s). Report: %s\n",
            leak_count, bad_free_count, path)
    }
}
