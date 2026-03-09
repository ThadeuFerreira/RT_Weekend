# Raylib texture mapping test (Odin)

Minimal standalone project to test Raylib 3D texture mapping: textured sphere with orbital camera. Ported from the C++ reference.

**Cube-normalized sphere:** The sphere mesh is built by normalizing the six faces of a subdivided cube (each face point is moved to the unit sphere). This avoids polar singularities and thin triangles at the poles that you get with the usual polar (latitude/longitude) parametrization Raylib’s `GenMeshSphere` uses. Texture coordinates are equirectangular so a single 2D earth-style texture works. See `cube_sphere.odin` and the “Making a sphere” article (piecewise algebraic parametrization).

## Requirements

- [Odin](https://odin-lang.org/) (with vendor collection; raylib is in `$(odin root)/vendor/raylib`).
- Texture: put **`earth90.png`** in `resources/`. The C++ comment says the texture must be rotated 90° for correct sphere UVs; you can use any equirectangular-style image (e.g. from [raylib examples](https://github.com/raysan5/raylib/tree/master/examples/resources) or create a 90°-rotated version).

## Build & run

From this directory (`raylib_texture_test/`):

```bash
make debug    # build
make run      # build and run
```

Or manually:

```bash
odin build . -out:build/texture_test
./build/texture_test
```

Run from **`raylib_texture_test/`** so the path `resources/earth90.png` resolves. If the texture is missing, the sphere will render with the default material (no albedo texture).

## Controls

- **Orbital camera**: same as reference (mouse drag to orbit, scroll to zoom; depends on raylib `CAMERA_ORBITAL`).
- Close window or ESC to exit.

## Reference

C++ code used as reference: `InitWindow`, `SetConfigFlags` (VSYNC, MSAA, HIGHDPI), `Camera3D`, `LoadTexture`, `GenMeshSphere`, `LoadModelFromMesh`, `SetMaterialTexture` (albedo), `UpdateCamera(..., CAMERA_ORBITAL)`, `DrawModelEx`, cleanup.
