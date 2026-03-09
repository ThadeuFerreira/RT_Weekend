// Standalone test: Raylib textured sphere with orbital camera.
// Build: odin build . -out:build/texture_test
// Run from raylib_texture_test/ so "resources/earthmap1k.jpg" is found.

package main

import "core:c"
import "core:c/libc"
import "core:math"
import "core:strings"
import rl "vendor:raylib"


main :: proc() {
	// Initialization
	screen_width  :: 800
	screen_height :: 450
	rl.SetConfigFlags(rl.ConfigFlags{.VSYNC_HINT, .MSAA_4X_HINT, .WINDOW_HIGHDPI})
	rl.InitWindow(screen_width, screen_height, "raylib - Textured Sphere (Odin)")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	// Camera
	camera: rl.Camera3D
	camera.position   = rl.Vector3{0.0, 0.0, 100.0}
	camera.target     = rl.Vector3{0.0, 0.0, 0.0}
	camera.up         = rl.Vector3{0.0, 1.0, 0.0}
	camera.fovy       = 45.0
	camera.projection = .PERSPECTIVE

	// Load texture (image may need to be rotated 90° for sphere UVs — same as C++ comment)
	texture_path := "resources/2k_earth_daymap.jpg"
	texture := rl.LoadTexture(strings.unsafe_string_to_cstring(texture_path))
	defer rl.UnloadTexture(texture)

	// Sphere: standard sphere mesh with get_sphere_uv equirectangular UVs
	position := rl.Vector3{0.0, 0.0, 0.0}
	axis     := rl.Vector3{1.0, 0.0, 0.0}
	scale    := rl.Vector3{1.0, 1.0, 1.0}
	angle    :: -90.0
	radius   :: 10.0
	n_rings  :: 32
	n_slices :: 32
	tint     := rl.WHITE

	sphere_mesh := rl.GenMeshSphere(radius, n_rings, n_slices)
	// reinterpret the []f32 slice as []rl.Vector2 so we can use .x & .y easily
	uvs := transmute([]rl.Vector2)(sphere_mesh.texcoords[:sphere_mesh.vertexCount])
	// simply swap x and y!
	for &uv in uvs {uv.x, uv.y = uv.y, uv.x}
	// important part, need to tell raylib to update the mesh buffer on the GPU 
	rl.UpdateMeshBuffer(sphere_mesh, 1, raw_data(uvs), i32(len(uvs) * size_of(rl.Vector2)), 0)
	defer rl.UnloadMesh(sphere_mesh)
	sphere := rl.LoadModelFromMesh(sphere_mesh)
	defer rl.UnloadModel(sphere)
	rl.SetMaterialTexture(&sphere.materials[0], rl.MaterialMapIndex.ALBEDO, texture)

	// Main loop
	for !rl.WindowShouldClose() {
		rl.UpdateCamera(&camera, rl.CameraMode.ORBITAL)
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		rl.BeginMode3D(camera)
		rl.DrawModelEx(sphere, position, axis, angle, scale, tint)
		rl.EndMode3D()
		rl.EndDrawing()
	}
}
