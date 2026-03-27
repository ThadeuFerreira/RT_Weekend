# AGENTS.md

This file guides AI agents working autonomously in this repository.

## Project Summary

A [Ray Tracing in One Weekend](https://raytracing.github.io/)–style path tracer built in the
[Odin programming language](https://odin-lang.org/). The project combines a CPU path tracer
core with:

- **[Raylib](https://www.raylib.com/)** for windowing, UI panels, and log output
- **Scene editing** — interactive 3D viewport to add, move, and delete spheres at runtime
- **Idle GPU throttling** — viewport/preview dirty-flag redraw + idle event-wait pacing (no unnecessary 60 FPS present loop)
- **GPU acceleration** via a Vulkan compute shader (`-gpu` flag)
- **Cross-platform** — Linux (Vulkan GPU + CPU), macOS/Windows (CPU fallback)

## Build & Verify

Always build before testing changes.

**Using the Makefile:**

```bash
make debug    # Debug build → build/debug (-define:VERBOSE_DEBUG=1)
make release # Release build → build/release (optimized, quiet stdout)
```

**Manual build:**

```bash
odin build . -collection:RT_Weekend=. -debug -define:VERBOSE_DEBUG=1 -out:build/debug
```

Release builds use: `-o:speed -no-bounds-check -define:PROFILING_ENABLED=false -define:VERBOSE_OUTPUT=false -define:TRACE_CAPTURE_ENABLED=false`. Run with `./build/release`.

`VERBOSE_DEBUG` is a convenience build flag (`-define:VERBOSE_DEBUG=1`) that enables diagnostic defaults in one switch:
- `TRACK_ALLOCATIONS` default on
- `UI_EVENT_LOG_ENABLED` default on
- `EDITOR_IDLE_GPU_TRACE` default on

Idle GPU tracing can still be overridden at runtime with `EDITOR_IDLE_GPU_TRACE=0|1`.

Verify a small, fast render starts (opens a Raylib window, closes when done):

```bash
./build/debug -w 100 -h 100 -s 5
```

For GPU path verification (requires Vulkan):

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
| `raytrace` | `raytrace/` | Path tracer core: camera, BVH, materials, Vulkan GPU backend |
| `scene` | `scene/` | Shared scene types (`SceneSphere`, `CameraParams`, `MaterialKind`) |
| `ui` | `ui/` | Raylib window, panels, scene editor, GPU dispatch loop |

## Current File Responsibilities

### `raytrace/` package

| File | Responsibility |
|------|----------------|
| `camera.odin` | `Camera`, `RenderSession`, parallel tile rendering, `start_render_auto`, `get_render_progress`, `finish_render` |
| `hittable.odin` | `Sphere`/`Quad`, AABB, `BVHNode` (recursive), `flatten_bvh`, `bvh_hit_linear` (iterative flat BVH) |
| `material.odin` | `lambertian`, `metallic`, `dielectric` unions; `scatter` procedure |
| `vector3.odin` | Vec3 math, `ray`, `ray_color_linear` (iterative, used by CPU workers) |
| `interval.odin` | `Interval` struct for ray `t`-range and AABB overlap |
| `gpu_types.odin` | `LinearBVHNode`, `GPUSphere`, `GPUCameraUniforms`, `scene_to_gpu_spheres`, `_camera_to_gpu_uniforms` |
| `gpu_backend_vulkan.odin` | Vulkan compute backend: `VulkanGPUBackend`, init/dispatch/readback/destroy; `VULKAN_RENDERER_API` vtable constant |
| `gpu_backend_adapter.odin` | Wraps `GpuRendererApi` as a `RenderBackendApi` for the unified backend interface |
| `gpu_renderer.odin` | `GpuRendererApi` vtable, `GpuRenderer` struct, helper procs, `create_gpu_renderer` factory |
| `render_backend.odin` | `RenderBackendApi` vtable, `RenderBackend`, backend helpers |
| `cpu_backend.odin` | CPU tile renderer as a `RenderBackend` |
| `raytrace.odin` | `setup_scene` (default scene), `write_buffer_to_ppm` |
| `scene_build.odin` | `build_world_from_scene`, `convert_world_to_edit_spheres` |
| `scene_io.odin` | `load_scene` / `save_scene` (JSON); preserves non-black camera background, and for black/missing background with no emissive materials it falls back to white before render |
| `profiling.odin` | Zero-cost timing probes (gated by `PROFILING_ENABLED` compile flag) |

### `util/` package

| File | Responsibility |
|------|----------------|
| `util/cli.odin` | `Args`, `parse_args_with_short_flags`, `get_number_of_physical_cores`, `print_system_info` |
| `util/rng.odin` | `ThreadRNG`, `create_thread_rng`, `random_float`, `random_float_range` (Xoshiro256++) |
| `util/config.odin` | `RenderConfig`, `EditorLayout`, `save_config`, `load_config` |
| `util/layout_preset.odin` | `LayoutPreset` type |
| `util/trace.odin` | Chrome/Perfetto timeline tracing capture (Chrome JSON traceEvents). Gated by `TRACE_CAPTURE_ENABLED`. |

## Instrumentation pattern (idiomatic Odin)

Odin does not use preprocessor macros for RAII timers. The idiomatic pattern is:

- **Compile-time gating** via `#config` and `when` inside helper procs (or at call sites).
- **Scope object + `defer`** to ensure the end marker runs on scope exit.

For profiling counters (Stats panel) use `raytrace/profiling.odin`:

```odin
scope := PROFILE_SCOPE(&some_ns_counter)
defer PROFILE_SCOPE_END(scope)
```

For Chrome/Perfetto timeline export use `util/trace.odin`:

```odin
s := util.trace_scope_begin("Frame", "game")
defer util.trace_scope_end(s)
```

## GPU Acceleration

### How it works

`start_render_auto(cam, world, threads, use_gpu)` is the entry point:
- When `use_gpu=true` and Vulkan init succeeds: builds BVH, uploads scene to SSBOs, returns a session with `use_gpu=true`
- When Vulkan init fails (no driver, unsupported platform): logs the reason and falls back to the standard CPU path transparently

The GPU path dispatches one `vkCmdDispatch` per frame (one sample per pixel per call). The UI reads back the accumulation buffer every 4 frames and uploads to the Raylib texture.

### GpuRenderer vtable (`gpu_renderer.odin`)

All GPU access goes through the `GpuRenderer` vtable — `ui/` never touches `VulkanGPUBackend` directly:

```odin
gpu_renderer_dispatch(r)          // dispatch one sample
gpu_renderer_readback(r, out)     // read back RGBA bytes
gpu_renderer_get_samples(r) -> (cur, tot: int)
gpu_renderer_done(r) -> bool
gpu_renderer_destroy(r)           // destroy + free
```

`create_gpu_renderer` tries the Vulkan compute backend. Returns nil if unavailable.

### Platform behavior

| OS | GPU Backend | Notes |
|----|-------------|-------|
| Linux | Vulkan compute | Via `vendor:vulkan` + `vk_ctx` package |
| Windows | CPU fallback | Vulkan support planned |
| macOS | CPU fallback | Vulkan support planned |

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
3. Add a `MAT_*` constant in `gpu_types.odin` and a GLSL case in `raytrace_vk.comp`.
4. Add a `scene.MaterialKind` value and handle it in `scene_build.odin` and the editor.

### Adding a New Scene Object Type

1. Define the struct and AABB in `hittable.odin`; add it to the `Object` union.
2. Add a hit-test case in the `hit` procedure and AABB case in `get_aabb`.
3. Add a new `LinearBVHNode` leaf sentinel (see `left_idx` sentinel comments).
4. Add a GLSL struct and intersection case in `raytrace_vk.comp` for GPU support.

## Constraints

- **Build collection** `-collection:RT_Weekend=.` is required — without it `import "RT_Weekend:raytrace"` fails.
- **Tile size (32×32)** is tuned for cache locality — do not change without benchmarking.
- **Xoshiro256++** in `util/rng.odin` must not be replaced with a standard-library RNG that requires locking.
- Do not introduce global mutable state. Thread safety is kept explicit by passing context through procedure parameters.
- **`ui/` never imports `raytrace` GPU internals directly** — all GPU access goes through `rt.GpuRenderer` helper procs.
