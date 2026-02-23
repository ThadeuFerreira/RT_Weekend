# agents.md

This file guides AI agents working autonomously in this repository.

## Project Summary

A [Ray Tracing in One Weekend](https://raytracing.github.io/)–style path tracer built in the [Odin programming language](https://odin-lang.org/). The project combines a CPU path tracer core with:

- **[Raylib](https://www.raylib.com/)** for windowing, UI, and logging
- **Scene editing** — interactive control over objects and materials at runtime
- **GPU acceleration** via Vulkan and OpenGL (Nvidia, AMD, Intel)
- **Cross-platform** — Linux, macOS, Windows

## Build & Verify

Always build before testing changes:

```bash
odin build . -debug -out:build/debug
```

Verify correctness with a small, fast render:

```bash
./build/debug -w 100 -h 100 -s 5 -o test.ppm
```

For performance changes, use a timed render (timing is always printed to stdout):

```bash
./build/debug -w 800 -h 450 -s 50 --no-progress -o bench.ppm
```

## Current File Responsibilities

| File | Responsibility |
|---|---|
| `main.odin` | Entry point, CLI parsing, scene generation |
| `camera.odin` | Parallel rendering, tile dispatch, thread management |
| `hittable.odin` | Sphere/Cube geometry, BVH tree construction and traversal |
| `material.odin` | Lambertian, Metallic, Dielectric scatter logic |
| `vector3.odin` | Vec3 math, Ray struct, recursive `ray_color` |
| `raytrace.odin` | `world_ray_color`, pixel buffer, PPM file output |
| `utils.odin` | Argument parsing, RNG (Xoshiro256++), progress bar |
| `interval.odin` | `t`-range clamping, AABB overlap checks |
| `profiling.odin` | Nanosecond timing, gated by `PROFILING_ENABLED` |

All files belong to a single Odin package — they compile together with no subdirectories.

## Planned Architecture

### UI Layer (Raylib)
- Raylib owns the window, input loop, and log output.
- The rendered image (pixel buffer) is uploaded to a Raylib texture each frame and drawn to the screen.
- Scene editing controls (object placement, material parameters) will be driven through Raylib's input and immediate-mode UI.
- Use Raylib's `TraceLog` for all runtime logging; do not use `fmt.println` for user-facing output once Raylib is integrated.

### GPU Acceleration
- Vulkan and OpenGL backends are the target GPU APIs.
- GPU path must run on Nvidia, AMD, and Intel hardware; avoid vendor-specific extensions.
- The CPU path tracer (`camera.odin` + `vector3.odin`) should remain intact as a fallback and reference implementation.
- Shader code should be kept in separate files (e.g., `shaders/`) and loaded at runtime via Raylib or a thin wrapper.

### Scene Editing
- Scenes are currently generated procedurally in `main.odin`. The scene representation needs to be promoted to a mutable, runtime-editable structure.
- Materials and objects should be editable without restarting the application.
- When the scene changes, the BVH must be rebuilt before the next render pass.

### Cross-Platform
- Odin has cross-platform support built in; avoid OS-specific syscalls outside of `utils.odin`.
- Raylib handles platform differences for windowing and input.
- GPU backend selection (Vulkan vs OpenGL) should be a runtime or compile-time flag, not hard-coded.

## Concurrency Rules

These must be respected when modifying rendering code:

- The **BVH and camera** are read-only during rendering. Never write to them from worker threads.
- **Tile dispatch** uses `sync.atomic_add`. Do not replace with a mutex.
- Each worker thread has its **own Xoshiro256++ RNG instance**. Do not share RNG state across threads.
- The **pixel buffer** is partitioned by tile; threads write to non-overlapping regions with no locking needed.

## Extending the Renderer

### Adding a New Material
1. Add a struct and include it in the `Material` union in `material.odin`.
2. Add a `scatter` case in the `scatter` procedure.
3. Optionally register it in the scene editor / `main.odin` generator.

### Adding a New Primitive
1. Define the struct and AABB in `hittable.odin`.
2. Add it to the `Hittable` union.
3. Add a hit-test case in the `hit` procedure.
4. The BVH picks it up automatically.

## Constraints

- **Tile size (32×32)** is tuned for cache locality — do not change without benchmarking.
- **Xoshiro256++** in `utils.odin` must not be replaced with a standard-library RNG that requires locking.
- Do not introduce global mutable state. Thread safety is kept explicit by passing context through procedure parameters.
- Output format is **P6 binary PPM** by default. `write_ppm_ascii` (P3) exists but is slow — not for benchmarks.
