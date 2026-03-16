package raytrace

// GpuRenderMode controls whether the GPU renderer stops after reaching
// total_samples (SingleShot) or automatically resets and keeps accumulating
// (Continuous).  Default is SingleShot, matching the CPU path behaviour.
GpuRenderMode :: enum { SingleShot, Continuous }

// GpuRendererApi is a vtable for a GPU rendering backend.
//
// To add a new backend (e.g. Metal, Vulkan, DX12):
//   1. Define a backend-specific state struct.
//   2. Implement the procs below for that struct.
//   3. Declare a package-level constant MY_RENDERER_API :: GpuRendererApi{...}.
//   4. Add a `when ODIN_OS == .Whatever` branch in create_gpu_renderer() to try it.
GpuRendererApi :: struct {
    init:        proc "odin" (cam: ^Camera, world: []Object, spheres: []GPUSphere, quads: []GPUQuad, bvh: []LinearBVHNode, volumes: []GPUVolume, volume_quads: []GPUQuad, total: int, image_list: []^Texture_Image) -> (rawptr, bool),
    dispatch:    proc "odin" (state: rawptr),
    readback:    proc "odin" (state: rawptr, out: [][4]u8),
    destroy:     proc "odin" (state: rawptr),
    get_samples: proc "odin" (state: rawptr) -> (int, int),
    get_timings: proc "odin" (state: rawptr) -> (i64, i64),  // dispatch_ns, readback_ns
    reset:       proc "odin" (state: rawptr),                 // zero accumulation, restart from sample 0
}

GpuRenderer :: struct {
    api:   GpuRendererApi,
    state: rawptr,
    mode:  GpuRenderMode, // SingleShot = stop after total_samples; Continuous = loop forever
}

// Helper procs — callers use these, never the vtable directly.
gpu_renderer_dispatch    :: proc(r: ^GpuRenderer) { r.api.dispatch(r.state) }
gpu_renderer_readback    :: proc(r: ^GpuRenderer, out: [][4]u8) { r.api.readback(r.state, out) }
gpu_renderer_destroy     :: proc(r: ^GpuRenderer) { r.api.destroy(r.state); free(r) }
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

// create_gpu_renderer is the platform-aware factory.
// world is the full scene (reserved for backends that need it); spheres, quads, volumes, volume_quads are GPU arrays;
// bvh must be from flatten_bvh_for_gpu. image_list is the ordered image textures from
// collect_image_textures_ordered (caller collects once). Returns nil if no GPU backend is available.
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
    // ── macOS: future Metal backend goes here ─────────────────────────────────
    // when ODIN_OS == .Darwin {
    //     if state, ok := METAL_RENDERER_API.init(cam, world, spheres, quads, bvh, total); ok {
    //         r := new(GpuRenderer)
    //         r.api   = METAL_RENDERER_API
    //         r.state = state
    //         return r
    //     }
    // }

    // ── Windows: future DirectX 12 / Vulkan backend goes here ─────────────────
    // when ODIN_OS == .Windows {
    //     if state, ok := DX12_RENDERER_API.init(cam, world, spheres, quads, bvh, total); ok { ... }
    // }

    // OpenGL backend — works on Linux (GLX), Windows (WGL), and macOS
    // (fails gracefully at 4.1 cap with a printed message).
    when ODIN_OS == .Linux || ODIN_OS == .Windows || ODIN_OS == .Darwin {
        if state, ok := OPENGL_RENDERER_API.init(cam, world, spheres, quads, bvh, volumes, volume_quads, total, image_list); ok {
            r := new(GpuRenderer)
            r.api   = OPENGL_RENDERER_API
            r.state = state
            return r
        }
    }

    return nil
}
