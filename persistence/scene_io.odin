package persistence

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"

// Intermediate types for JSON (avoid union unmarshaling).

SceneCamera :: struct {
	lookfrom:      [3]f32 `json:"lookfrom"`,
	lookat:        [3]f32 `json:"lookat"`,
	vup:           [3]f32 `json:"vup"`,
	vfov:          f32   `json:"vfov,omitempty"`,
	defocus_angle: f32   `json:"defocus_angle,omitempty"`,
	focus_dist:    f32   `json:"focus_dist,omitempty"`,
	max_depth:     int   `json:"max_depth,omitempty"`,
	shutter_open:  f32   `json:"shutter_open,omitempty"`,
	shutter_close: f32   `json:"shutter_close,omitempty"`,
	background:    [3]f32 `json:"background,omitempty"`,
}

SceneMaterial :: struct {
	material_type:     string  `json:"type"`,
	albedo:            [3]f32  `json:"albedo,omitempty"`,
	image_path:        string  `json:"image_path,omitempty"`,
	// texture_kind: "constant" (default), "checker", "image", "noise", "marble". Missing → constant (backward compat).
	texture_kind:      string  `json:"texture_kind,omitempty"`,
	checker_scale:     f32     `json:"checker_scale,omitempty"`,
	checker_color_odd: [3]f32  `json:"checker_color_odd,omitempty"`,
	noise_scale:       f32     `json:"noise_scale,omitempty"`,
	fuzz:              f32     `json:"fuzz,omitempty"`,
	ref_idx:           f32     `json:"ref_idx,omitempty"`,
}

SceneObject :: struct {
	object_type:  string        `json:"type"`,
	center:       [3]f32        `json:"center,omitempty"`,
	center1:      [3]f32        `json:"center1,omitempty"`, // end position for motion blur (t=1)
	radius:       f32           `json:"radius,omitempty"`,
	material:     SceneMaterial `json:"material"`,
	is_moving:    bool          `json:"is_moving,omitempty"`,
	// Quad: corner Q and edge vectors u, v.
	q:            [3]f32        `json:"q,omitempty"`,
	u:            [3]f32        `json:"u,omitempty"`,
	v:            [3]f32        `json:"v,omitempty"`,
	rotation_deg: [3]f32        `json:"rotation_deg,omitempty"`,
	scale_xyz:    [3]f32        `json:"scale_xyz,omitempty"`,
}

// SceneVolumeData is the JSON-serializable form of a volume (constant-density fog/smoke box).
SceneVolumeData :: struct {
	box_min:       [3]f32 `json:"box_min"`,
	box_max:       [3]f32 `json:"box_max"`,
	rotate_y_deg:  f32    `json:"rotate_y_deg,omitempty"`,
	translate:     [3]f32 `json:"translate,omitempty"`,
	density:       f32    `json:"density,omitempty"`,
	albedo:        [3]f32 `json:"albedo,omitempty"`,
}

SceneFile :: struct {
	camera:  SceneCamera          `json:"camera"`,
	objects: [dynamic]SceneObject `json:"objects"`,
	volumes: [dynamic]SceneVolumeData `json:"volumes,omitempty"`,
}

@(private)
_is_black_background :: proc(bg: [3]f32) -> bool {
	return bg[0] == 0.0 && bg[1] == 0.0 && bg[2] == 0.0
}

@(private)
_scene_has_emissive_material :: proc(objects: []SceneObject) -> bool {
	for obj in objects {
		switch obj.material.material_type {
		case "diffuse_light", "emissive":
			return true
		}
	}
	return false
}

// _scene_resolve_image_path returns an absolute path for loading. Relative paths are resolved against scene_dir.
@(private)
_scene_resolve_image_path :: proc(scene_dir, image_path: string, allocator := context.allocator) -> string {
	if len(image_path) == 0 do return ""
	when ODIN_OS == .Windows {
		if len(image_path) >= 3 && image_path[1] == ':' && (image_path[2] == '\\' || image_path[2] == '/') {
			return strings.clone(image_path, allocator)
		}
	} else {
		if image_path[0] == '/' {
			return strings.clone(image_path, allocator)
		}
	}
	return strings.concatenate({scene_dir, filepath.SEPARATOR_STRING, image_path}, allocator)
}

// load_scene loads camera and objects from a JSON scene file. Resolution/samples come from arguments.
// When image_cache is non-nil, image_path fields in lambertian materials are loaded from disk (paths relative to
// the scene file directory) and stored in the cache; the world is then built with ImageTextureRuntime so
// image textures render correctly. When image_cache is nil, image_path is ignored and lambertian uses albedo only.
// Returns (camera, world, volumes, true) on success; (nil, nil, nil, false) on error.
// volumes is the list of scene volume definitions (for editor round-trip); caller must delete(volumes).
load_scene :: proc(
	path: string,
	image_width: int,
	image_height: int,
	samples_per_pixel: int,
	image_cache: ^map[string]^rt.Texture_Image = nil,
) -> (^rt.Camera, [dynamic]rt.Object, [dynamic]core.SceneVolume, bool) {
	data, read_ok := os.read_entire_file(path)
	if !read_ok {
		fmt.fprintf(os.stderr, "Scene file not found or unreadable: %s\n", path)
		return nil, nil, nil, false
	}
	defer delete(data)

	scene: SceneFile
	err := json.unmarshal(data, &scene)
	if err != nil {
		fmt.fprintf(os.stderr, "Scene parse error: %v\n", err)
		return nil, nil, nil, false
	}

	scene_dir := filepath.dir(path)
	defer delete(scene_dir)

	// Pre-load image textures when cache is provided so the world is built with ImageTextureRuntime.
	if image_cache != nil && scene.objects != nil {
		for &obj in scene.objects {
			s := &obj.material
			if s.material_type == "lambertian" && len(s.image_path) > 0 {
				resolved := _scene_resolve_image_path(scene_dir, s.image_path)
				defer delete(resolved)
				if resolved not_in image_cache {
					img := new(rt.Texture_Image)
					img^ = rt.texture_image_init()
					if rt.texture_image_load(img, resolved) {
						// Key must outlive this scope; map owns it until cache is cleared.
						image_cache[strings.clone(resolved)] = img
					} else {
						fmt.fprintf(os.stderr, "Scene image load failed: %s\n", resolved)
						rt.texture_image_destroy(img)
						free(img)
					}
				}
			}
		}
	}

	cam := rt.make_camera(image_width, image_height, samples_per_pixel)
	// Default camera pose if scene file has zero or missing camera (edge case)
	zero_vec := [3]f32{0, 0, 0}
	use_default_camera := scene.camera.lookfrom == zero_vec && scene.camera.lookat == zero_vec
	if use_default_camera {
		cam.lookfrom = [3]f32{13, 2, 3}
		cam.lookat = zero_vec
		cam.vup = [3]f32{0, 1, 0}
	} else {
		cam.lookfrom = scene.camera.lookfrom
		cam.lookat = scene.camera.lookat
		cam.vup = scene.camera.vup
	}
	if scene.camera.vfov > 0 {
		cam.vfov = scene.camera.vfov
	}
	if scene.camera.defocus_angle >= 0 {
		cam.defocus_angle = scene.camera.defocus_angle
	}
	if scene.camera.focus_dist > 0 {
		cam.focus_dist = scene.camera.focus_dist
	}
	if scene.camera.max_depth > 0 {
		cam.max_depth = scene.camera.max_depth
	}
	if scene.camera.shutter_close > scene.camera.shutter_open {
		cam.shutter_open = scene.camera.shutter_open
		cam.shutter_close = scene.camera.shutter_close
	}
	// background: preserve scene value unless it's black/missing AND the scene has no emissive materials.
	// In that no-light case, force white so imported scenes remain visible before users add lights.
	cam.background = scene.camera.background
	if _is_black_background(cam.background) && !_scene_has_emissive_material(scene.objects[:]) {
		cam.background = [3]f32{1, 1, 1}
	}
	rt.init_camera(cam)

	cap_val := 0
	if scene.objects != nil {
		cap_val = len(scene.objects)
	}
	if scene.volumes != nil {
		cap_val += len(scene.volumes)
	}
	world := make([dynamic]rt.Object, 0, cap_val)
	if scene.objects != nil {
		for &obj in scene.objects {
			mat := scene_material_to_material(&obj.material, scene_dir, image_cache)
			switch obj.object_type {
			case "sphere":
				center1 := obj.center1
				if !obj.is_moving {
					center1 = obj.center
				}
				has_rot := obj.rotation_deg[0] != 0 || obj.rotation_deg[1] != 0 || obj.rotation_deg[2] != 0
				has_scale := obj.scale_xyz != {0, 0, 0} && obj.scale_xyz != {1, 1, 1}
				if has_rot || has_scale {
					eff_scale := obj.scale_xyz
					if eff_scale == ([3]f32{0, 0, 0}) { eff_scale = {1, 1, 1} }
					inner_sphere := rt.Sphere{
						center    = {0, 0, 0},
						center1   = {0, 0, 0},
						radius    = obj.radius,
						material  = mat,
						is_moving = false,
					}
					inst := rt.make_transformed_object_trs(
						rt.TransformedPrimitive(inner_sphere),
						obj.center,
						obj.rotation_deg,
						eff_scale,
					)
					append(&world, rt.Object(inst))
				} else {
					append(&world, rt.Sphere{
						center    = obj.center,
						center1   = center1,
						radius    = obj.radius,
						material  = mat,
						is_moving = obj.is_moving,
					})
				}
			case "quad":
				append(&world, rt.Object(rt.make_quad(obj.q, obj.u, obj.v, mat)))
			case:
				fmt.fprintf(os.stderr, "Unknown object type: %s\n", obj.object_type)
			}
		}
		delete(scene.objects)
	}
	volumes_out := make([dynamic]core.SceneVolume)
	if scene.volumes != nil {
		for &v in scene.volumes {
			sv := core.SceneVolume{
				box_min      = v.box_min,
				box_max      = v.box_max,
				rotate_y_deg = v.rotate_y_deg,
				translate   = v.translate,
				density     = v.density != 0 ? v.density : 0.01,
				albedo      = v.albedo,
			}
			append(&volumes_out, sv)
			append(&world, rt.build_volume_from_scene_volume(sv))
		}
		delete(scene.volumes)
	}

	return cam, world, volumes_out, true
}

scene_material_to_material :: proc(s: ^SceneMaterial, scene_dir: string, image_cache: ^map[string]^rt.Texture_Image = nil) -> rt.material {
	switch s.material_type {
	case "lambertian":
		// texture_kind: missing or "constant" → constant (backward compat); "checker", "image", "noise", "marble".
		switch s.texture_kind {
		case "checker":
			scale := s.checker_scale != 0 ? s.checker_scale : 1.0
			return rt.material(rt.lambertian{albedo = rt.CheckerTexture{scale = scale, even = s.albedo, odd = s.checker_color_odd}})
		case "noise":
			scale := s.noise_scale != 0 ? s.noise_scale : 4.0
			return rt.material(rt.lambertian{albedo = rt.NoiseTexture{scale = scale}})
		case "marble":
			scale := s.noise_scale != 0 ? s.noise_scale : 4.0
			return rt.material(rt.lambertian{albedo = rt.MarbleTexture{scale = scale}})
		}
		// "image" or legacy: image_path non-empty → image if cache has it
		if len(s.image_path) > 0 && image_cache != nil {
			resolved := _scene_resolve_image_path(scene_dir, s.image_path)
			defer delete(resolved)
			if img := image_cache[resolved]; img != nil {
				// Path must match cache key for later convert_world_to_edit_spheres / build_world_from_scene lookups.
				return rt.material(rt.lambertian{albedo = rt.ImageTextureRuntime{path = strings.clone(resolved), image = img}})
			}
		}
		// constant (default) or image miss: solid colour
		return rt.material(rt.lambertian{albedo = rt.ConstantTexture{color = s.albedo}})
	case "metal":
		return rt.material(rt.metallic{albedo = s.albedo, fuzz = s.fuzz})
	case "dielectric":
		return rt.material(rt.dielectric{ref_idx = s.ref_idx})
	case "diffuse_light":
		return rt.material(rt.diffuse_light{emit = s.albedo})
	case:
		return rt.material(rt.lambertian{albedo = rt.ConstantTexture{color = {0.5, 0.5, 0.5}}})
	}
}

// save_scene writes the current camera (pose/view) and world to a JSON scene file.
// When volumes is non-nil, volume definitions are written so they can be reloaded (world alone cannot be round-tripped for volumes).
save_scene :: proc(path: string, r_camera: ^rt.Camera, r_world: [dynamic]rt.Object, volumes: []core.SceneVolume = nil) -> bool {
	if r_camera == nil {
		return false
	}

	scene := SceneFile{
		camera  = SceneCamera{
			lookfrom      = r_camera.lookfrom,
			lookat        = r_camera.lookat,
			vup           = r_camera.vup,
			vfov          = r_camera.vfov,
			defocus_angle = r_camera.defocus_angle,
			focus_dist    = r_camera.focus_dist,
			max_depth     = r_camera.max_depth,
			shutter_open  = r_camera.shutter_open,
			shutter_close = r_camera.shutter_close,
			background    = r_camera.background,
		},
		objects = make([dynamic]SceneObject),
		volumes = make([dynamic]SceneVolumeData),
	}
	defer delete(scene.objects)
	defer delete(scene.volumes)

	scene_dir := filepath.dir(path)
	defer delete(scene_dir)

	for obj in r_world {
		switch o in obj {
		case rt.Sphere:
			append(&scene.objects, SceneObject{
				object_type = "sphere",
				center      = o.center,
				center1     = o.center1,
				radius      = o.radius,
				material    = material_to_scene_material(o.material, scene_dir),
				is_moving   = o.is_moving,
			})
		case rt.Quad:
			append(&scene.objects, SceneObject{
				object_type = "quad",
				q           = o.Q,
				u           = o.u,
				v           = o.v,
				material    = material_to_scene_material(o.material, scene_dir),
			})
		case rt.ConstantMedium:
			// Volume geometry is not round-tripped from world; save from volumes slice when provided.
		case rt.TransformedObject:
			// Serialize as sphere with rotation/scale fields so the scene file round-trips.
			if s, is_sphere := o.inner.(rt.Sphere); is_sphere {
				append(&scene.objects, SceneObject{
					object_type  = "sphere",
					center       = o.translation,
					center1      = o.translation,
					radius       = s.radius,
					material     = material_to_scene_material(s.material, scene_dir),
					is_moving    = false,
					rotation_deg = o.rotation_deg,
					scale_xyz    = o.scale_xyz,
				})
			}
		case rt.ConstantMedium:
			// Volume geometry is not round-tripped from world; save from volumes slice when provided.
		}
	}
	if volumes != nil {
		for v in volumes {
			append(&scene.volumes, SceneVolumeData{
				box_min = v.box_min, box_max = v.box_max,
				rotate_y_deg = v.rotate_y_deg, translate = v.translate,
				density = v.density, albedo = v.albedo,
			})
		}
	}

	data, err := json.marshal(scene)
	if err != nil {
		fmt.fprintf(os.stderr, "Scene marshal error: %v\n", err)
		return false
	}
	defer delete(data)

	for &obj in scene.objects {
		if len(obj.material.image_path) > 0 {
			delete(obj.material.image_path)
		}
	}

	f, open_err := os.open(path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o644)
	if open_err != os.ERROR_NONE {
		fmt.fprintf(os.stderr, "Scene write error: %s\n", path)
		return false
	}
	defer os.close(f)
	_, _ = os.write(f, data)
	return true
}

// material_to_scene_material converts rt.material to JSON-friendly SceneMaterial.
// scene_dir is the directory of the scene file; image paths are stored relative to it (absolute paths → basename).
material_to_scene_material :: proc(m: rt.material, scene_dir: string) -> SceneMaterial {
	switch mat in m {
	case rt.lambertian:
		switch tex in mat.albedo {
		case rt.NoiseTexture:
			return SceneMaterial{material_type = "lambertian", texture_kind = "noise", noise_scale = tex.scale}
		case rt.MarbleTexture:
			return SceneMaterial{material_type = "lambertian", texture_kind = "marble", noise_scale = tex.scale}
		case rt.CheckerTexture:
			return SceneMaterial{
				material_type     = "lambertian",
				texture_kind      = "checker",
				albedo            = tex.even,
				checker_scale     = tex.scale,
				checker_color_odd = tex.odd,
			}
		case rt.ImageTextureRuntime:
			if len(tex.path) > 0 {
				// Store path relative to scene file; absolute or unrelated → basename.
				rel_path := tex.path
				if len(scene_dir) > 0 {
					if rel, rel_err := filepath.rel(scene_dir, tex.path); rel_err == nil {
						rel_path = rel
					} else {
						rel_path = filepath.base(tex.path)
					}
				}
				return SceneMaterial{
					material_type = "lambertian",
					texture_kind  = "image",
					albedo        = rt.texture_value_runtime(mat.albedo, 0, 0, {0, 0, 0}),
					image_path    = rel_path,
				}
			}
		case rt.ConstantTexture:
			return SceneMaterial{material_type = "lambertian", texture_kind = "constant", albedo = tex.color}
		}
		// fallback
		return SceneMaterial{material_type = "lambertian", texture_kind = "constant", albedo = rt.texture_value_runtime(mat.albedo, 0, 0, {0, 0, 0})}
	case rt.metallic:
		return SceneMaterial{material_type = "metal", albedo = mat.albedo, fuzz = mat.fuzz}
	case rt.dielectric:
		return SceneMaterial{material_type = "dielectric", ref_idx = mat.ref_idx}
	case rt.diffuse_light:
		return SceneMaterial{material_type = "diffuse_light", albedo = mat.emit}
	case rt.isotropic:
		return SceneMaterial{material_type = "isotropic", albedo = mat.albedo}
	case:
		return SceneMaterial{material_type = "lambertian", texture_kind = "constant", albedo = [3]f32{0.5, 0.5, 0.5}}
	}
}
