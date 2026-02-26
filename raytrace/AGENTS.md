# raytrace — Renderer (path tracer)

This package is the **path tracer only**: camera, BVH, materials, ray math, tile-based parallel rendering. It does **not** perform scene file I/O; that lives in **persistence**.

## Purpose

- **Camera** — `Camera`, `make_camera`, `init_camera`, `apply_scene_camera`, `copy_camera_to_scene_params`; non-blocking render API: `start_render`, `get_render_progress`, `finish_render`, `RenderSession`.
- **Scene build** — `convert_world_to_edit_spheres`, `build_world_from_scene` (core.SceneSphere ↔ Object).
- **Geometry** — `Sphere`, `Cube`, `Object` union; BVH and intersection in **hittable.odin**.
- **Materials** — `material` union (lambertian, metallic, dielectric), `scatter` in **material.odin**.
- **Ray / color** — Vec3, ray math, `ray_color`, `linear_to_gamma` in **vector3.odin**; **raytrace.odin**: `TestPixelBuffer`, `write_buffer_to_ppm`, scene setup helpers.
- **Profiling** — `PROFILING_ENABLED`, `Profile_Scope`, per-phase timings in **profiling.odin**.
- **Interval** — `Interval`, `interval_clamp`, etc. in **interval.odin**.

## Files

- **camera.odin** — Camera struct, tile queue, worker threads, start/get_progress/finish.
- **scene_build.odin** — World ↔ core.SceneSphere conversion.
- **vector3.odin**, **raytrace.odin**, **hittable.odin**, **material.odin**, **interval.odin**, **profiling.odin**.

## Dependency rule

**raytrace** depends only on **core** and **util**. Scene file load/save are in **persistence** (which imports raytrace for Camera and Object).
