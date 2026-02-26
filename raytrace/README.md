# `raytrace/` — Path Tracer: CPU & GPU Paths Explained

This package is the core of the renderer.  It implements a **Monte Carlo path tracer**
from scratch, running on the CPU (multi-threaded) or the GPU (OpenGL compute shader).
Both paths produce the same image; the GPU path is faster for high sample counts.

This document explains *how* each path works, *why* the algorithms are the way they are,
and *how to extend* the renderer with new techniques.

---

## Table of Contents

1. [What is Path Tracing?](#1-what-is-path-tracing)
2. [Core Concepts (shared by both paths)](#2-core-concepts)
3. [CPU Path](#3-cpu-path)
4. [GPU Path](#4-gpu-path)
5. [CPU vs GPU — When to Use Which](#5-cpu-vs-gpu)
6. [File Map](#6-file-map)
7. [How to Extend the Renderer](#7-extending-the-renderer)
8. [References & Further Reading](#8-references)

---

## 1. What is Path Tracing?

**Ray tracing** answers the question: "given a pixel on screen, what colour should it be?"
It does this by firing a ray from the camera through that pixel into the scene and finding
what the ray hits.

**Path tracing** extends ray tracing to simulate *global illumination* — indirect light
that bounces between surfaces.  When a ray hits a surface, it is randomly scattered in a
new direction according to the surface's material.  The process repeats until the ray
escapes the scene (hits the sky) or exceeds the maximum bounce depth.  The final colour
is the product of all the attenuation values collected along the path, multiplied by the
sky colour at the end.

```
Camera → pixel → ray → hit surface → scatter → hit another surface → scatter → … → sky
         ↑                                                                        ↑
    primary ray                                                          accumulated light
```

Because scattering is random, a single ray gives a noisy result.  The noise averages out
when you fire many rays (samples) through the same pixel — this is **Monte Carlo
integration**.  More samples → less noise, but proportionally more compute time.

### Why is it slow?

Each sample requires:
- An intersection test against every object in the scene (mitigated by the BVH)
- A random scatter decision per bounce (up to `max_depth` bounces)
- Recursive (CPU) or iterative (GPU) evaluation

A 800×450 image at 100 samples per pixel fires **36 million** primary rays, each spawning
up to 20 scattered rays.  That is up to **720 million** intersection tests.

---

## 2. Core Concepts

These ideas appear in both the CPU and GPU implementations.

### 2.1 The Ray

```odin
// vector3.odin
ray :: struct {
    orig : [3]f32,   // origin point
    dir  : [3]f32,   // direction (not necessarily unit length)
}
ray_at :: proc(r: ray, t: f32) -> [3]f32 { return r.orig + t * r.dir }
```

A ray is a half-line: `P(t) = origin + t * direction` for `t > 0`.  Intersection tests
find the smallest positive `t` where the ray meets a surface.

### 2.2 Sphere Intersection

The intersection of a ray with a sphere of radius `r` centred at `C` is a quadratic
equation in `t`.  Given the ray `P(t) = O + t*D`:

```
|P(t) - C|² = r²
(D·D)t² - 2(D·(C-O))t + ((C-O)·(C-O) - r²) = 0
```

The discriminant `h² - ac` tells us how many intersection points exist (0, 1, or 2).
We take the smaller positive root (the nearest hit from the camera side).
See `hit_sphere` in `vector3.odin` for the implementation.

### 2.3 Materials

Three materials are implemented, all sharing the same `scatter` interface: given an
incoming ray and a hit record, produce an outgoing (scattered) ray and an attenuation
colour.

| Material | Odin type | Behaviour |
|---|---|---|
| **Lambertian** | `lambertian` | Diffuse: scatter in a random hemisphere direction near the normal.  Models matte surfaces (wood, plaster, rough stone). |
| **Metallic** | `metallic` | Specular: reflect the ray around the surface normal, perturbed by a fuzz factor.  `fuzz=0` → perfect mirror. |
| **Dielectric** | `dielectric` | Refract or reflect based on Snell's law and the Schlick approximation.  Models glass, water, diamond. |

The Schlick approximation for Fresnel reflectance:

```
R(θ) = R₀ + (1 - R₀)(1 - cos θ)⁵       R₀ = ((n₁-n₂)/(n₁+n₂))²
```

When `R(θ) > random()` the ray reflects; otherwise it refracts.  This correctly models
the observation that glass becomes more mirror-like at grazing angles.

### 2.4 Camera & Depth of Field

The camera model (`camera.odin`) is a thin-lens approximation.  Instead of firing all
rays from a single point, rays originate from a random point on a *defocus disk* — a
disk orthogonal to the view direction, centred at `lookfrom`.  Objects at the focal
distance appear sharp; objects at other depths are blurred.

```
defocus_radius = focus_dist × tan(defocus_angle / 2)
ray_origin = random_point_on_disk(radius = defocus_radius)
```

### 2.5 Gamma Correction

OpenGL and most monitors expect colours in **sRGB** gamma space.  The renderer works in
**linear** light space and converts at output time with a square-root approximation of
the standard gamma-2.2 curve:

```odin
linear_to_gamma :: proc(c: f32) -> f32 { return math.sqrt(max(c, 0)) }
```

The GPU readback (`gpu_backend_readback`) applies the same correction before writing
bytes to the texture.

### 2.6 Bounding Volume Hierarchy (BVH)

Testing every ray against every object is O(N) per ray.  A BVH reduces this to O(log N)
by wrapping groups of objects in Axis-Aligned Bounding Boxes (AABBs) arranged in a tree.
If a ray misses a node's AABB, the entire subtree is skipped.

**Slab method** (AABB hit test): for each axis, compute the intervals `[t_lo, t_hi]`
where the ray is inside the slab between `min` and `max`.  The ray hits the AABB if and
only if the intersection of all three intervals is non-empty.

```
for each axis { t0 = (min - origin) / dir;  t1 = (max - origin) / dir }
t_enter = max(t0_x, t0_y, t0_z)
t_exit  = min(t1_x, t1_y, t1_z)
hit = t_exit > t_enter
```

---

## 3. CPU Path

### 3.1 Overview

```
main.odin
  └─ ui.run_app
       └─ rt.start_render_auto          (camera.odin)
            ├─ build_bvh                (hittable.odin) — recursive pointer tree
            ├─ flatten_bvh              (hittable.odin) — flat array for CPU workers
            └─ spawn N worker threads   (camera.odin)
                 └─ each pulls tiles from a shared atomic work queue
                      └─ for each pixel in tile:
                           for each sample:
                             r = get_ray(camera, x, y)
                             colour += ray_color_linear(r, max_depth, …)
                           set_pixel(buffer, x, y, colour / samples)
```

### 3.2 Parallel Tile Rendering

The image is divided into **32×32 pixel tiles**.  A shared atomic counter
(`TileWorkQueue.next_tile`) acts as the work queue.  Each thread does:

```odin
for {
    tile_index := sync.atomic_add(&work_queue.next_tile, 1)  // claim next tile
    if tile_index >= total_tiles { break }
    render_tile(ctx, tiles[tile_index])
}
```

Because threads write to non-overlapping regions of the pixel buffer, no locking is
needed for writes.  Only the tile counter uses atomic operations.

Each thread has its own **Xoshiro256++ RNG** seeded with a unique value, so there are no
data races on random number generation and the render is deterministic per seed.

### 3.3 Recursive BVH (`bvh_hit`) vs Iterative BVH (`bvh_hit_linear`)

Two BVH traversal implementations exist side by side — intentionally, for comparison:

**`bvh_hit` (recursive)** — `hittable.odin`
- Clean, easy to read; mirrors the tree structure directly
- Stack space grows with BVH depth (compiler call stack)
- Pointer chasing: each node access may miss the CPU cache

**`bvh_hit_linear` (iterative)** — `hittable.odin`
- Uses an explicit `int` stack of max depth 64
- All nodes are contiguous in memory (`[]LinearBVHNode`) → cache-friendly
- The same flat array is uploaded to the GPU unchanged (no format conversion)
- Workers use this path when `linear_nodes != nil`

```
Recursive tree           Flat array (same tree)
    [0]                  index: 0  1  2  3  4  5  6
   /   \                 nodes: [root][L][LL][LR][R][RL][RR]
  [1]  [4]              left:   1   2  -1  -1  5  -1  -1
 /  \  / \              right:  4   3  -2  -3  6  -4  -5
[2][3][5][6]            (negative right = leaf: -(obj_idx+1))
```

`flatten_bvh` converts the tree to the array via depth-first traversal.  The root is
always at index 0.

### 3.4 `ray_color_linear` — Path Tracing (Recursive, CPU)

```odin
// vector3.odin
ray_color_linear :: proc(r, depth, world, rng, …) -> [3]f32 {
    if depth <= 0 { return {0,0,0} }            // recursion limit

    if bvh_hit_linear(nodes, objects, r, …) {   // find nearest hit
        if scatter(material, r_in, hit, …) {    // scatter at surface
            return attenuation * ray_color_linear(scattered, depth-1, …)
        }
        return {0,0,0}                          // absorbed
    }
    return sky_gradient(r)                      // no hit → sky
}
```

The recursion depth is bounded by `camera.max_depth` (default 20).  Each recursive call
multiplies the attenuation, so paths that bounce many times naturally contribute less to
the final colour.

---

## 4. GPU Path

### 4.1 Overview

```
ui.run_app (use_gpu=true)
  └─ rt.start_render_auto
       ├─ build_bvh + flatten_bvh      — BVH built once on CPU
       └─ gpu_backend_init              — compile shader, upload buffers
            ├─ UBO  binding=0 : GPUCameraUniforms  (camera parameters)
            ├─ SSBO binding=1 : [count][GPUSphere…] (sphere data)
            ├─ SSBO binding=2 : [count][LinearBVHNode…] (flat BVH)
            └─ SSBO binding=3 : [vec4…] (output accumulation, zeroed)

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

### 4.2 Progressive Accumulation

The GPU shader does **one sample per dispatch**.  The output SSBO accumulates RGB values
across dispatches:

```glsl
// raytrace.comp (simplified)
pixels[pixel_idx] += vec4(path_trace(primary_ray, seed), 0.0);
```

The CPU reads back the buffer every 4 frames and divides by the number of completed
samples to get the running average.  This is identical in spirit to the CPU path where
each pixel accumulates `samples_per_pixel` values and divides at the end — the GPU just
does one sample at a time across the whole image, frame by frame.

### 4.3 PCG Random Number Generator

The CPU uses Xoshiro256++.  The GPU uses **PCG (Permuted Congruential Generator)**
because:

- PCG has no global state — each invocation carries its own `uint` state locally
- The seed is derived from `(pixel_y * width + pixel_x) + sample * width * height`,
  giving every `(pixel, sample)` pair a unique pseudo-random stream
- It passes statistical tests comparable to Xoshiro but is simpler in GLSL

```glsl
// raytrace.comp
uint pcg(inout uint state) {
    state = state * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
float rand(inout uint seed) { return float(pcg(seed)) / float(0xFFFFFFFFu); }
```

### 4.4 Iterative Path Tracing (GPU)

GLSL does not support recursion.  `ray_color_linear` (recursive) becomes an explicit
loop in `path_trace` (GPU):

```glsl
// raytrace.comp
vec3 path_trace(Ray r, inout uint seed) {
    vec3 throughput = vec3(1.0);   // product of attenuations so far
    vec3 colour     = vec3(0.0);   // additive sky contributions

    for (int depth = 0; depth < max_depth; depth++) {
        HitRecord rec;
        if (bvh_hit_scene(r, 0.001, 1e30, rec)) {
            vec3 attenuation; Ray scattered;
            if (!scatter_*(rec, r, seed, attenuation, scattered)) break;
            throughput *= attenuation;
            r = scattered;
        } else {
            colour += throughput * sky_color(r);
            return colour;
        }
    }
    return colour;
}
```

`throughput` replaces the recursive multiplication of `attenuation * ray_color(…)`.
This is the standard iterative reformulation of recursive path tracing.

### 4.5 Data Layout: CPU ↔ GPU

The flat `LinearBVHNode` array built by `flatten_bvh` is uploaded to the GPU as-is.
The `GPUSphere` array is converted from the Odin-union `Object` slice by
`scene_to_gpu_spheres`.  Both use `std430` layout in the SSBO.

SSBO format (both spheres and BVH):
```
bytes 0–15  : [4]i32 { count, 0, 0, 0 }  ← element count + 12-byte pad
bytes 16–…  : array of structs
```

The 16-byte header is required because GLSL `std430` places the first array element at a
16-byte boundary when the struct contains a `vec3`.

GPU struct sizes (must match GLSL definitions exactly):

| Odin struct | Size | GLSL binding |
|---|---|---|
| `GPUSphere` | 48 B | `Sphere` in `SpheresBlock` |
| `LinearBVHNode` | 32 B | `BVHNode` in `BVHBlock` |
| `GPUCameraUniforms` | 128 B | `CameraBlock` (UBO, std140) |

---

## 5. CPU vs GPU

| | CPU path | GPU path (`-gpu`) |
|---|---|---|
| **Startup** | Fast (no shader compile) | ~100 ms shader compile |
| **First pixel** | After all tiles | After first dispatch |
| **Progressive** | No (full render then show) | Yes (one sample per frame) |
| **Low sample count** (<10 spp) | Faster | Overhead dominates |
| **High sample count** (>50 spp) | Slower | Much faster |
| **Complex geometry** | Any `Object` union type | Spheres only (Cube not yet uploaded) |
| **Debuggability** | Printf, breakpoints | Driver-side only |
| **Portability** | Any platform | Requires OpenGL 4.3+ |

**Rule of thumb:** use the GPU path for iterative preview renders (many samples,
interactive feedback) and the CPU path for quick test renders or when debugging material
behaviour.

---

## 6. File Map

```
raytrace/
├── camera.odin         Camera definition, tile generation, start_render,
│                       start_render_auto (CPU/GPU dispatch), get_render_progress,
│                       finish_render, worker thread loop
├── hittable.odin       Sphere/Cube primitives, AABB, hit_record,
│                       BVHNode (recursive tree), bvh_hit (recursive traversal),
│                       flatten_bvh, bvh_hit_linear (flat iterative traversal)
├── material.odin       lambertian, metallic, dielectric unions; scatter procedure
├── vector3.odin        Vec3 math, ray, hit_sphere, ray_color (recursive),
│                       ray_color_linear (iterative, prefers flat BVH)
├── interval.odin       Interval struct used for ray t-range and AABB tests
├── gpu_types.odin      LinearBVHNode, GPUSphere, GPUCameraUniforms, GPUBackend,
│                       MAT_* constants, scene_to_gpu_spheres
├── gpu_backend.odin    gpu_backend_init/dispatch/readback/destroy;
│                       glXGetProcAddressARB GL loader (Linux)
├── raytrace.odin       setup_scene (default scene), write_buffer_to_ppm
├── scene_build.odin    build_world_from_scene (converts scene spheres to Objects)
├── scene_io.odin       load_scene / save_scene (JSON)
└── profiling.odin      Zero-cost timing probes (gated by PROFILING_ENABLED)

assets/shaders/
└── raytrace.comp       GLSL 430 compute shader: PCG RNG, iterative BVH,
                        iterative path tracer, all three material types
```

---

## 7. Extending the Renderer

This section shows concretely how to add common path-tracing features.  The design is
intentionally modular so each addition touches a small, well-defined set of files.

### 7.1 New Material: Emissive (Light Sources)

Currently the sky provides all light.  An **emissive** material lets geometry itself
emit light (area lights, neon tubes, the sun as a sphere).

**CPU side — `material.odin`:**
```odin
emissive :: struct {
    emit: [3]f32,   // emitted radiance (can be > 1 for HDR lights)
}
// In scatter():
case emissive:
    attenuation^ = {0, 0, 0}
    // signal "no scatter" — caller adds m.emit to accumulated colour
    return false
```

Because `scatter` returns false, `ray_color_linear` returns `{0,0,0}`.  You need to
modify `ray_color_linear` to add `m.emit` to the accumulated colour before returning:

```odin
if scatter_result {
    return attenuation * ray_color_linear(scattered, depth-1, …)
}
return emission_from_hit_record(hr)   // new: emissive materials contribute here
```

**GPU side — `gpu_types.odin` and `raytrace.comp`:**
```odin
MAT_EMISSIVE :: i32(3)
// Reuse _pad[0] in GPUSphere for emission strength — no size change.
```

```glsl
// raytrace.comp
const int MAT_EMISSIVE = 3;
case MAT_EMISSIVE:
    colour += throughput * sphere.albedo * sphere.fuzz_or_ior; // fuzz_or_ior = strength
    return colour;  // path ends; no scatter
```

**Reference:** *Ray Tracing: The Next Week*, chapter 7 — Lights.

---

### 7.2 Textures

A **texture** maps a 2D (u, v) coordinate to a colour, allowing photo-realistic surface
detail without extra geometry.

**Step 1 — UV coordinates**

Sphere UV mapping (standard equirectangular projection):
```
u = atan2(-hit_point.z, hit_point.x) / (2π) + 0.5
v = acos(-hit_point.y / radius) / π
```

Add `u, v: f32` to `hit_record` (CPU) and `HitRecord` (GLSL) and fill them in
`hit_sphere`.

**Step 2 — Texture data**

Add a texture SSBO (binding=4) containing a flat array of `vec4` texels and a metadata
array (width, height, offset into the texel array per texture ID):

```glsl
layout(std430, binding = 4) readonly buffer TexturesBlock {
    int    texel_count;
    int    _pad[3];
    vec4   texels[];   // all textures packed end-to-end
};
layout(std430, binding = 5) readonly buffer TextureMetaBlock {
    int    texture_count;
    int    _pad[3];
    ivec4  meta[];   // .x = offset, .y = width, .z = height, .w = unused
};
```

**Step 3 — Sampling**

```glsl
vec3 sample_texture(int tex_id, float u, float v) {
    ivec4 m  = meta[tex_id];
    int   ix = int(u * float(m.y)) % m.y;
    int   iy = int(v * float(m.z)) % m.z;
    return texels[m.x + iy * m.y + ix].rgb;
}
```

**Step 4 — Wire it in**

Add `texture_id: i32` to `GPUSphere` (currently in `_pad[0]`, cast as needed).  In the
material scatter functions, replace `sphere.albedo` with `sample_texture(sphere.texture_id, rec.u, rec.v)`.

**CPU reference:** *Ray Tracing: The Next Week*, chapter 4 — Solid Textures and chapter 6 — Image Textures.

---

### 7.3 Triangle Meshes

Spheres are fast to intersect but cannot represent arbitrary shapes.  Triangle meshes
(`.obj`, `.gltf`) are the industry standard for complex geometry.

**Möller–Trumbore intersection** (fast ray–triangle test):

```
Given triangle vertices V0, V1, V2 and ray (O, D):
e1 = V1 - V0,   e2 = V2 - V0
h  = D × e2
det = e1 · h
if |det| < ε: miss (ray parallel to triangle)
u = (O - V0) · h / det         — barycentric u ∈ [0,1]
q = (O - V0) × e1
v = D · q / det                 — barycentric v ∈ [0,1], u+v ≤ 1
t = e2 · q / det               — ray parameter
```

**CPU — `hittable.odin`:**
```odin
Triangle :: struct {
    v0, v1, v2: [3]f32,
    n0, n1, n2: [3]f32,   // per-vertex normals for smooth shading
    material:   material,
}
Object :: union { Sphere, Cube, Triangle }   // extend the union
```

**Flat BVH leaf extension:**

The linear BVH already uses a sentinel to distinguish leaf types.  Add a second sentinel:

```odin
// In LinearBVHNode:
// left_idx = -1  → sphere leaf  (existing)
// left_idx = -2  → triangle leaf (new)
// right_or_obj_idx = -(triangle_index + 1)
```

In `bvh_hit_linear`, add an `else if node.left_idx == -2` branch that calls
`hit_triangle`.

**GPU — `raytrace.comp`:**

Add a `TrianglesBlock` SSBO (binding=5) and `intersect_triangle` alongside
`hit_sphere`.  The BVH traversal loop in `bvh_hit_scene` already handles arbitrary leaf
types — just add another `if` on the sentinel value.

**Reference:** Möller & Trumbore, *Fast, Minimum Storage Ray/Triangle Intersection*, 1997.
Also: *Physically Based Rendering* (PBRT), chapter 3 — Shapes.

---

### 7.4 Better BVH: Surface Area Heuristic (SAH)

The current BVH splits along the longest axis at the median.  **SAH** minimises the
expected cost of a ray–tree intersection by choosing the split plane that minimises:

```
cost(L, R) = C_aabb + (SA(L)/SA(parent)) * N(L) * C_hit
                     + (SA(R)/SA(parent)) * N(R) * C_hit
```

where `SA(X)` is the surface area of box `X` and `N(X)` the number of primitives.  SAH
typically produces BVHs 2–3× faster to traverse than median-split.

Replace the insertion-sort + median split in `build_bvh` (`hittable.odin`) with a sweep
over candidate split planes along each axis.  No other files need changes.

**Reference:** *Physically Based Rendering*, chapter 4.3 — The Surface Area Heuristic.

---

### 7.5 Importance Sampling

Randomly scattering in the hemisphere is **uniform sampling**.  Surfaces are lit mostly
from light sources, so most random rays contribute very little.  **Importance sampling**
biases random rays toward light sources (or the BRDF lobe), reducing variance for the
same sample count.

**Simple next-event estimation (shadow rays):**

At each hit, explicitly sample a point on each light source and test visibility.  Add
this contribution directly instead of waiting for the path to accidentally hit the light.

```odin
// For each area light, cast a shadow ray to a random point on the light.
// If not occluded, add light.emit * BRDF(wo, wi) * cos_theta / pdf(wi)
```

**Reference:** *Ray Tracing: The Rest of Your Life* (Peter Shirley) — the entire book
covers importance sampling for path tracing.

---

### 7.6 Volumetric Effects (Fog, Smoke, Clouds)

A **participating medium** scatters light inside its volume, not just on its surface.
The simplest model is a homogeneous medium with constant density:

- At each ray step, sample whether the ray is scattered before reaching the next surface
  using `t_scatter = -log(random()) / density`
- If `t_scatter < t_hit`, scatter in a random direction (isotropic phase function) or
  forward-biased (Henyey–Greenstein phase function)
- Otherwise, proceed to the surface hit as normal

Implement this as a new `ConstantMedium` object wrapping any existing hittable (e.g., a
sphere filled with fog).

**Reference:** *Ray Tracing: The Next Week*, chapter 9 — Volumes.

---

### 7.7 BVH on the GPU (TLAS/BLAS)

For truly complex scenes (millions of triangles), building the BVH on the CPU and
uploading it to a SSBO becomes the bottleneck.  Modern GPU APIs (Vulkan Ray Tracing,
DXR) provide hardware-accelerated BVH build and traversal.  OpenGL does not, but the
`flat LinearBVHNode` array format used here is the same layout expected by Vulkan's
`VkAccelerationStructure` — switching to Vulkan requires changing the dispatch mechanism
but not the data structures.

---

## 8. References

### Books (free online)

- **Peter Shirley, *Ray Tracing in One Weekend* series** (the primary inspiration for
  this renderer): https://raytracing.github.io/
  - *In One Weekend* — sphere intersection, materials, camera, antialiasing, DOF
  - *The Next Week* — BVH, textures, lights, volumes, motion blur
  - *The Rest of Your Life* — importance sampling, PDFs, MIS

- **Matt Pharr, Wenzel Jakob, Greg Humphreys, *Physically Based Rendering: From Theory
  to Implementation* (PBRT)**: https://pbr-book.org/
  The definitive reference for production path tracers.  Every technique mentioned
  above is covered in rigorous mathematical detail.

### Papers

- Möller & Trumbore, *Fast, Minimum Storage Ray/Triangle Intersection* (1997) —
  triangle intersection algorithm used in `intersect_triangle`

- MacDonald & Booth, *Heuristics for ray tracing using space subdivision* (1990) —
  original SAH paper

- O'Neill, *PCG: A Family of Simple Fast Space-Efficient Statistically Good Algorithms
  for Random Number Generation* (2014) — PCG RNG used in the compute shader:
  https://www.pcg-random.org/

- Henyey & Greenstein, *Diffuse radiation in the galaxy* (1941) — the phase function
  used for anisotropic volume scattering

### GPU & OpenGL

- OpenGL Wiki — Compute Shaders: https://www.khronos.org/opengl/wiki/Compute_Shader
- OpenGL Wiki — Shader Storage Buffer Objects:
  https://www.khronos.org/opengl/wiki/Shader_Storage_Buffer_Object
- Odin `vendor:OpenGL` source: `$(odin root)/vendor/OpenGL/`
