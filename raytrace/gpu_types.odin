package raytrace

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
    program:         u32,  // linked compute shader program
    ssbo_spheres:    u32,  // SSBO: [4]i32 header then []GPUSphere
    ssbo_bvh:        u32,  // SSBO: [4]i32 header then []LinearBVHNode
    ssbo_output:     u32,  // SSBO: vec4 per pixel (RGB accumulation)
    ubo_camera:      u32,  // UBO: GPUCameraUniforms (std140)
    width:           int,
    height:          int,
    current_sample:  int,  // number of samples dispatched so far
    total_samples:   int,  // target sample count
    // Cached UBO contents so dispatch can update only current_sample.
    cached_uniforms: GPUCameraUniforms,
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

// GPUSphere packs a sphere and its material into 48 bytes.
//
// albedo stores reflectance for Lambertian and Metallic.
// For Dielectric albedo is {1,1,1} (fully white, no colour absorption).
// fuzz_or_ior carries fuzz radius for Metallic, IOR for Dielectric.
//
// Extensibility note:
//   _pad[3] reserves space for three future f32 fields, e.g.
//     _pad[0] = texture_id (cast to f32 or add a second i32 field)
//     _pad[1] = emission_strength for emissive materials
//   No GLSL changes required when adding fields within the existing 48 bytes.
GPUSphere :: struct #packed {
    center:      [3]f32,
    radius:      f32,
    albedo:      [3]f32,
    mat_type:    i32,
    fuzz_or_ior: f32,
    _pad:        [3]f32,   // reserved for future material params / texture_id
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
        gpu.center = s.center
        gpu.radius = s.radius

        switch m in s.material {
        case lambertian:
            gpu.mat_type    = MAT_LAMBERTIAN
            gpu.albedo      = m.albedo
            gpu.fuzz_or_ior = 0.0
        case metallic:
            gpu.mat_type    = MAT_METALLIC
            gpu.albedo      = m.albedo
            gpu.fuzz_or_ior = m.fuzz
        case dielectric:
            gpu.mat_type    = MAT_DIELECTRIC
            gpu.albedo      = [3]f32{1, 1, 1}
            gpu.fuzz_or_ior = m.ref_idx
        case:
            // Unknown material: default to white Lambertian
            gpu.mat_type = MAT_LAMBERTIAN
            gpu.albedo   = [3]f32{1, 1, 1}
        }

        result[idx] = gpu
        idx += 1
    }
    return result
}
