# core — Shared types

This package holds **shared data types** used by the editor, the path tracer, and the persistence layer. It has **no dependency** on editor, raytrace, or I/O.

## Purpose

- **Core_MaterialKind** — Enum used by both the edit view (Raylib) and the path tracer so neither needs to depend on the other’s material representation.
- **Core_SceneSphere** — Canonical in-memory representation of a sphere for the editor and renderer; `raytrace.build_world_from_scene` converts `[]Core_SceneSphere` to `[dynamic]Object`.
- **Core_CameraParams** — Shared camera definition (lookfrom, lookat, vup, vfov, defocus_angle, focus_dist, max_depth) used by the edit view, camera panel, and path tracer; raytrace applies it to `rt.Render_Camera` before rendering.

## Files

- **types.odin** — `Core_MaterialKind`, `Core_SceneSphere`, `Core_CameraParams`.

## Naming / scope

**Types** in this package use the `Core_` prefix: `Core_CameraParams`, `Core_SceneSphere`, `Core_MaterialKind`. Variables in other packages that hold these use the short prefix `c_` (e.g. `c_camera_params`). This distinguishes shared core types from editor-only (`Editor_*`, `e_`) and render-only (`Render_*`, `r_`) symbols.

## Dependency rule

**core** must not import: editor, raytrace, persistence, or any file I/O. Other packages (util, raytrace, persistence, editor) may import core.
