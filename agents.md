# AGENTS.md

This file guides AI agents working autonomously in this repository.

## Project Summary

A [Ray Tracing in One Weekend](https://raytracing.github.io/)–style path tracer built in the
[Odin programming language](https://odin-lang.org/). The project combines a CPU path tracer
core with:

- **[Raylib](https://www.raylib.com/)** for windowing, UI panels, and log output
- **Scene editing** — interactive 3D viewport to add, move, and delete spheres at runtime
- **GPU acceleration** via an OpenGL 4.3 compute shader (`-gpu` flag)
- **Cross-platform** — Linux (GPU + CPU), Windows (GPU + CPU), macOS (CPU fallback)

## Build & Verify

Always build before testing changes.

**Using the Makefile:**

```bash
make debug    # Debug build → build/debug
make release # Release build → build/release (optimized, quiet stdout)
```

**Manual build:**

```bash
odin build . -collection:RT_Weekend=. -debug -out:build/debug
```

Release builds use: `-o:speed -no-bounds-check -define:PROFILING_ENABLED=false -define:VERBOSE_OUTPUT=false`. Run with `./build/release`.

Verify a small, fast render starts (opens a Raylib window, closes when done):

```bash
./build/debug -w 100 -h 100 -s 5
```

For GPU path verification (requires OpenGL 4.3+):

```bash
./build/debug -gpu -s 20 -w 200 -h 112
```

For performance changes, use a timed render (timing printed to stdout in debug; Stats panel has data in both):

```bash
./build/debug -w 800 -h 450 -s 50
# or
./build/release -w 800 -h 450 -s 50
```

Cross-compile type-checks (no linker — syntax/type errors only):

```bash
odin check . -collection:RT_Weekend=. -target:windows_amd64
odin check . -collection:RT_Weekend=. -target:darwin_amd64
```

## Package Structure

The project is split across five Odin packages (build with `-collection:RT_Weekend=.`):

| Package | Directory | Responsibility |
|---------|-----------|----------------|
| `main` | `.` (root) | CLI parsing, scene setup, launches `ui.run_app` |
| `util` | `util/` | Argument parsing, system info, Xoshiro256++ RNG |
| `raytrace` | `raytrace/` | Path tracer core: camera, BVH, materials, GPU backend |
| `scene` | `scene/` | Shared scene types (`SceneSphere`, `CameraParams`, `MaterialKind`) |
| `ui` | `ui/` | Raylib window, panels, scene editor, GPU dispatch loop |

## Current File Responsibilities

### `raytrace/` package

| File | Responsibility |
|------|----------------|
| `camera.odin` | `Camera`, `RenderSession`, parallel tile rendering, `start_render_auto`, `get_render_progress`, `finish_render` |
| `hittable.odin` | `Sphere`/`Cube`, AABB, `BVHNode` (recursive), `flatten_bvh`, `bvh_hit_linear` (iterative flat BVH) |
| `material.odin` | `lambertian`, `metallic`, `dielectric` unions; `scatter` procedure |
| `vector3.odin` | Vec3 math, `ray`, `ray_color_linear` (iterative, used by CPU workers) |
| `interval.odin` | `Interval` struct for ray `t`-range and AABB overlap |
| `gpu_types.odin` | `GPUBackend`, `LinearBVHNode`, `GPUSphere`, `GPUCameraUniforms`, `scene_to_gpu_spheres` |
| `gpu_backend.odin` | OpenGL compute backend: init/dispatch/readback/destroy; cross-platform GL loaders (Linux GLX, Windows WGL, macOS dlsym); `OPENGL_RENDERER_API` vtable constant |
| `gpu_renderer.odin` | `GpuRendererApi` vtable, `GpuRenderer` struct, helper procs, `create_gpu_renderer` platform factory |
| `raytrace.odin` | `setup_scene` (default scene), `write_buffer_to_ppm` |
| `scene_build.odin` | `build_world_from_scene`, `convert_world_to_edit_spheres` |
| `scene_io.odin` | `load_scene` / `save_scene` (JSON) |
| `profiling.odin` | Zero-cost timing probes (gated by `PROFILING_ENABLED` compile flag) |

### `util/` package

| File | Responsibility |
|------|----------------|
| `util/cli.odin` | `Args`, `parse_args_with_short_flags`, `get_number_of_physical_cores`, `print_system_info` |
| `util/rng.odin` | `ThreadRNG`, `create_thread_rng`, `random_float`, `random_float_range` (Xoshiro256++) |
| `util/config.odin` | `RenderConfig`, `EditorLayout`, `save_config`, `load_config` |
| `util/layout_preset.odin` | `LayoutPreset` type |

## GPU Acceleration

### How it works

`start_render_auto(cam, world, threads, use_gpu)` is the entry point:
- When `use_gpu=true` and GPU init succeeds: builds BVH, uploads scene to SSBOs, returns a session with `use_gpu=true`
- When GPU init fails (wrong driver, macOS 4.1 cap, missing shader): logs the reason and falls back to the standard CPU path transparently

The GPU path dispatches one `DispatchCompute` per frame (one sample per pixel per call). The UI reads back the accumulation buffer every 4 frames and uploads to the Raylib texture.

### GpuRenderer vtable (`gpu_renderer.odin`)

All GPU access goes through the `GpuRenderer` vtable — `ui/` never touches `GPUBackend` directly:

```odin
gpu_renderer_dispatch(r)          // dispatch one sample
gpu_renderer_readback(r, out)     // read back RGBA bytes
gpu_renderer_get_samples(r) -> (cur, tot: int)
gpu_renderer_done(r) -> bool
gpu_renderer_destroy(r)           // destroy + free
```

`create_gpu_renderer` is the platform-aware factory. It has commented stubs for future
Metal (macOS) and DirectX 12 / Vulkan (Windows) backends — adding a new backend requires
implementing the five vtable procs and registering them there.

### Platform behavior

| OS | GPU today | Notes |
|----|-----------|-------|
| Linux | OpenGL 4.3 via GLX | `glXGetProcAddressARB` loader |
| Windows | OpenGL 4.3 via WGL | `wglGetProcAddress` + `opengl32.dll` fallback |
| macOS | CPU fallback | OpenGL capped at 4.1; `gl.DispatchCompute == nil` → graceful fallback |

## Concurrency Rules

These must be respected when modifying rendering code:

- The **BVH and camera** are read-only during rendering. Never write to them from worker threads.
- **Tile dispatch** uses `sync.atomic_add`. Do not replace with a mutex.
- Each worker thread has its **own Xoshiro256++ RNG instance**. Do not share RNG state.
- The **pixel buffer** is partitioned by tile; threads write to non-overlapping regions — no locking needed for writes.
- The **GPU path** spawns no worker threads; `gpu_renderer_dispatch` is called from the Raylib main thread only.

## Extending the Renderer

### Adding a New Material

1. Add a struct in `material.odin` and include it in the `Material` union.
2. Add a `scatter` case in the `scatter` procedure.
3. Add a `MAT_*` constant in `gpu_types.odin` and a GLSL case in `raytrace.comp`.
4. Add a `scene.MaterialKind` value and handle it in `scene_build.odin` and the editor.

### Adding a New GPU Backend (e.g. Metal, Vulkan)

1. Create a new file (e.g. `raytrace/metal_backend.odin`).
2. Define a backend state struct and implement the five vtable procs.
3. Declare `METAL_RENDERER_API :: GpuRendererApi{...}`.
4. Uncomment and fill the stub `when ODIN_OS == .Darwin` block in `create_gpu_renderer`.

### Adding a New Scene Object Type

1. Define the struct and AABB in `hittable.odin`; add it to the `Object` union.
2. Add a hit-test case in the `hit` procedure and AABB case in `get_aabb`.
3. Add a new `LinearBVHNode` leaf sentinel (see `left_idx` sentinel comments).
4. Add a GLSL struct and intersection case in `raytrace.comp` for GPU support.

## Constraints

- **Build collection** `-collection:RT_Weekend=.` is required — without it `import "RT_Weekend:raytrace"` fails.
- **Tile size (32×32)** is tuned for cache locality — do not change without benchmarking.
- **Xoshiro256++** in `util/rng.odin` must not be replaced with a standard-library RNG that requires locking.
- Do not introduce global mutable state. Thread safety is kept explicit by passing context through procedure parameters. The `gpu_backend.odin` file-level `_gl32_module` / `_ogl_handle` vars are the only deliberate exceptions (GL loader handles are process-lifetime singletons).
- **`ui/` never imports `raytrace` GPU internals directly** — all GPU access goes through `rt.GpuRenderer` helper procs.
