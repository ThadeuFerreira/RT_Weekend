package core

ConstantTexture :: struct {
	color: [3]f32,
}

CheckerTexture :: struct {
	scale: f32,
	even:  [3]f32,
	odd:   [3]f32,
}

// ImageTexture references an image file by path. At render time the path
// is resolved via an image cache (e.g. build_world_from_scene image_cache).
// Hard-coded or later: import any image as texture.
ImageTexture :: struct {
	path: string,
}

// NoiseTexture produces a smooth Perlin noise pattern scaled to a grey value in [0,1].
// scale controls the spatial frequency: higher = finer detail.
NoiseTexture :: struct {
	scale: f32,
}

// MarbleTexture produces a marble-like pattern using Perlin turbulence modulated by a sine wave.
// scale controls the stripe frequency (multiplied into p.z before sin).
MarbleTexture :: struct {
	scale: f32,
}

Texture :: union {
	ConstantTexture,
	CheckerTexture,
	ImageTexture,
	NoiseTexture,
	MarbleTexture,
}

// TextureKind selects the Lambertian texture type for persistence and scene build.
TextureKind :: enum {
	Constant,
	Checker,
	Image,
}

// MaterialKind is the shared material type used by the edit view (Raylib) and the path tracer.
// Both sides use this enum so no package needs to depend on the other's material representation.
MaterialKind :: enum {
	Lambertian,
	Metallic,
	Dielectric,
}

// SceneSphere is the canonical in-memory representation of a sphere for the editor and the renderer.
// The edit view stores these; raytrace.build_world_from_scene converts them to raytrace.Object.
// For Lambertian: texture_kind and optional checker_* / image_path define the texture (albedo = even/constant color).
SceneSphere :: struct {
	center:            [3]f32,
	center1:           [3]f32, // end position for motion blur (t=1); only used when is_moving
	radius:            f32,
	material_kind:     MaterialKind,
	albedo:            Texture,
	// Lambertian texture (used when material_kind == .Lambertian)
	texture_kind:      TextureKind,  // default .Constant
	checker_scale:     f32,          // for .Checker (default 1)
	checker_color_odd: [3]f32,       // for .Checker; even = albedo
	image_path:        string,       // for .Image; path (absolute or relative to scene file)
	fuzz:              f32,          // used for Metallic (default 0.1)
	ref_idx:           f32,          // used for Dielectric (default 1.5)
	is_moving:         bool,
}

// CameraParams is the shared camera definition used by the edit view (and camera panel) and the path tracer.
// Includes focus distance and defocus angle for depth-of-field. Raytrace applies this to rt.Camera before rendering.
// Shutter open/close are normalized [0..1]; ray time is sampled in this interval (scaffolding; get_ray may use later).
CameraParams :: struct {
	lookfrom:      [3]f32, // camera position
	lookat:        [3]f32, // target point
	vup:           [3]f32, // up vector (typically {0, 1, 0})
	vfov:          f32,    // vertical field of view in degrees
	defocus_angle: f32,    // depth-of-field aperture (degrees, 0 = pin sharp)
	focus_dist:    f32,    // focus distance (distance to in-focus plane)
	max_depth:     int,    // max ray bounces
	shutter_open:  f32,    // motion-blur shutter open time (normalized 0..1, default 0)
	shutter_close: f32,   // motion-blur shutter close time (normalized 0..1, default 1)
}
