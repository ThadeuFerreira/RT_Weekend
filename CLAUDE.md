# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This project is written in the [Odin programming language](https://odin-lang.org/).

```bash
# Build debug binary (use collection so main can import core, util, raytrace, interfaces, editor)
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

### UI assets (SDF font and shader)
- **`assets/fonts/Inter-Regular.ttf`** — Inter (OFL-licensed, Arial-like) used for UI text when SDF font loading succeeds. Sourced from [rsms/inter](https://github.com/rsms/inter).
- **`assets/shaders/sdf.fs`** — Raylib SDF fragment shader (GLSL 330) for signed-distance-field text rendering.

**Feature flag:** SDF/custom font loading is **off by default** (`USE_SDF_FONT = false`). With it disabled, the UI uses Raylib’s default font only. To enable SDF and custom font loading, build with `-define:USE_SDF_FONT=true`.

Paths are resolved **relative to the current working directory** at launch. Run the binary from the repository root (e.g. `./build/debug`) so `assets/fonts/` and `assets/shaders/` are found when the flag is enabled. If the font or shader fails to load, the UI falls back to Raylib’s default font.

## Project layout (packages)

Layout is Godot-inspired: **core** (shared types), **raytrace** (renderer only), **interfaces** (system I/O), **editor** (application UI). See each major folder’s **AGENTS.md** for scoped context.

- **`main.odin`** (package `main`) — entry point; imports `RT_Weekend:core`, `RT_Weekend:util`, `RT_Weekend:raytrace`, `RT_Weekend:interfaces`, `RT_Weekend:editor`.
- **`core/`** (package `core`) — shared types used by editor and renderer: `MaterialKind`, `CameraParams`, `SceneSphere`. No I/O, no editor/raytrace dependency. See [core/AGENTS.md](core/AGENTS.md).
- **`util/`** (package `util`) — CLI args (`Args`, `parse_args_with_short_flags`), system info (`get_number_of_physical_cores`, `print_system_info`), per-thread RNG. No file I/O. See [util/AGENTS.md](util/AGENTS.md).
- **`raytrace/`** (package `raytrace`) — path tracer only: camera, BVH, materials, vector/ray math, pixel buffer, profiling, `scene_build`. No scene file I/O. See [raytrace/AGENTS.md](raytrace/AGENTS.md).
- **`interfaces/`** (package `interfaces`) — system I/O: `load_scene`/`save_scene`, `load_config`/`save_config`; types `RenderConfig`, `EditorLayout`, etc. Depends on core and raytrace. See [interfaces/AGENTS.md](interfaces/AGENTS.md).
- **`editor/`** (package `editor`) — Raylib window, panels, menus, layout, widgets, fonts. Exports `run_app`. Depends on core, util, raytrace, interfaces. See [editor/AGENTS.md](editor/AGENTS.md).

## Architecture Overview

The renderer is a standard path tracer built around these layers:

### Entry & Scene Setup (`main.odin` + `raytrace/` + `interfaces/`)
`main.odin` parses CLI arguments (util), loads config/scene via `interfaces` when paths are given, builds camera and world (or uses raytrace for empty scene), then calls `editor.run_app()`.

Scene file I/O is in **interfaces** (`load_scene`, `save_scene`); config I/O is `interfaces.load_config` / `save_config`.

### Editor (`editor/`)
`run_app()` (in `editor/app.odin`) owns the main thread and the Raylib event loop:
1. Creates the window and a GPU texture sized to the render output
2. Calls `start_render()` to kick off background worker threads (non-blocking)
3. Each frame: uploads partial pixel buffer to GPU, polls progress, calls `finish_render()` when all tiles are done
4. Draws panels, menu bar, and layout via `editor/ui.odin` and panel-specific modules

`editor/ui.odin`: `update_panel`, `draw_panel_chrome`, `upload_render_texture`. Panels (render, stats, log, edit view, camera, object props, preview port, system info) and menus/layout live in the same package. SDF font in `editor/font_sdf.odin`; `draw_ui_text` / `measure_ui_text` in `app.odin`.

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
- `util/rng.odin`: Xoshiro256++ PRNG (`ThreadRNG`, `create_thread_rng`, `random_float`, `random_float_range`). Config/file I/O lives in **interfaces**, not util.

### Interval Math (`raytrace/interval.odin`)
Simple `Interval` struct used for ray `t`-range clamping and AABB overlap tests.

## Odin-Specific Notes

- Odin uses `import` and has built-in `sync`, `thread`, and `fmt` packages.
- The project uses multiple packages: `main` (root), `core`, `util`, `raytrace`, `interfaces`, `editor`. Build with `-collection:RT_Weekend=.` so that `import "RT_Weekend:editor"` etc. resolve.
- `sync.atomic_add`, `sync.atomic_load` are used for lock-free tile dispatch and progress tracking.
- No heap allocator is configured explicitly; Odin's default context allocator is used.
- Worker threads receive their context via `thread.Thread.data` (a `rawptr` cast to `^ParallelRenderContext`).
- The Raylib trace log callback uses `proc "c"` calling convention; `context = runtime.default_context()` is required at the top to use Odin allocators.
