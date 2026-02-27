package raytrace

// GpuRendererApi is a vtable for a GPU rendering backend.
//
// To add a new backend (e.g. Metal, Vulkan, DX12):
//   1. Define a backend-specific state struct.
//   2. Implement the five procs below for that struct.
//   3. Declare a package-level constant MY_RENDERER_API :: GpuRendererApi{...}.
//   4. Add a `when ODIN_OS == .Whatever` branch in create_gpu_renderer() to try it.
GpuRendererApi :: struct {
    init:        proc "odin" (cam: ^Camera, world: []Object, bvh: []LinearBVHNode, total: int) -> (rawptr, bool),
    dispatch:    proc "odin" (state: rawptr),
    readback:    proc "odin" (state: rawptr, out: [][4]u8),
    destroy:     proc "odin" (state: rawptr),
    get_samples: proc "odin" (state: rawptr) -> (int, int),
}

GpuRenderer :: struct {
    api:   GpuRendererApi,
    state: rawptr,
}

// Helper procs — callers use these, never the vtable directly.
gpu_renderer_dispatch    :: proc(r: ^GpuRenderer) { r.api.dispatch(r.state) }
gpu_renderer_readback    :: proc(r: ^GpuRenderer, out: [][4]u8) { r.api.readback(r.state, out) }
gpu_renderer_destroy     :: proc(r: ^GpuRenderer) { r.api.destroy(r.state); free(r) }
gpu_renderer_get_samples :: proc(r: ^GpuRenderer) -> (cur: int, tot: int) {
    return r.api.get_samples(r.state)
}
gpu_renderer_done :: proc(r: ^GpuRenderer) -> bool {
    cur, tot := r.api.get_samples(r.state)
    return tot > 0 && cur >= tot
}

// create_gpu_renderer is the platform-aware factory.
// It tries the best backend for the current OS, falling back through options
// until one succeeds.  Returns nil if no GPU backend is available.
create_gpu_renderer :: proc(
    cam:   ^Camera,
    world: []Object,
    bvh:   []LinearBVHNode,
    total: int,
) -> ^GpuRenderer {
    // ── macOS: future Metal backend goes here ─────────────────────────────────
    // when ODIN_OS == .Darwin {
    //     if state, ok := METAL_RENDERER_API.init(cam, world, bvh, total); ok {
    //         r := new(GpuRenderer)
    //         r.api   = METAL_RENDERER_API
    //         r.state = state
    //         return r
    //     }
    // }

    // ── Windows: future DirectX 12 / Vulkan backend goes here ─────────────────
    // when ODIN_OS == .Windows {
    //     if state, ok := DX12_RENDERER_API.init(cam, world, bvh, total); ok { ... }
    //     if state, ok := VULKAN_RENDERER_API.init(cam, world, bvh, total); ok { ... }
    // }

    // OpenGL backend — works on Linux (GLX), Windows (WGL), and macOS
    // (fails gracefully at 4.1 cap with a printed message).
    when ODIN_OS == .Linux || ODIN_OS == .Windows || ODIN_OS == .Darwin {
        if state, ok := OPENGL_RENDERER_API.init(cam, world, bvh, total); ok {
            r := new(GpuRenderer)
            r.api   = OPENGL_RENDERER_API
            r.state = state
            return r
        }
    }

    return nil
}
