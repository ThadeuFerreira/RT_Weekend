# core — Shared types

This package holds **shared data types** used by the editor, the path tracer, and the persistence layer. It has **no dependency** on editor, raytrace, or I/O.

## Purpose

- **MaterialKind** — Enum used by both the edit view (Raylib) and the path tracer so neither needs to depend on the other's material representation.
- **SceneSphere** — Canonical in-memory representation of a sphere for the editor and renderer; `raytrace.build_world_from_scene` converts `[]SceneSphere` to `[dynamic]Object`. Includes **center1** and **is_moving** for motion blur (sphere interpolates from `center` to `center1` over the shutter interval); the editor exposes movement as offset dX/dY/dZ = center1 − center.
- **CameraParams** — Shared camera definition (lookfrom, lookat, vup, vfov, defocus_angle, focus_dist, max_depth, **shutter_open**, **shutter_close**) used by the edit view, camera panel, and path tracer; raytrace applies it to `rt.Camera` before rendering. Shutter open/close are normalized [0..1] for motion-blur ray-time sampling (scaffolding; renderer may use in a later pass).

## Files

- **types.odin** — `MaterialKind`, `SceneSphere`, `CameraParams`.

## Naming / scope

Use idiomatic Odin names for core types (`CameraParams`, `SceneSphere`, `MaterialKind`). In caller code, use `c_` for variables/fields that hold core values (e.g. `c_camera_params`).

## Dependency rule

**core** must not import: editor, raytrace, persistence, or any file I/O. Other packages (util, raytrace, persistence, editor) may import core.
