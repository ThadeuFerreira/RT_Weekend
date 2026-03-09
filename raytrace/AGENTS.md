# raytrace — Renderer (path tracer)

This package is the **path tracer only**: camera, BVH, materials, ray math, tile-based parallel rendering. It does **not** perform scene file I/O; that lives in **persistence**.

## Purpose

- **Camera** — `Camera`, `make_camera`, `init_camera`, `apply_scene_camera`, `copy_camera_to_scene_params`; non-blocking render API: `start_render`, `get_render_progress`, `finish_render`, `RenderSession` (field `r_camera`). Camera includes **shutter_open**, **shutter_close** (normalized [0..1]); `get_ray` samples ray time in that interval for motion blur. `normalize_shutter` is optional validation (see TODO at definition).
- **Scene build** — `convert_world_to_edit_spheres`, `build_world_from_scene` (core.SceneSphere ↔ Object).

## Naming / scope

Use idiomatic Odin names for raytrace types/functions (`Camera`, `make_camera`, `init_camera`, etc.). Use `r_` for variables/fields that hold render state (e.g. `r_camera`, `r_session`, `r_world`).
- **Geometry** — `Sphere` in **sphere.odin**; `Quad` and rect helpers in **quad.odin**; `Object` union, AABB, BVH, and `hit()` in **hittable.odin**.
- **Materials** — `material` union (lambertian, metallic, dielectric), `scatter` in **material.odin**. Lambertian uses **Texture** (core union: ConstantTexture, CheckerTexture) for albedo; metallic/dielectric use plain `[3]f32` or ref_idx.
- **Textures** — Types aliased from **core** in **texture.odin**; `texture_value(tex, u, v, p)` returns sampled color. Used by CPU path (material.odin) and by **gpu_types.odin** / **scene_to_gpu_spheres** for GPU (TEX_CONSTANT, TEX_CHECKER). **texture_image.odin** — `Texture_Image` for image files: load via `vendor:stb/image` (LDR `texture_image_load` or HDR `texture_image_loadf`), `texture_image_convert_to_bytes`, clamped `texture_image_pixel_data`; cleanup with `texture_image_destroy`. Use `texture_image_byte_slice` or `texture_image_float_slice` for contiguous data for compute-shader upload (SSBO or texture).
- **Ray / color** — Vec3, ray math, `ray_color`, `linear_to_gamma` in **vector3.odin**; **raytrace.odin**: `TestPixelBuffer`, `write_buffer_to_ppm`, scene setup helpers.
- **Profiling** — `PROFILING_ENABLED`, `Profile_Scope`, per-phase timings in **profiling.odin**. `VERBOSE_OUTPUT` (#config, default true) gates non-essential stdout; `aggregate_into_summary` always runs so the Stats panel has data in release builds.
- **Interval** — `Interval`, `interval_clamp`, etc. in **interval.odin**.

## Files

- **camera.odin** — Camera struct, tile queue, worker threads, start/get_progress/finish.
- **scene_build.odin** — World ↔ core.SceneSphere conversion; `build_world_from_scene(..., ground_texture: Texture)` takes texture by value.
- **texture.odin** — Core texture type aliases; `texture_value(tex, u, v, p)`.
- **texture_image.odin** — `Texture_Image` (stb/image): load, destroy, pixel_data (clamped), convert_to_bytes; byte_slice/float_slice for GPU upload.
- **sphere.odin** — `Sphere`, `sphere_center_at`, `sphere_get_uv`, `sphere_bounding_box`.
- **quad.odin** — `Quad`, `make_quad`, `quad_bounding_box`, `aabb_from_points`, `xy_rect`, `xz_rect`, `yz_rect`.
- **hittable.odin** — `hit_record`, `Object` union, AABB, BVH (build/flatten/linear), `hit()`, `set_face_normal`.
- **vector3.odin**, **raytrace.odin**, **material.odin**, **interval.odin**, **profiling.odin**, **gpu_types.odin** (GPU texture fields: tex_type, tex_scale, tex_even, tex_odd).

## Dependency rule

**raytrace** depends only on **core** and **util**. Scene file load/save are in **persistence** (which imports raytrace for Camera and Object).

## Allocation preference

Prefer stack allocation; avoid passing pointers unless strictly necessary. Texture is passed by value (e.g. `build_world_from_scene(..., ground_texture: Texture)`, `texture_value(tex: Texture, ...)`). Use pointers only when needed (e.g. optional ground texture in editor, or legacy `setup_scene(..., ground_texture: ^Texture = nil)`).
