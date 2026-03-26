# raytrace — Renderer (path tracer)

This package is the **path tracer only**: camera, BVH, materials, ray math, tile-based parallel rendering. It does **not** perform scene file I/O; that lives in **persistence**.

## Purpose

- **Camera** — `Camera`, `make_camera`, `init_camera`, `apply_scene_camera`, `copy_camera_to_scene_params`; non-blocking render API: `start_render`, `get_render_progress`, `finish_render`, `RenderSession` (field `r_camera`). Camera includes **shutter_open**, **shutter_close** (normalized [0..1]); `get_ray` samples ray time in that interval for motion blur. `normalize_shutter` is optional validation (see TODO at definition).
- **Scene build** — `convert_world_to_edit_spheres`, `build_world_from_scene` (core.SceneSphere ↔ Object).

## Naming / scope

Use idiomatic Odin names for raytrace types/functions (`Camera`, `make_camera`, `init_camera`, etc.). Use `r_` for variables/fields that hold render state (e.g. `r_camera`, `r_session`, `r_world`).
- **Geometry** — `Sphere` + `hit_sphere` in **sphere.odin**; `Quad`, `hit_quad`, and rect helpers in **quad.odin**; `ConstantMedium`, `constant_medium_hit`, and volume builders in **volume.odin**; `Object` union and `hit()` dispatch in **hittable.odin**.
- **AABB** — `AABB`, `aabb_union`, `aabb_hit`, `aabb_hit_fast`, `aabb_from_points` in **aabb.odin**.
- **BVH** — `BVHNode`, `build_bvh`, `build_bvh_sah`, `bvh_hit` (recursive), `free_bvh` in **bvh.odin**; `flatten_bvh`, `flatten_bvh_for_gpu`, `bvh_hit_linear` (iterative) in **bvh_linear.odin**.
- **Materials** — `material` union (lambertian, metallic, dielectric, diffuse_light, isotropic), `scatter`, `emitted` in **material.odin**. Lambertian uses **RTexture** for albedo; metallic/dielectric use plain `[3]f32` or ref_idx.
- **Textures** — Types aliased from **core** in **texture.odin**; shared sampling helpers (`_sample_constant`, `_sample_checker`, `_sample_noise`, `_sample_marble`) used by both `texture_value` (core Texture) and `texture_value_runtime` (RTexture). **texture_image.odin** — `Texture_Image` for image files: load via `vendor:stb/image`, pixel_data, destroy; byte_slice/float_slice for GPU upload.
- **Ray / color** — Vec3, ray math, `linear_to_gamma` in **vector3.odin**; `ray_color`, `ray_color_linear` in **ray_color.odin**; **raytrace.odin**: `TestPixelBuffer`, `write_buffer_to_ppm`, scene setup helpers.
- **Profiling** — `PROFILING_ENABLED`, `Profile_Scope`, per-phase timings in **profiling.odin**. `VERBOSE_OUTPUT` (#config, default true) gates non-essential stdout; `aggregate_into_summary` always runs so the Stats panel has data in release builds.
- **Interval** — `Interval`, `interval_clamp`, etc. in **interval.odin**.

## Files

- **hittable.odin** — `hit_record`, `Object` union, `object_bounding_box`, `set_face_normal`, `hit()` dispatch.
- **aabb.odin** — `AABB`, `aabb_union`, `aabb_surface_area`, `aabb_hit`, `aabb_hit_fast`, `aabb_from_points`, `aabb_pad_to_minimums`.
- **bvh.odin** — `BVHNode`, `build_bvh`, `build_bvh_sah`, `bvh_hit`, `free_bvh`, `object_center`, `collect_quads_from_bvh`.
- **bvh_linear.odin** — `flatten_bvh`, `flatten_bvh_for_gpu`, `bvh_hit_linear`.
- **sphere.odin** — `Sphere`, `sphere_center_at`, `sphere_get_uv`, `sphere_bounding_box`, `hit_sphere`.
- **quad.odin** — `Quad`, `make_quad`, `quad_bounding_box`, `hit_quad`, `xy_rect`, `xz_rect`, `yz_rect`, `append_box`.
- **volume.odin** — `ConstantMedium` builders, `constant_medium_hit`, `boundary_hit_interval`, `free_volume_object`.
- **ray_color.odin** — `ray_color` (recursive BVH), `ray_color_linear` (iterative BVH).
- **vector3.odin** — Vec3 math, `ray`, `ray_at`, `linear_to_gamma`, `dot`, `cross`, `unit_vector`.
- **camera.odin** — Camera struct, tile queue, worker threads, start/get_progress/finish.
- **scene_build.odin** — World ↔ core.SceneSphere conversion; `build_world_from_scene`.
- **texture.odin** — Core texture type aliases; shared sampling helpers; `texture_value`, `texture_value_runtime`.
- **texture_image.odin** — `Texture_Image` (stb/image): load, destroy, pixel_data; byte_slice/float_slice for GPU upload.
- **material.odin**, **interval.odin**, **profiling.odin**, **perlin.odin**, **transform.odin**.
- **gpu_types.odin** — `LinearBVHNode`, `GPUSphere`, `GPUQuad`, `GPUVolume`, `LEAF_*` sentinels, scene-to-GPU converters.
- **render_backend.odin**, **cpu_backend.odin**, **gpu_backend_adapter.odin**, **gpu_backend_vulkan.odin**, **gpu_renderer.odin**.

## Dependency rule

**raytrace** depends only on **core** and **util**. Scene file load/save are in **persistence** (which imports raytrace for Camera and Object).

## Allocation preference

Prefer stack allocation; avoid passing pointers unless strictly necessary. Texture is passed by value (e.g. `build_world_from_scene(..., ground_texture: Texture)`, `texture_value(tex: Texture, ...)`). Use pointers only when needed (e.g. optional ground texture in editor, or legacy `setup_scene(..., ground_texture: ^Texture = nil)`).
