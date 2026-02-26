# `raytrace/` — GPU Path

This package is the core path tracer; it supports both a **CPU** (multi-threaded) and a **GPU** (OpenGL compute shader) path. Both produce the same image.

**For build/run, architecture (path tracing, BVH, materials, camera, CPU pipeline), and file map, see [CLAUDE.md](../CLAUDE.md) at the repo root.**

This README describes only the **GPU path** — pipeline, data layout, and how it differs from the CPU path.

---

## Table of Contents

1. [GPU pipeline overview](#1-gpu-pipeline-overview)
2. [Buffers and bindings](#2-buffers-and-bindings)
3. [PCG RNG and seeding](#3-pcg-rng-and-seeding)
4. [Iterative path tracing and BVH](#4-iterative-path-tracing-and-bvh)
5. [Data layout: CPU ↔ GPU](#5-data-layout-cpu--gpu)
6. [CPU vs GPU](#6-cpu-vs-gpu)
7. [Extending the GPU path](#7-extending-the-gpu-path)
8. [References](#8-references)

---

## 1. GPU pipeline overview

```
ui.run_app (use_gpu=true)
  └─ rt.start_render_auto
       ├─ build_bvh + flatten_bvh      — BVH built once on CPU
       └─ gpu_backend_init             — compile shader, upload buffers
            ├─ UBO  binding=0 : GPUCameraUniforms  (camera parameters)
            ├─ SSBO binding=1 : [count][GPUSphere…] (sphere data)
            ├─ SSBO binding=2 : [count][LinearBVHNode…] (flat BVH)
            └─ SSBO binding=3 : [vec4…] (output accumulation; .rgb used, .a unused)

each frame:
  gpu_backend_dispatch → DispatchCompute(W/8, H/8, 1)
    └─ raytrace.comp (one invocation per pixel)
         └─ path_trace(primary_ray, seed)
              └─ accumulate colour into pixels[idx]

every 4 frames:
  gpu_backend_readback
    ├─ GetBufferSubData → read vec4 per pixel
    ├─ divide by current_sample
    ├─ sqrt gamma correction
    └─ write [][4]u8 → UpdateTexture
```

Progressive accumulation: one sample per dispatch. The output SSBO stores running sums; the CPU divides by the sample count on readback. See [CLAUDE.md](../CLAUDE.md) for the CPU tile-based path.

---

## 2. Buffers and bindings

| Binding | Type | Content |
|--------|------|--------|
| 0 | UBO (std140) | `GPUCameraUniforms` — camera, defocus, width/height, sample count |
| 1 | SSBO (std430) | `[4]i32` header + `[]GPUSphere` |
| 2 | SSBO (std430) | `[4]i32` header + `[]LinearBVHNode` |
| 3 | SSBO (std430) | `[]vec4` — one per pixel; .rgb = accumulated linear colour, .a unused |

**Why vec4 for output?** std430 alignment: a vec3 array would require explicit padding to 16-byte boundaries. Using vec4 keeps the layout simple; alpha is intentionally unused. See `gpu_backend.odin` and `OutputBlock` in `raytrace.comp`.

---

## 3. PCG RNG and seeding

The GPU uses **PCG** (Permuted Congruential Generator) so each invocation has its own local `uint` state — no shared globals.

**Seeding:** Combine pixel index and sample index, then hash once to avoid correlation between consecutive pixels:

```glsl
uint seed = pcg_hash(pixel_index ^ (sample_index * 2654435761u));
```

`pcg_hash(v)` runs one round of PCG mixing on `v`; the shader then warms up the RNG with two discarded values before use. See the comment block above `pcg_hash` in `raytrace.comp`.

---

## 4. Iterative path tracing and BVH

GLSL has no recursion. The CPU’s recursive `ray_color_linear` becomes an explicit loop in `path_trace` (GPU): a `for (depth …)` loop with `throughput *= attenuation` and `r = scattered`.

**BVH traversal** is stack-based: `int stack[64]`. Max depth 64 is sufficient for a balanced BVH with up to ~10^18 leaves; if exceeded, nodes are silently skipped (missing geometry). See `bvh_hit_scene` in `raytrace.comp`.

---

## 5. Data layout: CPU ↔ GPU

The flat `LinearBVHNode` array from `flatten_bvh` is uploaded as-is. `GPUSphere` is built from the Odin `Object` slice by `scene_to_gpu_spheres`. Sizes and layout must match the GLSL definitions exactly (see `gpu_types.odin` and the `#assert(size_of(...))` checks).

| Odin struct | Size | GLSL |
|-------------|------|------|
| `GPUSphere` | 48 B | `Sphere` in `SpheresBlock` |
| `LinearBVHNode` | 32 B | `BVHNode` in `BVHBlock` |
| `GPUCameraUniforms` | 128 B | `CameraBlock` (UBO, std140) |

SSBO headers: first 16 bytes are `[4]i32 { count, 0, 0, 0 }` so the following array is correctly aligned for std430.

---

## 6. CPU vs GPU

| | CPU path | GPU path |
|--|----------|----------|
| **Startup** | Fast | ~100 ms shader compile |
| **Progressive** | No | Yes (one sample per frame) |
| **Low spp** (<10) | Often faster | Overhead dominates |
| **High spp** (>50) | Slower | Much faster |
| **Geometry** | Any `Object` type | Spheres only (for now) |
| **Platform** | Any | Linux + GLX (see CLAUDE.md) |

Use the GPU path for interactive previews with many samples; use the CPU path for quick tests or when debugging materials.

---

## 7. Extending the GPU path

- **New material (e.g. emissive):** Add a `MAT_*` constant in `gpu_types.odin` and a matching `const int` + `case` in `raytrace.comp`; use `GPUSphere._pad` or extend the struct (then keep layout in sync with GLSL).
- **Textures:** Add an SSBO of texels + a metadata SSBO; add `texture_id` (e.g. in `_pad[0]`) and a `sample_texture(…)` in the shader.
- **Triangles:** Reuse the linear BVH sentinel scheme: e.g. `left_idx == -2` for triangle leaves, `right_or_obj_idx = -(triangle_index + 1)`. Add a `TrianglesBlock` SSBO and `intersect_triangle` in the shader.

For full extension notes (emissive, textures, triangle meshes, SAH, importance sampling, volumes), see the previous version of this README in git history or the references below.

---

## 8. References

- **Peter Shirley, *Ray Tracing in One Weekend* series**: https://raytracing.github.io/
- **PCG (O'Neill)**: https://www.pcg-random.org/ — RNG used in `raytrace.comp`
- **OpenGL Compute Shaders**: https://www.khronos.org/opengl/wiki/Compute_Shader
- **SSBOs**: https://www.khronos.org/opengl/wiki/Shader_Storage_Buffer_Object
- **Odin `vendor:OpenGL`**: `$(odin root)/vendor/OpenGL/`
