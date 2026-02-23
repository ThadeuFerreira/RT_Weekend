# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This project is written in the [Odin programming language](https://odin-lang.org/).

```bash
# Build debug binary (use collection so main can import util, raytrace, ui)
odin build . -collection:RT_Weekend=. -debug -out:build/debug

# Run with defaults (800px wide, 10 samples, 10 spheres)
./build/debug

# Custom resolution / samples / threads
./build/debug -w 400 -h 225 -s 20 -c 8

# Full options
./build/debug -w <int> -h <int> -s <samples> -n <spheres> -c <threads>
```

**Key flags:**
- `-w` / `-h`: image width / height in pixels
- `-s`: samples per pixel (default 10)
- `-n`: number of small random spheres (default 10)
- `-c`: thread count (defaults to physical CPU cores)

The program opens a **Raylib window** with three floating panels:
- **Render Preview** — live RT image updating as tiles complete
- **Stats** — tile progress, thread count, elapsed time
- **Log** — startup and completion messages

Drag panels by their title bar; resize from the bottom-right grip.

## Dependencies

### Raylib (via Odin vendor collection)
Raylib is bundled with the Odin compiler distribution under `$(odin root)/vendor/raylib/`.
The Linux shared library (`libraylib.so`) is included in `vendor/raylib/linux/` — no separate system install is required as long as your Odin installation is complete.

If you encounter linker errors on Linux, verify that:
```bash
ls $(odin root)/vendor/raylib/linux/libraylib.so
```
exists. If not, install Odin from [odin-lang.org](https://odin-lang.org/) with the full vendor collection.

## Project layout (packages)

- **`main.odin`** (package `main`) — entry point; imports `RT_Weekend:util`, `RT_Weekend:raytrace`, `RT_Weekend:ui`.
- **`util/`** (package `util`) — CLI args (`Args`, `parse_args_with_short_flags`), system info (`get_number_of_physical_cores`, `print_system_info`), and per-thread RNG (`ThreadRNG`, `create_thread_rng`, `random_float`, `random_float_range`).
- **`raytrace/`** (package `raytrace`) — scene setup, camera, BVH, materials, vector/ray math, pixel buffer, profiling. Exports `setup_scene`, `start_render`, `get_render_progress`, `finish_render`, `Camera`, `Object`, `RenderSession`, `linear_to_gamma`, `Interval`, `interval_clamp`, etc.
- **`ui/`** (package `ui`) — Raylib window and panels; imports `RT_Weekend:raytrace`. Exports `run_app`.

## Architecture Overview

The renderer is a standard path tracer built around these layers:

### Entry & Scene Setup (`main.odin` + `raytrace/`)
`main.odin` parses CLI arguments (util), calls `raytrace.setup_scene()` to build the camera and world, then calls `ui.run_app()`.

`setup_scene()` returns `(^Camera, [dynamic]Object)` — it only builds geometry, it does **not** start rendering.

### Raylib UI (`ui/`)
`run_app()` (in `ui/app.odin`) owns the main thread and the Raylib event loop:
1. Creates the window and a GPU texture sized to the render output
2. Calls `start_render()` to kick off background worker threads (non-blocking)
3. Each frame: uploads partial pixel buffer to GPU, polls progress, calls `finish_render()` when all tiles are done
4. Draws three floating panels via `ui/ui.odin` helpers

`ui/ui.odin` contains stateless drawing and interaction procedures:
- `update_panel` — drag by title bar, resize by bottom-right grip
- `draw_panel_chrome` — rounded rect + title bar + resize grip
- `draw_stats_content` / `draw_log_content` — panel content renderers
- `upload_render_texture` — converts float buffer → RGBA u8 → `rl.UpdateTexture`

### Non-blocking Render API (`raytrace/camera.odin`)
Three procedures replace the old blocking `render_parallel`:
- `start_render(camera, world, num_threads) -> ^RenderSession` — allocates buffer, builds BVH, spawns threads, returns immediately
- `get_render_progress(session) -> f32` — returns 0.0–1.0; safe to call from any thread
- `finish_render(session)` — joins threads, frees BVH + contexts, prints timing breakdown to stdout

All per-thread state lives in `RenderSession` (no package-level globals).

### Parallel Rendering (`raytrace/camera.odin`)
The rendering loop (unchanged from previous design):
1. Allocates a flat `TestPixelBuffer` (width × height × 3 floats, row-major)
2. Builds the **BVH** once from the scene geometry
3. Divides the image into **32×32 pixel tiles**
4. Spawns N worker threads; each atomically pulls tiles from a shared work queue (`sync.atomic_add`)
5. Each thread has its own **Xoshiro256++ RNG** (seeded uniquely to avoid races)
6. Threads write to non-overlapping regions of the pixel buffer — no locking needed for writes

### Acceleration Structure (`raytrace/hittable.odin`)
BVH (Bounding Volume Hierarchy) built with median splitting. Reduces ray–scene intersection from O(n) to O(log n). Constructed once, then shared read-only across all threads.

### Ray & Color Logic (`raytrace/vector3.odin`, `raytrace/raytrace.odin`)
- `raytrace/vector3.odin`: Vec3 math, ray definition, `ray_color`, `linear_to_gamma`, `infinity`
- `raytrace/raytrace.odin`: `setup_scene` builds world geometry; `write_buffer_to_ppm` saves the final image

### Materials (`raytrace/material.odin`)
Union-based dispatch over `Lambertian`, `Metallic`, and `Dielectric`. Each implements a `scatter` procedure returning the scattered ray and attenuation color.

### Geometry (`raytrace/hittable.odin`)
`Sphere` and `Cube` primitives. BVH nodes are also `Hittable` variants (recursive union tree).

### Profiling (`raytrace/profiling.odin`)
Zero-cost profiling gated by `PROFILING_ENABLED` compile flag. Records nanosecond-precision timings per thread for: ray generation, `ray_color`, intersection, scatter, background, and pixel setup. Per-phase wall-clock breakdowns (BVH build, render, I/O) are always printed to stdout after the render completes.

### Utilities (`util/`)
- `util/cli.odin`: CLI argument parsing (`Args`, `parse_args_with_short_flags`), system info (`get_number_of_physical_cores`, `print_system_info` via `core:sys/info`).
- `util/rng.odin`: Xoshiro256++ PRNG (`ThreadRNG`, `create_thread_rng`, `random_float`, `random_float_range`).

### Interval Math (`raytrace/interval.odin`)
Simple `Interval` struct used for ray `t`-range clamping and AABB overlap tests.

## Odin-Specific Notes

- Odin uses `import` and has built-in `sync`, `thread`, and `fmt` packages.
- The project uses multiple packages: `main` (root), `util`, `raytrace`, `ui`. Build with `-collection:RT_Weekend=.` so that `import "RT_Weekend:util"` etc. resolve.
- `sync.atomic_add`, `sync.atomic_load` are used for lock-free tile dispatch and progress tracking.
- No heap allocator is configured explicitly; Odin's default context allocator is used.
- Worker threads receive their context via `thread.Thread.data` (a `rawptr` cast to `^ParallelRenderContext`).
- The Raylib trace log callback uses `proc "c"` calling convention; `context = runtime.default_context()` is required at the top to use Odin allocators.
