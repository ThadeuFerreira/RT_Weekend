# persistence — Scene and config load/save

This package implements **persistence**: scene file and config file load/save. It depends on **core** and **raytrace** (to build Camera and Object for scene I/O).

## Purpose

- **Scene I/O** — `load_scene(path, image_width, image_height, samples_per_pixel)` → `(^Camera, [dynamic]Object, bool)`; `save_scene(path, camera, world)` → `bool`. JSON types: `SceneFile`, `SceneCamera`, `SceneMaterial`, `SceneObject`.
- **Config I/O** — `load_config(path)` → `(RenderConfig, bool)`; `save_config(path, config)` → `bool`. Types: `RenderConfig`, `EditorLayout`, `PanelState`, `RectF`, `LayoutPreset` (panel layout persistence).

## Files

- **scene_io.odin** — Scene JSON (de)serialization; uses raytrace for `Camera`, `Object`, `make_camera`, `init_camera`, material conversion.
- **config_io.odin** — Config JSON (de)serialization and layout types.

## Dependency rule

**persistence** may import **core** and **raytrace**. Callers (main, editor) use these procs for all file-based scene and config operations so the renderer stays I/O-free.
