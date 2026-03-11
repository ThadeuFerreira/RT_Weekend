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
	DiffuseLight,
	Isotropic,
}

// SceneVolume defines a constant-density participating medium (fog/smoke) inside an axis-aligned box.
// The box is specified in local space (box_min, box_max), then rotated and translated.
// density: scattering coefficient; albedo: color of the isotropic phase function.
SceneVolume :: struct {
	box_min:       [3]f32,
	box_max:       [3]f32,
	rotate_y_deg:  f32,
	translate:     [3]f32,
	density:       f32,
	albedo:        [3]f32,
}

// Ground-sphere heuristic: used when a sphere is not explicitly marked (e.g. loading from world or legacy scenes).
// Spheres with center.y below this and radius above GROUND_SPHERE_RADIUS_MIN are treated as ground (excluded from bounds, skipped in edit list).
GROUND_SPHERE_CENTER_Y_MAX :: -100
GROUND_SPHERE_RADIUS_MIN   :: 100

// is_ground_heuristic returns true if the given center_y and radius match the legacy ground-plane convention.
// Use for rt.Sphere (world) or when SceneSphere.is_ground is not set. Scale-invariant identification should use is_ground on SceneSphere instead.
is_ground_heuristic :: proc(center_y, radius: f32) -> bool {
	return center_y < GROUND_SPHERE_CENTER_Y_MAX && radius > GROUND_SPHERE_RADIUS_MIN
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
	is_ground:         bool,         // if true, sphere is treated as ground (excluded from bounds, etc.); use for scale-invariant scenes
}

// scene_sphere_is_ground returns true if the sphere should be treated as ground (excluded from bounds, skip in edit list).
// Uses is_ground when set; otherwise falls back to is_ground_heuristic for backward compatibility.
scene_sphere_is_ground :: proc(s: SceneSphere) -> bool {
	return s.is_ground || is_ground_heuristic(s.center[1], s.radius)
}

// Default sky color when a ray misses the scene. Black so the only light comes from emitters.
CAMERA_BACKGROUND_DEFAULT :: [3]f32{0, 0, 0}
// Sky color for example scenes and backward compatibility (bluish gradient feel).
CAMERA_BACKGROUND_SKY :: [3]f32{0.70, 0.80, 1.00}

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
	background:    [3]f32, // sky color when ray misses (default CAMERA_BACKGROUND_DEFAULT)
}
