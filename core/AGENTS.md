# core — Shared types

This package holds **shared data types** used by the editor, the path tracer, and the interfaces layer. It has **no dependency** on editor, raytrace, or I/O.

## Purpose

- **MaterialKind** — Enum used by both the edit view (Raylib) and the path tracer so neither needs to depend on the other’s material representation.
- **SceneSphere** — Canonical in-memory representation of a sphere for the editor and renderer; `raytrace.build_world_from_scene` converts `[]SceneSphere` to `[dynamic]Object`.
- **CameraParams** — Shared camera definition (lookfrom, lookat, vup, vfov, defocus_angle, focus_dist, max_depth) used by the edit view, camera panel, and path tracer; raytrace applies it to `rt.Camera` before rendering.

## Files

- **types.odin** — `MaterialKind`, `SceneSphere`, `CameraParams`.

## Dependency rule

**core** must not import: editor, raytrace, interfaces, or any file I/O. Other packages (util, raytrace, interfaces, editor) may import core.
