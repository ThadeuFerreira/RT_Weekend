package raytrace

// GpuRenderMode controls whether the GPU renderer stops after reaching
// total_samples (SingleShot) or automatically resets and keeps accumulating
// (Continuous).  Default is SingleShot, matching the CPU path behaviour.
GpuRenderMode :: enum { SingleShot, Continuous }

// GpuRendererApi is a vtable for a GPU rendering backend (Vulkan compute).
GpuRendererApi :: struct {
    init:           proc "odin" (cam: ^Camera, world: []Object, spheres: []GPUSphere, quads: []GPUQuad, bvh: []LinearBVHNode, volumes: []GPUVolume, volume_quads: []GPUQuad, total: int, image_list: []^Texture_Image) -> (rawptr, bool),
    dispatch:       proc "odin" (state: rawptr),
    readback:       proc "odin" (state: rawptr, out: [][4]u8),
    final_readback: proc "odin" (state: rawptr, out: [][4]u8), // blocking wait for most-recent slot; call once at render completion
    destroy:        proc "odin" (state: rawptr),
    get_samples:    proc "odin" (state: rawptr) -> (int, int),
    get_timings:    proc "odin" (state: rawptr) -> (i64, i64),  // dispatch_ns, readback_ns
    reset:          proc "odin" (state: rawptr),                 // zero accumulation, restart from sample 0
}

GpuRenderer :: struct {
    api:   GpuRendererApi,
    state: rawptr,
    mode:  GpuRenderMode, // SingleShot = stop after total_samples; Continuous = loop forever
    kind:  RenderBackendKind,
}

// Helper procs — callers use these, never the vtable directly.
gpu_renderer_dispatch       :: proc(r: ^GpuRenderer) { r.api.dispatch(r.state) }
gpu_renderer_readback       :: proc(r: ^GpuRenderer, out: [][4]u8) { r.api.readback(r.state, out) }
// gpu_renderer_final_readback blocks until the most-recently filled PBO slot is ready,
// then converts it to RGBA bytes.  Call exactly once immediately before finish_render
// or a Continuous restart so the displayed image reflects the last completed sample.
gpu_renderer_final_readback :: proc(r: ^GpuRenderer, out: [][4]u8) {
    if r.api.final_readback != nil { r.api.final_readback(r.state, out) }
}
gpu_renderer_destroy        :: proc(r: ^GpuRenderer) { r.api.destroy(r.state); free(r) }
gpu_renderer_get_samples :: proc(r: ^GpuRenderer) -> (cur: int, tot: int) {
    return r.api.get_samples(r.state)
}
gpu_renderer_get_timings :: proc(r: ^GpuRenderer) -> (disp_ns: i64, read_ns: i64) {
    if r.api.get_timings != nil { return r.api.get_timings(r.state) }
    return 0, 0
}
gpu_renderer_done :: proc(r: ^GpuRenderer) -> bool {
    cur, tot := r.api.get_samples(r.state)
    return tot > 0 && cur >= tot
}
// gpu_renderer_set_mode changes the loop behaviour for the next dispatch cycle.
gpu_renderer_set_mode :: proc(r: ^GpuRenderer, mode: GpuRenderMode) { r.mode = mode }
// gpu_renderer_restart zeros the accumulation buffer and resets the sample counter
// so the next dispatch starts a fresh render without rebuilding the scene or shaders.
gpu_renderer_restart :: proc(r: ^GpuRenderer) {
    if r.api.reset != nil { r.api.reset(r.state) }
}

// create_gpu_renderer tries to initialise the Vulkan compute backend.
// Returns nil if no GPU backend is available.
create_gpu_renderer :: proc(
    cam:          ^Camera,
    world:        []Object,
    spheres:      []GPUSphere,
    quads:        []GPUQuad,
    bvh:          []LinearBVHNode,
    volumes:      []GPUVolume,
    volume_quads: []GPUQuad,
    total:        int,
    image_list:   []^Texture_Image,
) -> ^GpuRenderer {
    if state, ok := VULKAN_RENDERER_API.init(cam, world, spheres, quads, bvh, volumes, volume_quads, total, image_list); ok {
        r := new(GpuRenderer)
        r.api   = VULKAN_RENDERER_API
        r.state = state
        r.kind  = .Vulkan_Compute
        return r
    }
    return nil
}
