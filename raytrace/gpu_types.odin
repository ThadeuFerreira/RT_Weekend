package raytrace

import "RT_Weekend:core"

// ============================================================
// GPU-compatible type definitions
// ============================================================
//
// These structs are designed to be uploadable to Vulkan SSBOs
// and UBOs with std430 / std140 layout.  Each struct is
// annotated with its size so it is easy to verify alignment.
//
// Step 1 — LinearBVHNode (32 bytes, SSBO-compatible)
// Step 2 — GPUSphere, GPUCameraUniforms, material constants
// ============================================================

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
// Leaf sentinels for GPU BVH traversal (must match raytrace_vk.comp).
// left_idx == LEAF_SPHERE => right_or_obj_idx = -(sphere_index + 1)
// left_idx == LEAF_QUAD   => right_or_obj_idx = -(quad_index + 1)
// left_idx == LEAF_VOLUME => right_or_obj_idx = -(volume_index + 1)
LEAF_SPHERE :: i32(-1)
LEAF_QUAD   :: i32(-2)
LEAF_VOLUME :: i32(-3)

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
// Add new entries here; also add a GLSL case in raytrace_vk.comp
// and an Odin case in scene_to_gpu_spheres.
MAT_LAMBERTIAN :: i32(0)   // Diffuse: scatter in cosine-weighted hemisphere
MAT_METALLIC   :: i32(1)   // Specular: reflect + fuzz perturbation
MAT_DIELECTRIC :: i32(2)   // Refract/reflect via Schlick approximation (glass)
MAT_DIFFUSE_LIGHT :: i32(3) // Emissive: returns emit color, does not scatter
MAT_ISOTROPIC     :: i32(4) // Volumetric: scatter uniformly (used by constant_medium)
// Future: MAT_PBR_GLOSSY :: i32(5), …

// Texture type for Lambertian (GPU only; must match raytrace_vk.comp).
TEX_CONSTANT :: i32(0)  // use albedo as-is
TEX_CHECKER  :: i32(1)  // 3D checker from tex_scale, tex_even, tex_odd
TEX_IMAGE    :: i32(2)  // sample from bound 2D image texture using sphere UV
TEX_NOISE    :: i32(3)  // fBm Perlin noise; tex_scale = spatial frequency
TEX_MARBLE   :: i32(4)  // sin-modulated turbulence; tex_scale = stripe frequency

// Maximum number of distinct image textures on GPU (each sphere can reference one via tex_index).
MAX_GPU_IMAGE_TEXTURES :: 8


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

// GPUSphere mirrors the GLSL `Sphere` struct under std430 layout (144 bytes).
//
// GLSL vec3 has base alignment 16. Texture fields follow _pad so Lambertian
// can use ConstantTexture (albedo only) or CheckerTexture (tex_*).
//
// std430 array stride rule: struct stride = ceil(size / alignment) * alignment.
// Struct alignment = 16 (largest member alignment = vec3). Size without final
// padding = 136 bytes. 136 % 16 = 8 ≠ 0 → GPU adds implicit 8-byte trailing
// pad → stride = 144. The CPU struct must match: _pad_stride is 12 bytes (not 4)
// so that both sides use 144 bytes and sphere[N] is at offset N*144.
//
// Field offsets (must match raytrace_vk.comp Sphere struct exactly):
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
//   tex_index        : 128 – 131  (4 bytes) — which image texture slot for TEX_IMAGE
//   _pad_stride      : 132 – 143  (12 bytes) — pads struct to 144 = ceil(136/16)*16
GPUSphere :: struct #packed {
    center:      GPURay,
    radius:      f32,
    _pad_r:      [3]f32,   // padding: align albedo (vec3) to 16-byte boundary
    albedo:      [3]f32,
    mat_type:    i32,
    fuzz_or_ior: f32,
    _pad:        [3]f32,   // _pad[0] = is_moving flag (1.0=moving, 0.0=static)
    tex_type:    i32,      // TEX_CONSTANT or TEX_CHECKER or TEX_IMAGE (Lambertian only)
    tex_scale:   f32,
    _pad_tex:    [2]f32,   // align tex_even to 16
    tex_even:    [3]f32,
    _pad_even:   f32,
    tex_odd:     [3]f32,
    _pad_odd:    f32,
    tex_index:   i32,     // image texture slot index for TEX_IMAGE (0 = first bound texture)
    _pad_stride: [3]f32,  // pads struct to 144 bytes = ceil(136/16)*16; matches std430 array stride
}

// GPUQuad mirrors the GLSL Quad struct for the compute shader (std430).
// Geometry: Q, u, v, w, normal, D. Material: same as GPUSphere (mat_type, albedo, fuzz_or_ior, tex_*).
// Quads support Lambertian (constant/checker only), Metallic, Dielectric. No motion blur.
//
// std430: vec3 has base alignment 16. After _pad7[2] we are at offset 132; next 16-byte boundary is 144,
// so GLSL inserts 12 bytes implicit padding before tex_even. We must match that so mat_type/albedo/tex_*
// are read at the same offsets. Struct size = 176 bytes (array stride).
GPUQuad :: struct #packed {
    Q:         [3]f32,
    _pad0:     f32,
    u:         [3]f32,
    _pad1:     f32,
    v:         [3]f32,
    _pad2:     f32,
    w:         [3]f32,
    _pad3:     f32,
    normal:    [3]f32,
    _pad4:     f32,
    D:         f32,
    mat_type:  i32,
    _pad5:     [2]f32,
    albedo:    [3]f32,
    _pad6:     f32,
    fuzz_or_ior: f32,
    tex_type:  i32,
    tex_scale: f32,
    _pad7:     [2]f32,
    _pad_align_tex: [3]f32, // 12 bytes: matches GLSL implicit padding so tex_even starts at offset 144
    tex_even:  [3]f32,
    _pad8:     f32,
    tex_odd:   [3]f32,
    _pad9:     f32,
}

// GPUVolume describes one constant-density volume for the compute shader.
// Boundary is 6 quads stored in a separate SSBO starting at quad_start_index.
// std430: struct alignment 16 (vec3); size must be 48 so array stride is 48 (no implicit pad).
GPUVolume :: struct #packed {
    density:       f32,
    _pad_d:        [3]f32,   // align albedo to 16
    albedo:        [3]f32,
    _pad_a:        f32,
    quad_start:    i32,      // index into volume_quads (6 consecutive GPUQuads)
    _pad_stride:   [3]i32,   // pad to 48 bytes for std430 array stride
}

// scene_to_gpu_volumes builds GPUVolume and boundary GPUQuad arrays from world.
// Volumes are ConstantMedium objects; each volume's boundary_bvh is traversed to
// collect 6 quads (from append_box_transformed). Caller must delete both returned slices.
scene_to_gpu_volumes :: proc(objects: []Object) -> (volumes: []GPUVolume, volume_quads: []GPUQuad) {
    count := 0
    for o in objects {
        if _, ok := o.(ConstantMedium); ok { count += 1 }
    }
    if count == 0 {
        return nil, nil
    }
    volumes = make([]GPUVolume, count)
    boundary_quads := make([dynamic]Quad)
    defer delete(boundary_quads)
    idx := 0
    for o in objects {
        vol, ok := o.(ConstantMedium)
        if !ok { continue }
        collect_quads_from_bvh(vol.boundary_bvh, &boundary_quads)
        d := vol.density
        if d <= 0 { d = 0.01 }
        volumes[idx] = GPUVolume{
            density    = d,
            albedo     = vol.albedo,
            quad_start = i32(len(boundary_quads) - 6),
        }
        idx += 1
    }
    volume_quads = make([]GPUQuad, len(boundary_quads))
    for q, i in boundary_quads {
        volume_quads[i] = GPUQuad{
            Q = q.Q, u = q.u, v = q.v, w = q.w, normal = q.normal, D = q.D,
            mat_type = MAT_LAMBERTIAN, albedo = [3]f32{0.73, 0.73, 0.73},
            tex_type = TEX_CONSTANT,
        }
    }
    return volumes, volume_quads
}

// GPUCameraUniforms is uploaded as a UBO (std140).
// Padding fields keep each vec3 on a 16-byte boundary as required by std140.
// Must match the layout(std140) CameraBlock in raytrace_vk.comp exactly.
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
    background:     [3]f32, _p5: f32,   // miss color (flat background)
}

// _camera_to_gpu_uniforms converts Camera fields to the flat GPUCameraUniforms
// struct that matches the CameraBlock UBO layout in raytrace_vk.comp.
// defocus_angle is packed into the .w component of defocus_disk_u (see shader).
_camera_to_gpu_uniforms :: proc(cam: ^Camera, total_samples, current_sample: int) -> GPUCameraUniforms {
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
        background     = cam.background,
    }
}

// collect_image_textures_ordered walks the world and returns (1) a list of unique
// image textures in encounter order and (2) path -> slot index for each path.
// Used by the GPU backend to upload multiple textures and set GPUSphere.tex_index.
// Caller must delete the returned dynamic and map.
collect_image_textures_ordered :: proc(objects: []Object) -> (images: [dynamic]^Texture_Image, path_to_index: map[string]int) {
    path_to_index = make(map[string]int)
    images = make([dynamic]^Texture_Image)
    for o in objects {
        s, ok := o.(Sphere)
        if !ok { continue }
        m, ok_lambertian := s.material.(lambertian)
        if !ok_lambertian { continue }
        tex, ok_img := m.albedo.(ImageTextureRuntime)
        if !ok_img || tex.image == nil || len(tex.path) == 0 { continue }
        if tex.path not_in path_to_index {
            path_to_index[tex.path] = len(images)
            append(&images, tex.image)
        }
    }
    return
}

// pack_image_textures_for_gpu packs image pixel data into a flat i32 array
// for upload as a Vulkan SSBO (binding 7).
// Layout (after the standard [4]i32 header with image_count written by caller):
//   metadata: images_count * 4 ints per image (width, height, pixel_data_offset, 0)
//   pixel data: packed RGB bytes as i32 ((R << 16) | (G << 8) | B)
// pixel_data_offset is relative to the start of image_tex_data[] in the SSBO.
// Returns nil when images is empty. Caller must delete the returned slice.
pack_image_textures_for_gpu :: proc(images: []^Texture_Image) -> []i32 {
    if len(images) == 0 { return nil }

    total_pixels := 0
    for i in 0 ..< len(images) {
        w := texture_image_width(images[i])
        h := texture_image_height(images[i])
        total_pixels += w * h
    }

    metadata_ints := len(images) * 4
    data := make([]i32, metadata_ints + total_pixels)

    pixel_offset := metadata_ints
    for i in 0 ..< len(images) {
        img := images[i]
        w := texture_image_width(img)
        h := texture_image_height(img)

        base := i * 4
        data[base + 0] = i32(w)
        data[base + 1] = i32(h)
        data[base + 2] = i32(pixel_offset)
        data[base + 3] = 0

        bytes := texture_image_byte_slice(img)
        for py in 0 ..< h {
            for px in 0 ..< w {
                idx := (py * w + px) * 3
                if idx + 2 < len(bytes) {
                    r := i32(bytes[idx])
                    g := i32(bytes[idx + 1])
                    b := i32(bytes[idx + 2])
                    data[pixel_offset + py * w + px] = (r << 16) | (g << 8) | b
                }
            }
        }
        pixel_offset += w * h
    }
    return data
}

// scene_to_gpu_spheres converts the Odin-union Object slice to a flat []GPUSphere
// suitable for uploading to a Vulkan SSBO.
//
// When path_to_index is non-nil, ImageTextureRuntime spheres get tex_index set from
// it so each object can reference a different image texture on the GPU.
// When world_to_sphere_gpu is non-nil and len(world_to_sphere_gpu)==len(objects),
// each element is set to the GPU sphere index (0..count-1) for spheres or -1 for non-spheres.
// The resulting slice must be freed by the caller (delete(result)).
scene_to_gpu_spheres :: proc(objects: []Object, path_to_index: map[string]int = nil, world_to_sphere_gpu: []int = nil) -> []GPUSphere {
    // Count spheres first so we allocate exactly.
    count := 0
    for o in objects {
        if _, ok := o.(Sphere); ok { count += 1 }
    }

    result := make([]GPUSphere, count)
    idx := 0
    for i in 0..<len(objects) {
        o := objects[i]
        s, ok := o.(Sphere)
        if !ok {
            if world_to_sphere_gpu != nil && len(world_to_sphere_gpu) == len(objects) {
                world_to_sphere_gpu[i] = -1
            }
            continue
        }

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
            case ConstantTexture:
                gpu.tex_type  = TEX_CONSTANT
                gpu.albedo    = tex.color
                gpu.tex_index = 0
            case CheckerTexture:
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
                gpu.tex_index = 0
            case ImageTextureRuntime:
                if path_to_index != nil && tex.path in path_to_index {
                    gpu.tex_type   = TEX_IMAGE
                    gpu.albedo     = [3]f32{1, 1, 1}
                    gpu.tex_index  = i32(path_to_index[tex.path])
                } else {
                    // Path missing from cache or no path_to_index: fallback to grey so we never sample an unbound texture.
                    gpu.tex_type   = TEX_CONSTANT
                    gpu.albedo     = [3]f32{0.5, 0.5, 0.5}
                    gpu.tex_index  = 0
                }
            case NoiseTexture:
                gpu.tex_type  = TEX_NOISE
                gpu.tex_scale = tex.scale != 0 ? tex.scale : 4.0
                gpu.albedo    = [3]f32{0, 0, 0}
                gpu.tex_index = 0
            case MarbleTexture:
                gpu.tex_type  = TEX_MARBLE
                gpu.tex_scale = tex.scale != 0 ? tex.scale : 4.0
                gpu.albedo    = [3]f32{0, 0, 0}
                gpu.tex_index = 0
            }
        case metallic:
            gpu.mat_type    = MAT_METALLIC
            gpu.albedo      = m.albedo
            gpu.fuzz_or_ior = m.fuzz
            gpu.tex_type    = TEX_CONSTANT
            gpu.tex_index   = 0
        case dielectric:
            gpu.mat_type    = MAT_DIELECTRIC
            gpu.albedo      = [3]f32{1, 1, 1}
            gpu.fuzz_or_ior = m.ref_idx
            gpu.tex_type    = TEX_CONSTANT
            gpu.tex_index   = 0
        case diffuse_light:
            gpu.mat_type    = MAT_DIFFUSE_LIGHT
            gpu.albedo      = m.emit
            gpu.fuzz_or_ior = 0.0
            gpu.tex_type    = TEX_CONSTANT
            gpu.tex_index   = 0
        case isotropic:
            gpu.mat_type    = MAT_ISOTROPIC
            gpu.albedo      = m.albedo
            gpu.fuzz_or_ior = 0.0
            gpu.tex_type    = TEX_CONSTANT
            gpu.tex_index   = 0
        case:
            // Unknown material: default to white Lambertian (constant)
            gpu.mat_type  = MAT_LAMBERTIAN
            gpu.albedo    = [3]f32{1, 1, 1}
            gpu.tex_type  = TEX_CONSTANT
            gpu.tex_scale = 1.0
            gpu.tex_even  = [3]f32{1, 1, 1}
            gpu.tex_odd   = [3]f32{1, 1, 1}
            gpu.tex_index = 0
        }

        result[idx] = gpu
        if world_to_sphere_gpu != nil && len(world_to_sphere_gpu) == len(objects) {
            world_to_sphere_gpu[i] = idx
        }
        idx += 1
    }
    return result
}

// scene_to_gpu_quads converts Quad objects from the Object slice to a flat []GPUQuad.
// When world_to_quad_gpu is non-nil and len(world_to_quad_gpu)==len(objects), each element
// is set to the GPU quad index for quads or -1 for non-quads.
// Caller must delete(result).
scene_to_gpu_quads :: proc(objects: []Object, world_to_quad_gpu: []int = nil) -> []GPUQuad {
    count := 0
    for o in objects {
        if _, ok := o.(Quad); ok { count += 1 }
    }
    result := make([]GPUQuad, count)
    idx := 0
    for i in 0..<len(objects) {
        q, ok := objects[i].(Quad)
        if !ok {
            if world_to_quad_gpu != nil && len(world_to_quad_gpu) == len(objects) {
                world_to_quad_gpu[i] = -1
            }
            continue
        }
        gpu := GPUQuad{
            Q = q.Q, u = q.u, v = q.v, w = q.w, normal = q.normal, D = q.D,
        }
        switch m in q.material {
        case lambertian:
            gpu.mat_type    = MAT_LAMBERTIAN
            gpu.fuzz_or_ior = 0.0
            switch tex in m.albedo {
            case ConstantTexture:
                gpu.tex_type  = TEX_CONSTANT
                gpu.albedo    = tex.color
                gpu.tex_scale = 1.0
            case CheckerTexture:
                gpu.tex_type  = TEX_CHECKER
                gpu.albedo    = [3]f32{0, 0, 0}
                gpu.tex_scale = tex.scale
                if gpu.tex_scale == 0 { gpu.tex_scale = 1.0 }
                gpu.tex_even  = tex.even
                gpu.tex_odd   = tex.odd
            case ImageTextureRuntime:
                gpu.tex_type  = TEX_CONSTANT
                gpu.albedo    = [3]f32{0.5, 0.5, 0.5}
                gpu.tex_scale = 1.0
            case NoiseTexture:
                gpu.tex_type  = TEX_NOISE
                gpu.tex_scale = tex.scale != 0 ? tex.scale : 4.0
            case MarbleTexture:
                gpu.tex_type  = TEX_MARBLE
                gpu.tex_scale = tex.scale != 0 ? tex.scale : 4.0
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
        case diffuse_light:
            gpu.mat_type    = MAT_DIFFUSE_LIGHT
            gpu.albedo      = m.emit
            gpu.fuzz_or_ior = 0.0
            gpu.tex_type    = TEX_CONSTANT
        case isotropic:
            gpu.mat_type    = MAT_ISOTROPIC
            gpu.albedo      = m.albedo
            gpu.fuzz_or_ior = 0.0
            gpu.tex_type    = TEX_CONSTANT
        case:
            gpu.mat_type  = MAT_LAMBERTIAN
            gpu.albedo    = [3]f32{0.7, 0.7, 0.7}
            gpu.tex_type  = TEX_CONSTANT
        }
        result[idx] = gpu
        if world_to_quad_gpu != nil && len(world_to_quad_gpu) == len(objects) {
            world_to_quad_gpu[i] = idx
        }
        idx += 1
    }
    return result
}
