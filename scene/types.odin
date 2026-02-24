package scene

// MaterialKind is the shared material type used by the edit view (Raylib) and the path tracer.
// Both sides use this enum so no package needs to depend on the other's material representation.
MaterialKind :: enum {
	Lambertian,
	Metallic,
	Dielectric,
}

// SceneSphere is the canonical in-memory representation of a sphere for the editor and the renderer.
// The edit view stores these; raytrace.build_world_from_scene converts them to raytrace.Object.
SceneSphere :: struct {
	center:       [3]f32,
	radius:       f32,
	material_kind: MaterialKind,
	albedo:       [3]f32,
	fuzz:         f32, // used for Metallic (default 0.1)
	ref_idx:      f32, // used for Dielectric (default 1.5)
}

// CameraParams is the shared camera definition used by the edit view (and camera panel) and the path tracer.
// Includes focus distance and defocus angle for depth-of-field. Raytrace applies this to rt.Camera before rendering.
CameraParams :: struct {
	lookfrom:      [3]f32, // camera position
	lookat:        [3]f32, // target point
	vup:           [3]f32, // up vector (typically {0, 1, 0})
	vfov:          f32,    // vertical field of view in degrees
	defocus_angle: f32,    // depth-of-field aperture (degrees, 0 = pin sharp)
	focus_dist:    f32,    // focus distance (distance to in-focus plane)
	max_depth:     int,    // max ray bounces
}
