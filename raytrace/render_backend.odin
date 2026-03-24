package raytrace

// render_backend.odin — Backend-agnostic render interface.
//
// Both the CPU tile-based renderer and GPU compute-shader renderer implement
// this vtable so the editor and headless paths never branch on backend kind.
//
// To add a new backend (e.g. Vulkan, Metal, DX12):
//   1. Define a backend-specific state struct.
//   2. Implement the RenderBackendApi procs for that struct.
//   3. Declare a package-level constant MY_BACKEND_API :: RenderBackendApi{...}.
//   4. Add a branch in create_render_backend() to try it.

RenderBackendKind :: enum {
    CPU,
    OpenGL_Compute,
    Vulkan_Compute,
    // Future:
    // Metal_Compute,
    // DX12_Compute,
}

// RenderBackendApi is the vtable every render backend must implement.
//
// Lifecycle:
//   1. create_render_backend() → ^RenderBackend   (factory; picks best available)
//   2. Per frame:  backend_tick()                  (advance work)
//                  backend_readback()              (copy pixels to staging)
//                  backend_get_progress()          (poll completion)
//   3. On done:    backend_final_readback()        (optional; blocks for last sample)
//                  backend_finish()                (join/cleanup, populate profile)
//   4. Later:      backend_destroy()               (free all memory)
RenderBackendApi :: struct {
    // Advance one unit of rendering work.
    // CPU: no-op (workers run autonomously via threads).
    // GPU: dispatch one compute-shader sample.
    tick:           proc "odin" (state: rawptr),

    // Copy current accumulated pixels into `out` as RGBA bytes (gamma-corrected).
    // CPU: reads from shared float buffer.  GPU: reads back from GPU memory.
    readback:       proc "odin" (state: rawptr, out: [][4]u8),

    // Blocking readback that ensures the very last sample is included.
    // May be nil (CPU path doesn't need it).
    final_readback: proc "odin" (state: rawptr, out: [][4]u8),

    // Returns 0.0–1.0 render completion fraction.
    get_progress:   proc "odin" (state: rawptr) -> f32,

    // Returns (current_samples_or_tiles, total).
    get_samples:    proc "odin" (state: rawptr) -> (int, int),

    // Returns accumulated timing in nanoseconds: (dispatch_ns, readback_ns).
    // May be nil.
    get_timings:    proc "odin" (state: rawptr) -> (i64, i64),

    // Zero accumulation buffer and restart from sample 0 without rebuilding.
    // May be nil.
    reset:          proc "odin" (state: rawptr),

    // Join threads / release GPU objects.  Populates the session profile.
    // Called once when the render is complete.
    finish:         proc "odin" (state: rawptr, session: ^RenderSession),

    // Free all remaining memory (pixel buffer, session, etc.).
    // Called after finish, when the session is no longer needed.
    destroy:        proc "odin" (state: rawptr),
}

RenderBackend :: struct {
    api:   RenderBackendApi,
    state: rawptr,              // backend-specific state (opaque)
    kind:  RenderBackendKind,
    mode:  GpuRenderMode,       // SingleShot or Continuous (only meaningful for GPU backends)
}

// ── Convenience helpers — callers use these, never the vtable directly. ──────

backend_tick :: proc(b: ^RenderBackend) {
    if b.api.tick != nil { b.api.tick(b.state) }
}

backend_readback :: proc(b: ^RenderBackend, out: [][4]u8) {
    if b.api.readback != nil { b.api.readback(b.state, out) }
}

backend_final_readback :: proc(b: ^RenderBackend, out: [][4]u8) {
    if b.api.final_readback != nil { b.api.final_readback(b.state, out) }
}

backend_get_progress :: proc(b: ^RenderBackend) -> f32 {
    if b.api.get_progress != nil { return b.api.get_progress(b.state) }
    return 1.0
}

backend_get_samples :: proc(b: ^RenderBackend) -> (cur: int, tot: int) {
    if b.api.get_samples != nil { return b.api.get_samples(b.state) }
    return 0, 0
}

backend_get_timings :: proc(b: ^RenderBackend) -> (disp_ns: i64, read_ns: i64) {
    if b.api.get_timings != nil { return b.api.get_timings(b.state) }
    return 0, 0
}

backend_reset :: proc(b: ^RenderBackend) {
    if b.api.reset != nil { b.api.reset(b.state) }
}

backend_finish :: proc(b: ^RenderBackend, session: ^RenderSession) {
    if b.api.finish != nil { b.api.finish(b.state, session) }
}

backend_destroy :: proc(b: ^RenderBackend) {
    if b.api.destroy != nil { b.api.destroy(b.state) }
    free(b)
}

backend_done :: proc(b: ^RenderBackend) -> bool {
    cur, tot := backend_get_samples(b)
    return tot > 0 && cur >= tot
}

backend_kind_label :: proc(kind: RenderBackendKind) -> string {
    switch kind {
    case .CPU:             return "CPU"
    case .OpenGL_Compute:  return "GPU (OpenGL)"
    case .Vulkan_Compute:  return "GPU (Vulkan)"
    }
    return "Unknown"
}
