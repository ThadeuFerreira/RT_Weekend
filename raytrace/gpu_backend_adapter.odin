package raytrace

import "core:fmt"

import "RT_Weekend:util"

// gpu_backend_adapter.odin — Wraps the GpuRendererApi (Vulkan compute)
// behind the unified RenderBackendApi vtable.
//
// This is a thin adapter: each proc forwards to the corresponding GpuRendererApi
// proc.  The Vulkan-specific state (VulkanGPUBackend) is allocated and managed
// by gpu_backend_vulkan.odin; this adapter only holds a pointer to the
// GpuRenderer that owns it.

GPUBackendAdapterState :: struct {
    renderer: ^GpuRenderer,
    session:  ^RenderSession,
}

@(private) _gpu_adapter_tick :: proc(state: rawptr) {
    s := (^GPUBackendAdapterState)(state)
    r := s.renderer
    if r != nil && !gpu_renderer_done(r) {
        r.api.dispatch(r.state)
    }
}

@(private) _gpu_adapter_readback :: proc(state: rawptr, out: [][4]u8) {
    s := (^GPUBackendAdapterState)(state)
    if s.renderer != nil {
        s.renderer.api.readback(s.renderer.state, out)
    }
}

@(private) _gpu_adapter_final_readback :: proc(state: rawptr, out: [][4]u8) {
    s := (^GPUBackendAdapterState)(state)
    if s.renderer != nil {
        gpu_renderer_final_readback(s.renderer, out)
    }
}

@(private) _gpu_adapter_get_progress :: proc(state: rawptr) -> f32 {
    s := (^GPUBackendAdapterState)(state)
    if s.renderer == nil { return 1.0 }
    cur, tot := gpu_renderer_get_samples(s.renderer)
    if tot == 0 { return 1.0 }
    return f32(cur) / f32(tot)
}

@(private) _gpu_adapter_get_samples :: proc(state: rawptr) -> (int, int) {
    s := (^GPUBackendAdapterState)(state)
    if s.renderer == nil { return 0, 0 }
    return gpu_renderer_get_samples(s.renderer)
}

@(private) _gpu_adapter_get_timings :: proc(state: rawptr) -> (i64, i64) {
    s := (^GPUBackendAdapterState)(state)
    if s.renderer == nil { return 0, 0 }
    return gpu_renderer_get_timings(s.renderer)
}

@(private) _gpu_adapter_reset :: proc(state: rawptr) {
    s := (^GPUBackendAdapterState)(state)
    if s.renderer != nil {
        gpu_renderer_restart(s.renderer)
    }
}

@(private) _gpu_adapter_finish :: proc(state: rawptr, session: ^RenderSession) {
    s := (^GPUBackendAdapterState)(state)
    util.trace_scope_end(session.trace_render_scope)
    stop_timer(&session.timing.total)
    aggregate_into_summary(&session.timing, nil, &session.last_profile)

    if s.renderer != nil {
        disp_ns, read_ns := gpu_renderer_get_timings(s.renderer)
        session.last_profile.gpu_dispatch_seconds = f64(disp_ns) / 1e9
        session.last_profile.gpu_readback_seconds = f64(read_ns) / 1e9
        gpu_renderer_destroy(s.renderer)
        s.renderer = nil
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
    when VERBOSE_OUTPUT {
        fmt.println("[GPU] Render complete")
    }
}

@(private) _gpu_adapter_destroy :: proc(state: rawptr) {
    s := (^GPUBackendAdapterState)(state)
    free(s)
}

GPU_ADAPTER_API :: RenderBackendApi{
    tick           = _gpu_adapter_tick,
    readback       = _gpu_adapter_readback,
    final_readback = _gpu_adapter_final_readback,
    get_progress   = _gpu_adapter_get_progress,
    get_samples    = _gpu_adapter_get_samples,
    get_timings    = _gpu_adapter_get_timings,
    reset          = _gpu_adapter_reset,
    finish         = _gpu_adapter_finish,
    destroy        = _gpu_adapter_destroy,
}

// create_gpu_backend_adapter wraps an already-initialised GpuRenderer as a RenderBackend.
create_gpu_backend_adapter :: proc(renderer: ^GpuRenderer, session: ^RenderSession) -> ^RenderBackend {
    s := new(GPUBackendAdapterState)
    s.renderer = renderer
    s.session  = session

    b := new(RenderBackend)
    b.api   = GPU_ADAPTER_API
    b.state = s
    b.kind  = renderer.kind
    return b
}
