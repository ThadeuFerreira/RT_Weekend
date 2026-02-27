# raytrace — Renderer (path tracer)

This package is the **path tracer only**: camera, BVH, materials, ray math, tile-based parallel rendering. It does **not** perform scene file I/O; that lives in **persistence**.

## Purpose

- **Camera** — `Render_Camera`, `make_render_camera`, `init_render_camera`, `apply_scene_render_camera`, `copy_render_camera_to_scene_params`; non-blocking render API: `start_render`, `get_render_progress`, `finish_render`, `RenderSession` (field `r_camera`).
- **Scene build** — `convert_world_to_edit_spheres`, `build_world_from_scene` (core.Core_SceneSphere ↔ Object).

## Naming / scope

**Types** use the `Render_` prefix for renderer types (e.g. `Render_Camera`). **Functions** use full names (e.g. `init_render_camera`, `make_render_camera`, `apply_scene_render_camera`). **Variables/fields** use the short prefix `r_` (e.g. `session.r_camera`, `r_world` in caller code). This distinguishes the path-tracer camera and session from editor (`Editor_*`, `e_`) and core (`Core_*`, `c_`) symbols.
- **Geometry** — `Sphere`, `Cube`, `Object` union; BVH and intersection in **hittable.odin**.
- **Materials** — `material` union (lambertian, metallic, dielectric), `scatter` in **material.odin**.
- **Ray / color** — Vec3, ray math, `ray_color`, `linear_to_gamma` in **vector3.odin**; **raytrace.odin**: `TestPixelBuffer`, `write_buffer_to_ppm`, scene setup helpers.
- **Profiling** — `PROFILING_ENABLED`, `Profile_Scope`, per-phase timings in **profiling.odin**.
- **Interval** — `Interval`, `interval_clamp`, etc. in **interval.odin**.

## Files

- **camera.odin** — Render_Camera struct, tile queue, worker threads, start/get_progress/finish.
- **scene_build.odin** — World ↔ core.Core_SceneSphere conversion.
- **vector3.odin**, **raytrace.odin**, **hittable.odin**, **material.odin**, **interval.odin**, **profiling.odin**.

## Dependency rule

**raytrace** depends only on **core** and **util**. Scene file load/save are in **persistence** (which imports raytrace for Render_Camera and Object).
