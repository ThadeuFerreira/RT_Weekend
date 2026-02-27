package raytrace

// =============================================================
// GPU Compute-Shader Backend (Step 4)
// =============================================================
//
// This file implements the four-procedure GPU backend API:
//
//   gpu_backend_init      — compile shader, allocate & upload buffers
//   gpu_backend_dispatch  — update UBO, bind SSBOs, dispatch one sample
//   gpu_backend_readback  — read output SSBO, gamma-correct, fill [][4]u8
//   gpu_backend_destroy   — delete GL objects, free backend struct
//
// The backend requires an OpenGL 4.3+ context (compute shaders).
// All GL function pointers are loaded via glXGetProcAddressARB on Linux.
// Call gpu_backend_init AFTER rl.InitWindow() (GL context must exist).
//
// Scene data layout on the GPU (std430 / std140 — see gpu_types.odin):
//   UBO  binding=0 : GPUCameraUniforms (128 bytes, std140)
//   SSBO binding=1 : [4]i32 header + []GPUSphere  (static, uploaded once)
//   SSBO binding=2 : [4]i32 header + []LinearBVHNode (static, uploaded once)
//   SSBO binding=3 : []vec4 output accumulation (zeroed, grows each dispatch)

import "core:fmt"
import "core:math"
import gl "vendor:OpenGL"

// ── GL proc loader (Linux) ───────────────────────────────────────────────────
//
// glXGetProcAddressARB resolves any GL 4.x function by name as long as a
// GL context is current.  It is the standard loader for GLX-based systems.
// This block is stripped on non-Linux platforms by the Odin compiler.

when ODIN_OS == .Linux {
    foreign import libGL "system:GL"
    @(default_calling_convention = "c")
    foreign libGL {
        glXGetProcAddressARB :: proc(name: cstring) -> rawptr ---
    }

    // _set_gl_proc_address satisfies gl.Set_Proc_Address_Type.
    // gl.load_up_to calls it once per function name to fill the
    // package-level function pointer table in vendor:OpenGL.
    _set_gl_proc_address :: proc(p: rawptr, name: cstring) {
        (^rawptr)(p)^ = glXGetProcAddressARB(name)
    }
}

when ODIN_OS == .Windows {
    foreign import opengl32 "system:opengl32.lib"
    foreign import kernel32 "system:kernel32.lib"
    @(default_calling_convention = "c")
    foreign opengl32 { wglGetProcAddress :: proc(name: cstring) -> rawptr --- }
    @(default_calling_convention = "c")
    foreign kernel32 {
        LoadLibraryA   :: proc(name: cstring) -> rawptr ---
        GetProcAddress :: proc(module: rawptr, name: cstring) -> rawptr ---
    }
    @(private) _gl32_module: rawptr
    _set_gl_proc_address :: proc(p: rawptr, name: cstring) {
        fn := wglGetProcAddress(name)
        if fn == nil {
            if _gl32_module == nil { _gl32_module = LoadLibraryA("opengl32.dll") }
            fn = GetProcAddress(_gl32_module, name)
        }
        (^rawptr)(p)^ = fn
    }
}

when ODIN_OS == .Darwin {
    // macOS ships OpenGL.framework but caps at version 4.1 (no compute shaders).
    // The loader below compiles and runs; gpu_backend_init will detect the 4.1 cap
    // via the gl.DispatchCompute == nil check and return false → CPU fallback.
    foreign import libdl "system:dl"
    @(default_calling_convention = "c")
    foreign libdl {
        dlopen :: proc(filename: cstring, flags: i32) -> rawptr ---
        dlsym  :: proc(handle: rawptr, symbol: cstring) -> rawptr ---
    }
    RTLD_LAZY   :: i32(0x1)
    RTLD_GLOBAL :: i32(0x8)
    @(private) _ogl_handle: rawptr
    _set_gl_proc_address :: proc(p: rawptr, name: cstring) {
        if _ogl_handle == nil {
            _ogl_handle = dlopen(
                "/System/Library/Frameworks/OpenGL.framework/OpenGL",
                RTLD_LAZY | RTLD_GLOBAL,
            )
        }
        (^rawptr)(p)^ = dlsym(_ogl_handle, name)
    }
}

// ── Internal helper ──────────────────────────────────────────────────────────

// _render_camera_to_gpu_uniforms converts Render_Camera fields to the flat GPUCameraUniforms
// struct that matches the CameraBlock UBO layout in raytrace.comp.
// defocus_angle is packed into the .w component of defocus_disk_u (see shader).
_render_camera_to_gpu_uniforms :: proc(cam: ^Render_Camera, total_samples, current_sample: int) -> GPUCameraUniforms {
    return GPUCameraUniforms{
        camera_center  = cam.center,
        pixel00_loc    = cam.pixel00_loc,
        pixel_delta_u  = cam.pixel_delta_u,
        pixel_delta_v  = cam.pixel_delta_v,
        defocus_disk_u = cam.defocus_disk_u,
        defocus_angle  = cam.defocus_angle,
        defocus_disk_v = cam.defocus_disk_v,
        width          = i32(cam.image_width),
        height         = i32(cam.image_height),
        max_depth      = i32(cam.max_depth),
        total_samples  = i32(total_samples),
        current_sample = i32(current_sample),
    }
}

// ── gpu_backend_init ─────────────────────────────────────────────────────────

// gpu_backend_init compiles the compute shader, creates GL buffer objects, and
// uploads all static scene data (camera, spheres, BVH).  The output accumulation
// SSBO is zeroed so the first dispatch produces a correct sample.
//
// Must be called after rl.InitWindow() (a current GL context is required).
// Returns (nil, false) on any failure — caller falls back to the CPU path.
gpu_backend_init :: proc(
    cam:     ^Render_Camera,
    objects: []Object,
    lin_bvh: []LinearBVHNode,
    samples: int,
) -> (^GPUBackend, bool) {

    // Load all OpenGL 4.6 function pointers.  Safe to call multiple times;
    // subsequent calls are fast no-ops because pointers are already set.
    when ODIN_OS == .Linux || ODIN_OS == .Windows || ODIN_OS == .Darwin {
        gl.load_up_to(4, 6, _set_gl_proc_address)
    } else {
        fmt.println("[GPU] OpenGL not supported on this platform")
        return nil, false
    }

    // Verify compute shader support (OpenGL 4.3+).
    // On macOS the cap is 4.1 so DispatchCompute will be nil → graceful fallback.
    if gl.DispatchCompute == nil {
        fmt.println("[GPU] OpenGL 4.3 compute shaders not available on this platform/driver")
        return nil, false
    }

    // Compile and link the compute shader from disk.
    // load_compute_file returns false if the shader source is missing,
    // the driver does not support compute shaders, or compilation fails.
    program, ok := gl.load_compute_file("assets/shaders/raytrace.comp")
    if !ok {
        fmt.println("[GPU] Failed to compile compute shader — falling back to CPU")
        return nil, false
    }
    fmt.println("[GPU] Compute shader compiled OK")

    b := new(GPUBackend)
    b.program       = program
    b.width         = cam.image_width
    b.height        = cam.image_height
    b.total_samples = samples

    // Allocate four GL buffer objects (one UBO + three SSBOs).
    gl.GenBuffers(1, &b.ubo_camera)
    gl.GenBuffers(1, &b.ssbo_spheres)
    gl.GenBuffers(1, &b.ssbo_bvh)
    gl.GenBuffers(1, &b.ssbo_output)

    // ── UBO: camera parameters ────────────────────────────────────────────
    // Uploaded once here; only current_sample changes per dispatch, so
    // dispatch re-uploads the full 128-byte struct (cheap).
    b.cached_uniforms = _render_camera_to_gpu_uniforms(cam, samples, 0)
    gl.BindBuffer(gl.UNIFORM_BUFFER, b.ubo_camera)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(GPUCameraUniforms), &b.cached_uniforms, gl.DYNAMIC_DRAW)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    // ── SSBO: sphere array ────────────────────────────────────────────────
    // Layout: [4]i32 header (sphere_count, pad×3) then []GPUSphere.
    // The header count is read in GLSL as SpheresBlock.sphere_count.
    spheres := scene_to_gpu_spheres(objects)
    defer delete(spheres)

    sphere_header    := [4]i32{i32(len(spheres)), 0, 0, 0}
    sphere_body_size := len(spheres) * size_of(GPUSphere)
    sphere_total     := size_of([4]i32) + sphere_body_size

    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, b.ssbo_spheres)
    gl.BufferData(gl.SHADER_STORAGE_BUFFER, sphere_total, nil, gl.STATIC_DRAW)
    gl.BufferSubData(gl.SHADER_STORAGE_BUFFER, 0, size_of([4]i32), &sphere_header)
    if sphere_body_size > 0 {
        gl.BufferSubData(gl.SHADER_STORAGE_BUFFER, size_of([4]i32), sphere_body_size, raw_data(spheres))
    }

    // ── SSBO: BVH node array ──────────────────────────────────────────────
    bvh_header    := [4]i32{i32(len(lin_bvh)), 0, 0, 0}
    bvh_body_size := len(lin_bvh) * size_of(LinearBVHNode)
    bvh_total     := size_of([4]i32) + bvh_body_size

    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, b.ssbo_bvh)
    gl.BufferData(gl.SHADER_STORAGE_BUFFER, bvh_total, nil, gl.STATIC_DRAW)
    gl.BufferSubData(gl.SHADER_STORAGE_BUFFER, 0, size_of([4]i32), &bvh_header)
    if bvh_body_size > 0 {
        gl.BufferSubData(gl.SHADER_STORAGE_BUFFER, size_of([4]i32), bvh_body_size, raw_data(lin_bvh))
    }

    // ── SSBO: output accumulation buffer ─────────────────────────────────
    // vec4 (16 bytes) per pixel, initialised to zero.
    // Each dispatch accumulates one sample: pixels[i] += vec4(colour, 0).
    // Readback divides by current_sample to get the running average.
    pixel_count  := cam.image_width * cam.image_height
    output_total := pixel_count * size_of([4]f32)
    zeroes       := make([][4]f32, pixel_count)
    defer delete(zeroes)

    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, b.ssbo_output)
    gl.BufferData(gl.SHADER_STORAGE_BUFFER, output_total, raw_data(zeroes), gl.DYNAMIC_COPY)
    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, 0)

    fmt.printf("[GPU] Buffers ready — %d spheres, %d BVH nodes, %dx%d px\n",
        len(spheres), len(lin_bvh), cam.image_width, cam.image_height)
    return b, true
}

// ── gpu_backend_dispatch ─────────────────────────────────────────────────────

// gpu_backend_dispatch adds one progressive sample to the accumulation buffer.
// Call once per frame while current_sample < total_samples.
//
// The dispatch is asynchronous from the CPU's perspective; the GPU executes
// the compute shader in parallel.  The SHADER_STORAGE_BARRIER_BIT barrier
// inserted at the end ensures subsequent GetBufferSubData calls see the
// completed writes (see gpu_backend_readback).
gpu_backend_dispatch :: proc(b: ^GPUBackend) {
    // Advance the sample counter and push the updated UBO.
    b.current_sample += 1
    b.cached_uniforms.current_sample = i32(b.current_sample)

    gl.BindBuffer(gl.UNIFORM_BUFFER, b.ubo_camera)
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(GPUCameraUniforms), &b.cached_uniforms)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    // Bind the shader and all buffer objects to their declared binding points.
    gl.UseProgram(b.program)
    gl.BindBufferBase(gl.UNIFORM_BUFFER,         0, b.ubo_camera)
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER,  1, b.ssbo_spheres)
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER,  2, b.ssbo_bvh)
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER,  3, b.ssbo_output)

    // Dispatch: one 8×8 workgroup per 8×8 pixel tile.
    // Shader discards out-of-bounds invocations (pixel >= width/height).
    groups_x := u32((b.width  + 7) / 8)
    groups_y := u32((b.height + 7) / 8)
    gl.DispatchCompute(groups_x, groups_y, 1)

    // Memory barrier: all SSBO writes in the compute shader are made visible
    // before any subsequent buffer reads (e.g. GetBufferSubData in readback).
    gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT)
}

// ── gpu_backend_readback ─────────────────────────────────────────────────────

// gpu_backend_readback reads the accumulated SSBO, divides each pixel by the
// number of samples dispatched so far, applies gamma correction (sqrt, γ=2.0),
// and writes the result as RGBA bytes into out[].
//
// out must be pre-allocated with at least width×height elements.
// No vendor:raylib import — out is plain [][4]u8; the UI layer casts it to
// []rl.Color and calls rl.UpdateTexture directly (see app.odin).
gpu_backend_readback :: proc(b: ^GPUBackend, out: [][4]u8) {
    if b == nil { return }
    pixel_count := b.width * b.height
    if len(out) < pixel_count { return }

    // Read the raw float accumulation buffer from GPU memory.
    tmp := make([][4]f32, pixel_count)
    defer delete(tmp)

    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, b.ssbo_output)
    gl.GetBufferSubData(gl.SHADER_STORAGE_BUFFER, 0,
        pixel_count * size_of([4]f32), raw_data(tmp))
    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, 0)

    inv := f32(1.0) / f32(max(b.current_sample, 1))

    for i in 0..<pixel_count {
        // Divide by sample count to get the running average.
        r := tmp[i][0] * inv
        g := tmp[i][1] * inv
        bv := tmp[i][2] * inv

        // Gamma correction (γ = 2.0): sqrt maps linear light to display gamma.
        // Mirrors linear_to_gamma in vector3.odin.
        r  = math.sqrt(clamp(r,  0, 1))
        g  = math.sqrt(clamp(g,  0, 1))
        bv = math.sqrt(clamp(bv, 0, 1))

        out[i] = [4]u8{
            u8(r  * 255.999),
            u8(g  * 255.999),
            u8(bv * 255.999),
            255,
        }
    }
}

// ── gpu_backend_destroy ──────────────────────────────────────────────────────

// gpu_backend_destroy deletes all GL objects associated with the backend and
// frees the backend struct itself.  Call after the render is complete or when
// tearing down the application.
gpu_backend_destroy :: proc(b: ^GPUBackend) {
    if b == nil { return }
    gl.DeleteProgram(b.program)
    gl.DeleteBuffers(1, &b.ubo_camera)
    gl.DeleteBuffers(1, &b.ssbo_spheres)
    gl.DeleteBuffers(1, &b.ssbo_bvh)
    gl.DeleteBuffers(1, &b.ssbo_output)
    free(b)
}

// ── OpenGL backend vtable registration ───────────────────────────────────────

@(private)
_ogl_init :: proc(cam: ^Render_Camera, world: []Object, bvh: []LinearBVHNode, total: int) -> (rawptr, bool) {
    b, ok := gpu_backend_init(cam, world, bvh, total)
    return b, ok
}
@(private) _ogl_dispatch    :: proc(s: rawptr) { gpu_backend_dispatch((^GPUBackend)(s)) }
@(private) _ogl_readback    :: proc(s: rawptr, out: [][4]u8) { gpu_backend_readback((^GPUBackend)(s), out) }
@(private) _ogl_destroy     :: proc(s: rawptr) { gpu_backend_destroy((^GPUBackend)(s)) }
@(private) _ogl_get_samples :: proc(s: rawptr) -> (int, int) {
    b := (^GPUBackend)(s)
    return b.current_sample, b.total_samples
}

OPENGL_RENDERER_API :: GpuRendererApi{
    init        = _ogl_init,
    dispatch    = _ogl_dispatch,
    readback    = _ogl_readback,
    destroy     = _ogl_destroy,
    get_samples = _ogl_get_samples,
}
