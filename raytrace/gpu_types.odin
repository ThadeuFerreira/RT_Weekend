package raytrace

import "RT_Weekend:core"

// ============================================================
// GPU-compatible type definitions
// ============================================================
//
// These structs are designed to be uploadable to OpenGL SSBOs
// and UBOs with std430 / std140 layout.  Each struct is
// annotated with its size so it is easy to verify alignment.
//
// Step 1 — LinearBVHNode (32 bytes, SSBO-compatible)
// Step 2 — GPUSphere, GPUCameraUniforms, material constants
// ============================================================

// GPUBackend holds all OpenGL state for the GPU compute-shader path.
//
// Lifecycle:
//   gpu_backend_init   — compile shader, create buffers, upload scene
//   gpu_backend_dispatch — bind + dispatch one sample per frame
//   gpu_backend_readback — read accumulated buffer → RGBA bytes
//   gpu_backend_destroy  — delete GL objects, free struct
//
// All fields are private implementation details; callers use the four
// procedures above. The struct lives in gpu_types.odin so that
// RenderSession (in camera.odin) can hold a pointer to it without
// requiring a separate compilation unit.
GPUBackend :: struct {
    program:           u32,  // linked compute shader program
    ssbo_spheres:      u32,  // SSBO: [4]i32 header then []GPUSphere
    ssbo_bvh:          u32,  // SSBO: [4]i32 header then []LinearBVHNode
    ssbo_output:       u32,  // SSBO: vec4 per pixel (RGB accumulation)
    ubo_camera:        u32,  // UBO: GPUCameraUniforms (std140)
    width:             int,
    height:            int,
    current_sample:    int,  // number of samples dispatched so far
    total_samples:     int,  // target sample count
    // Cached UBO contents so dispatch can update only current_sample.
    cached_uniforms:   GPUCameraUniforms,
    // Timing (nanoseconds) accumulated across all dispatch/readback calls.
    dispatch_total_ns: i64,
    readback_total_ns: i64,
}

// ---- Step 1 ------------------------------------------------

// LinearBVHNode is a 32-byte, cache-friendly BVH node.
//
// Internal node layout:
//   left_idx        = index of left  child in the nodes array
//   right_or_obj_idx = index of right child in the nodes array
//
// Leaf node layout:
//   left_idx        = -1  (sentinel: "I am a leaf")
//   right_or_obj_idx = -(object_index + 1)  (negative encodes the sphere index)
//
// The flat array produced by flatten_bvh is traversed iteratively
// by bvh_hit_linear — no pointer chasing, no recursion.
//
// Extensibility note:
//   To add TriangleMesh leaves, add a second sentinel value for
//   left_idx (e.g. -2) and store the triangle index in
//   right_or_obj_idx the same way.  The traversal loop in
//   bvh_hit_linear only needs one extra case per new primitive type.
LinearBVHNode :: struct #packed {
    aabb_min:        [3]f32,
    right_or_obj_idx: i32,       // child index (internal) or -(obj+1) (leaf)
    aabb_max:        [3]f32,
    left_idx:        i32,        // child index (internal) or -1 (leaf)
}

// ---- Step 2 ------------------------------------------------

// Material type constants.
// Add new entries here; also add a GLSL case in raytrace.comp
// and an Odin case in scene_to_gpu_spheres.
MAT_LAMBERTIAN :: i32(0)   // Diffuse: scatter in cosine-weighted hemisphere
MAT_METALLIC   :: i32(1)   // Specular: reflect + fuzz perturbation
MAT_DIELECTRIC :: i32(2)   // Refract/reflect via Schlick approximation (glass)
// Future: MAT_EMISSIVE :: i32(3), MAT_PBR_GLOSSY :: i32(4), …

// Texture type for Lambertian (GPU only; must match raytrace.comp).
TEX_CONSTANT :: i32(0)  // use albedo as-is
TEX_CHECKER  :: i32(1)  // 3D checker from tex_scale, tex_even, tex_odd


// GPURay mirrors the GLSL `Ray` struct under std430 layout (32 bytes).
// GLSL vec3 has base alignment 16, so a 4-byte pad is required between
// origin and dir.  Without it the CPU (packed, 28 bytes) and the GPU
// (std430, 32 bytes) would be misaligned for dir and time.
GPURay :: struct #packed {
    origin: [3]f32,
    _pad0:  f32,        // 4 bytes: matches GLSL implicit padding after vec3 origin
    dir:    [3]f32,
    time:   f32,        // 32 bytes total — matches GLSL Ray in std430
}

// GPUSphere mirrors the GLSL `Sphere` struct under std430 layout (128 bytes).
//
// GLSL vec3 has base alignment 16. Texture fields follow _pad so Lambertian
// can use ConstantTexture (albedo only) or CheckerTexture (tex_*).
//
// Field offsets (must match raytrace.comp Sphere struct exactly):
//   center (GPURay)  : 0   – 31   (32 bytes)
//   radius           : 32  – 35   (4 bytes)
//   _pad_r[3]        : 36  – 47   (12 bytes, padding before vec3 albedo)
//   albedo           : 48  – 59   (12 bytes)
//   mat_type         : 60  – 63   (4 bytes)
//   fuzz_or_ior      : 64  – 67   (4 bytes)
//   _pad[3]          : 68  – 79   (12 bytes; _pad[0] = is_moving flag)
//   tex_type         : 80  – 83   (4 bytes)
//   tex_scale        : 84  – 87   (4 bytes)
//   _pad_tex[2]      : 88  – 95   (8 bytes, align tex_even to 16)
//   tex_even         : 96  – 107  (12 bytes)
//   _pad_even        : 108 – 111  (4 bytes)
//   tex_odd          : 112 – 123  (12 bytes)
//   _pad_odd         : 124 – 127  (4 bytes)
GPUSphere :: struct #packed {
    center:      GPURay,
    radius:      f32,
    _pad_r:      [3]f32,   // padding: align albedo (vec3) to 16-byte boundary
    albedo:      [3]f32,
    mat_type:    i32,
    fuzz_or_ior: f32,
    _pad:        [3]f32,   // _pad[0] = is_moving flag (1.0=moving, 0.0=static)
    tex_type:    i32,      // TEX_CONSTANT or TEX_CHECKER (Lambertian only)
    tex_scale:   f32,
    _pad_tex:    [2]f32,   // align tex_even to 16
    tex_even:    [3]f32,
    _pad_even:   f32,
    tex_odd:     [3]f32,
    _pad_odd:    f32,
}

// GPUCameraUniforms is uploaded as a UBO (std140).
// Padding fields keep each vec3 on a 16-byte boundary as required by std140.
// Must match the layout(std140) CameraBlock in raytrace.comp exactly.
GPUCameraUniforms :: struct #packed {
    camera_center:  [3]f32, _p0: f32,   // 16 bytes
    pixel00_loc:    [3]f32, _p1: f32,   // 16 bytes
    pixel_delta_u:  [3]f32, _p2: f32,   // 16 bytes
    pixel_delta_v:  [3]f32, _p3: f32,   // 16 bytes
    defocus_disk_u: [3]f32, defocus_angle: f32,  // 16 bytes (defocus_angle packed in w)
    defocus_disk_v: [3]f32, _p4: f32,   // 16 bytes
    width:          i32,
    height:         i32,
    max_depth:      i32,
    total_samples:  i32,
    current_sample: i32,
    _pad:           [3]i32,             // align to 16 bytes
}

// scene_to_gpu_spheres converts the Odin-union Object slice to a flat []GPUSphere
// suitable for uploading to a GL SSBO.
//
// Only Sphere objects are included (Cube is not yet supported on the GPU path).
// The resulting slice must be freed by the caller (delete(result)).
scene_to_gpu_spheres :: proc(objects: []Object) -> []GPUSphere {
    // Count spheres first so we allocate exactly.
    count := 0
    for o in objects {
        if _, ok := o.(Sphere); ok { count += 1 }
    }

    result := make([]GPUSphere, count)
    idx := 0
    for o in objects {
        s, ok := o.(Sphere)
        if !ok { continue }

        gpu := GPUSphere{}
        gpu.center = GPURay{
            origin = s.center,
            dir    = s.center1 - s.center,
            time   = 0,
        }
        gpu._pad[0] = s.is_moving ? 1.0 : 0.0
        gpu.radius = s.radius

        switch m in s.material {
        case lambertian:
            gpu.mat_type    = MAT_LAMBERTIAN
            gpu.fuzz_or_ior = 0.0
            switch tex in m.albedo {
            case core.ConstantTexture:
                gpu.tex_type  = TEX_CONSTANT
                gpu.albedo    = tex.color
            case  core.CheckerTexture:
                // Used when ground or any Lambertian has CheckerTexture (e.g. "Next Week: Checkers Texture" example).
                gpu.tex_type  = TEX_CHECKER
                gpu.albedo    = [3]f32{0, 0, 0}
                gpu.tex_scale = tex.scale
                if gpu.tex_scale == 0 {
                    // Keep checker sampling stable if a scene provides an invalid zero scale.
                    gpu.tex_scale = 1.0
                }
                gpu.tex_even  = tex.even
                gpu.tex_odd   = tex.odd
            case:
                // Future texture types or fallback: sample at origin so GPU gets a single colour; shader uses TEX_CONSTANT.
                gpu.tex_type  = TEX_CONSTANT
                //Pinkish color
                gpu.albedo    = [3]f32{1, 0.5, 0.5}
            }
        case metallic:
            gpu.mat_type    = MAT_METALLIC
            gpu.albedo      = m.albedo
            gpu.fuzz_or_ior = m.fuzz
            gpu.tex_type    = TEX_CONSTANT
        case dielectric:
            gpu.mat_type    = MAT_DIELECTRIC
            gpu.albedo      = [3]f32{1, 1, 1}
            gpu.fuzz_or_ior = m.ref_idx
            gpu.tex_type    = TEX_CONSTANT
        case:
            // Unknown material: default to white Lambertian (constant)
            gpu.mat_type  = MAT_LAMBERTIAN
            gpu.albedo    = [3]f32{1, 1, 1}
            gpu.tex_type  = TEX_CONSTANT
            gpu.tex_scale = 1.0
            gpu.tex_even  = [3]f32{1, 1, 1}
            gpu.tex_odd   = [3]f32{1, 1, 1}
        }

        result[idx] = gpu
        idx += 1
    }
    return result
}
