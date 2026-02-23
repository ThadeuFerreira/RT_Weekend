package raytrace

import "core:encoding/json"
import "core:fmt"
import "core:os"

// Intermediate types for JSON (avoid union unmarshaling).

SceneCamera :: struct {
	lookfrom:      [3]f32 `json:"lookfrom"`,
	lookat:        [3]f32 `json:"lookat"`,
	vup:           [3]f32 `json:"vup"`,
	vfov:          f32   `json:"vfov,omitempty"`,
	defocus_angle: f32   `json:"defocus_angle,omitempty"`,
	focus_dist:    f32   `json:"focus_dist,omitempty"`,
	max_depth:     int   `json:"max_depth,omitempty"`,
}

SceneMaterial :: struct {
	material_type: string  `json:"type"`,
	albedo:        [3]f32  `json:"albedo,omitempty"`,
	fuzz:          f32    `json:"fuzz,omitempty"`,
	ref_idx:       f32    `json:"ref_idx,omitempty"`,
}

SceneObject :: struct {
	object_type: string        `json:"type"`,
	center:      [3]f32        `json:"center"`,
	radius:      f32           `json:"radius"`,
	material:    SceneMaterial `json:"material"`,
}

SceneFile :: struct {
	camera:  SceneCamera        `json:"camera"`,
	objects: [dynamic]SceneObject `json:"objects"`,
}

// load_scene loads camera and objects from a JSON scene file. Resolution/samples come from arguments.
// Returns (camera, world, true) on success; (nil, nil, false) on error.
load_scene :: proc(
	path: string,
	image_width: int,
	image_height: int,
	samples_per_pixel: int,
) -> (^Camera, [dynamic]Object, bool) {
	data, read_ok := os.read_entire_file(path)
	if !read_ok {
		fmt.fprintf(os.stderr, "Scene file not found or unreadable: %s\n", path)
		return nil, nil, false
	}
	defer delete(data)

	scene: SceneFile
	err := json.unmarshal(data, &scene)
	if err != nil {
		fmt.fprintf(os.stderr, "Scene parse error: %v\n", err)
		return nil, nil, false
	}

	cam := make_camera(image_width, image_height, samples_per_pixel)
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
	init_camera(cam)

	cap_val := 0
	if scene.objects != nil {
		cap_val = len(scene.objects)
	}
	world := make([dynamic]Object, 0, cap_val)
	if scene.objects != nil {
		for &obj in scene.objects {
			mat := scene_material_to_material(&obj.material)
			switch obj.object_type {
			case "sphere":
				append(&world, Sphere{center = obj.center, radius = obj.radius, material = mat})
			case "cube":
				append(&world, Cube{center = obj.center, radius = obj.radius, material = mat})
			case:
				fmt.fprintf(os.stderr, "Unknown object type: %s\n", obj.object_type)
			}
		}
		delete(scene.objects)
	} // free array allocated by json.unmarshal

	return cam, world, true
}

scene_material_to_material :: proc(s: ^SceneMaterial) -> material {
	switch s.material_type {
	case "lambertian":
		return material(lambertian{albedo = s.albedo})
	case "metal":
		return material(metalic{albedo = s.albedo, fuzz = s.fuzz})
	case "dielectric", "dieletric":
		return material(dieletric{ref_idx = s.ref_idx})
	case:
		return material(lambertian{albedo = [3]f32{0.5, 0.5, 0.5}})
	}
}

// save_scene writes the current camera (pose/view) and world to a JSON scene file.
save_scene :: proc(path: string, camera: ^Camera, world: [dynamic]Object) -> bool {
	if camera == nil {
		return false
	}

	scene := SceneFile{
		camera = SceneCamera{
			lookfrom      = camera.lookfrom,
			lookat        = camera.lookat,
			vup           = camera.vup,
			vfov          = camera.vfov,
			defocus_angle = camera.defocus_angle,
			focus_dist    = camera.focus_dist,
			max_depth     = camera.max_depth,
		},
		objects = make([dynamic]SceneObject),
	}
	defer delete(scene.objects)

	for obj in world {
		switch o in obj {
		case Sphere:
			append(&scene.objects, SceneObject{
				object_type = "sphere",
				center      = o.center,
				radius      = o.radius,
				material    = material_to_scene_material(o.material),
			})
		case Cube:
			append(&scene.objects, SceneObject{
				object_type = "cube",
				center      = o.center,
				radius      = o.radius,
				material    = material_to_scene_material(o.material),
			})
		}
	}

	data, err := json.marshal(scene)
	if err != nil {
		fmt.fprintf(os.stderr, "Scene marshal error: %v\n", err)
		return false
	}
	defer delete(data)

	f, open_err := os.open(path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o644)
	if open_err != os.ERROR_NONE {
		fmt.fprintf(os.stderr, "Scene write error: %s\n", path)
		return false
	}
	defer os.close(f)
	_, _ = os.write(f, data)
	return true
}

material_to_scene_material :: proc(m: material) -> SceneMaterial {
	switch mat in m {
	case lambertian:
		return SceneMaterial{material_type = "lambertian", albedo = mat.albedo}
	case metalic:
		return SceneMaterial{material_type = "metal", albedo = mat.albedo, fuzz = mat.fuzz}
	case dieletric:
		return SceneMaterial{material_type = "dielectric", ref_idx = mat.ref_idx}
	case:
		return SceneMaterial{material_type = "lambertian", albedo = [3]f32{0.5, 0.5, 0.5}}
	}
}
