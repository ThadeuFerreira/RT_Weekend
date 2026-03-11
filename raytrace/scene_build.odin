package raytrace

import "core:fmt"
import "core:strings"
import "RT_Weekend:core"
when !VERBOSE_OUTPUT {
	@(private)
	_use_verbose_imports_scene_build :: proc() {
		_ = fmt.printf
	}
}

// sphere_to_scene_sphere converts a single Sphere to core.SceneSphere (material, albedo, etc.).
// Used by LoadFromWorld to preserve world order when rebuilding the editor object list.
// Sets texture_kind, checker_scale, checker_color_odd, image_path for Lambertian persistence.
sphere_to_scene_sphere :: proc(s: Sphere) -> core.SceneSphere {
	ss := core.SceneSphere{center = s.center, center1 = s.center1, radius = s.radius, is_moving = s.is_moving}
	switch m in s.material {
	case lambertian:
		ss.material_kind = .Lambertian
		switch a in m.albedo {
		case ConstantTexture:
			ss.texture_kind = .Constant
			ss.albedo = core.Texture(a)
		case CheckerTexture:
			ss.texture_kind = .Checker
			ss.checker_scale = a.scale
			ss.checker_color_odd = a.odd
			ss.albedo = core.Texture(a)
		case ImageTextureRuntime:
			ss.texture_kind = .Image
			ss.image_path = a.path
			ss.albedo = core.ImageTexture{path = a.path}
		case NoiseTexture:
			ss.texture_kind = .Constant
			ss.albedo = core.Texture(core.NoiseTexture(a))
		case MarbleTexture:
			ss.texture_kind = .Constant
			ss.albedo = core.Texture(core.MarbleTexture(a))
		}
	case metallic:
		ss.material_kind = .Metallic
		ss.albedo = ConstantTexture{color = m.albedo}
		ss.fuzz = m.fuzz
	case dielectric:
		ss.material_kind = .Dielectric
		ss.ref_idx = m.ref_idx
	case diffuse_light:
		ss.material_kind = .DiffuseLight
		ss.albedo = core.ConstantTexture{color = m.emit}
	case:
		ss.material_kind = .Lambertian
		ss.albedo = core.ConstantTexture{color = {0.5, 0.5, 0.5}}
	}
	return ss
}

// convert_world_to_edit_spheres converts rt.Object spheres to core.SceneSphere for the edit view.
// Skips the ground plane (core.is_ground_heuristic) and Quad objects (quads are not editable as spheres).
// Caller must delete the returned array.
convert_world_to_edit_spheres :: proc(world: []Object) -> [dynamic]core.SceneSphere {
	result := make([dynamic]core.SceneSphere)
	for obj in world {
		s, ok := obj.(Sphere)
		if !ok { continue }
		if core.is_ground_heuristic(s.center[1], s.radius) {
			continue
		}
		ss := sphere_to_scene_sphere(s)
		append(&result, ss)
	}
	return result
}

// build_world_from_scene converts shared scene spheres to raytrace Objects.
// When include_ground is true, prepends a ground plane using the given ground_texture (value).
// Caller passes default grey (e.g. ConstantTexture{0.5,0.5,0.5}) when no custom ground is desired.
// image_cache: when non-nil, Lambertian .Image textures are looked up here; on miss we try to load and insert. If nil or load fails, use magenta fallback.
// Caller owns and must delete the returned dynamic array.
build_world_from_scene :: proc(
	scene_objects: []core.SceneSphere,
	ground_texture: Texture,
	image_cache: ^map[string]^Texture_Image = nil,
	include_ground: bool = true,
) -> [dynamic]Object {
	world := make([dynamic]Object)

	if include_ground {
		ground_rtex: RTexture
		switch g in ground_texture {
		case ConstantTexture:
			ground_rtex = g
		case CheckerTexture:
			ground_rtex = g
		case core.NoiseTexture:
			ground_rtex = NoiseTexture(g)
		case core.MarbleTexture:
			ground_rtex = MarbleTexture(g)
		case core.ImageTexture:
			when VERBOSE_OUTPUT {
				fmt.printf("[SceneBuild] Ground uses core.ImageTexture path=%q; runtime ground image unsupported here, using gray fallback\n", g.path)
			}
			ground_rtex = ConstantTexture{color = {0.5, 0.5, 0.5}}
		}
		append(&world, Object(Sphere{
			center   = {0, -1000, 0},
			radius   = 1000,
			material = lambertian{albedo = ground_rtex},
		}))
	}

	MAGENTA_FALLBACK :: [3]f32{1, 0, 1}

	for s in scene_objects {
		mat: material
		switch s.material_kind {
		case .Lambertian:
			albedo_rtex: RTexture
			// Prefer texture_kind for scene-driven conversion; fall back to albedo union for legacy/Noise/Marble.
			switch s.texture_kind {
			case .Constant:
				switch a in s.albedo {
				case ConstantTexture:
					albedo_rtex = a
				case CheckerTexture:
					albedo_rtex = ConstantTexture{color = a.even}
				case core.NoiseTexture:
					albedo_rtex = NoiseTexture(a)
				case core.MarbleTexture:
					albedo_rtex = MarbleTexture(a)
				case core.ImageTexture:
					albedo_rtex = ConstantTexture{color = {0.5, 0.5, 0.5}}
				case:
					albedo_rtex = ConstantTexture{color = {0.5, 0.5, 0.5}}
				}
			case .Checker:
				even := [3]f32{0.5, 0.5, 0.5}
				switch a in s.albedo {
				case ConstantTexture:     even = a.color
				case CheckerTexture:      even = a.even
				case core.NoiseTexture:   {}
				case core.MarbleTexture:  {}
				case core.ImageTexture:   {}
				case:                     {}
				}
				scale := s.checker_scale
				if scale <= 0 { scale = 1.0 }
				albedo_rtex = CheckerTexture{scale = scale, even = even, odd = s.checker_color_odd}
			case .Image:
				path := s.image_path
				if len(path) == 0 {
					if a, ok := s.albedo.(core.ImageTexture); ok { path = a.path }
				}
				if image_cache != nil && len(path) > 0 {
					if img := image_cache[path]; img != nil {
						when VERBOSE_OUTPUT {
							fmt.printf("[SceneBuild] Image texture cache hit path=%q (%dx%d)\n",
								path, texture_image_width(img), texture_image_height(img))
						}
						albedo_rtex = ImageTextureRuntime{path = path, image = img}
					} else {
						img := new(Texture_Image)
						img^ = texture_image_init()
						if texture_image_load(img, path) {
							image_cache[strings.clone(path)] = img
							albedo_rtex = ImageTextureRuntime{path = path, image = img}
						} else {
							when VERBOSE_OUTPUT {
								fmt.printf("[SceneBuild] Image texture load failed path=%q; using magenta fallback\n", path)
							}
							texture_image_destroy(img)
							free(img)
							albedo_rtex = ConstantTexture{color = MAGENTA_FALLBACK}
						}
					}
				} else {
					when VERBOSE_OUTPUT {
						if image_cache == nil {
							fmt.printf("[SceneBuild] Image texture nil cache path=%q; using magenta fallback\n", path)
						}
					}
					albedo_rtex = ConstantTexture{color = MAGENTA_FALLBACK}
				}
			case:
				// Legacy: derive from albedo union
				switch a in s.albedo {
				case ConstantTexture:
					albedo_rtex = a
				case CheckerTexture:
					albedo_rtex = a
				case core.NoiseTexture:
					albedo_rtex = NoiseTexture(a)
				case core.MarbleTexture:
					albedo_rtex = MarbleTexture(a)
				case core.ImageTexture:
					path := a.path
					if image_cache != nil && len(path) > 0 {
						if img := image_cache[path]; img != nil {
							albedo_rtex = ImageTextureRuntime{path = path, image = img}
						} else {
							img := new(Texture_Image)
							img^ = texture_image_init()
							if texture_image_load(img, path) {
								image_cache[strings.clone(path)] = img
								albedo_rtex = ImageTextureRuntime{path = path, image = img}
							} else {
								texture_image_destroy(img)
								free(img)
								albedo_rtex = ConstantTexture{color = MAGENTA_FALLBACK}
							}
						}
					} else {
						albedo_rtex = ConstantTexture{color = MAGENTA_FALLBACK}
					}
				case:
					albedo_rtex = ConstantTexture{color = {0.5, 0.5, 0.5}}
				}
			}
			mat = material(lambertian{albedo = albedo_rtex})
		case .Metallic:
			fuzz := s.fuzz
			if fuzz <= 0 { fuzz = 0.1 }
			
			// Editor metallic fallback to basic array extraction
			metal_col := [3]f32{0.5, 0.5, 0.5}
			if ct, ok := s.albedo.(core.ConstantTexture); ok {
				metal_col = ct.color
			} else if ct2, ok := s.albedo.(core.CheckerTexture); ok {
				metal_col = ct2.even
			}
			mat = material(metallic{albedo = metal_col, fuzz = fuzz})
		case .Dielectric:
			ref_idx := s.ref_idx
			if ref_idx <= 0 { ref_idx = 1.5 }
			mat = material(dielectric{ref_idx = ref_idx})
		case .DiffuseLight:
			emit_col := [3]f32{1, 1, 1}
			if ct, ok := s.albedo.(core.ConstantTexture); ok {
				emit_col = ct.color
			} else if ct2, ok := s.albedo.(core.CheckerTexture); ok {
				emit_col = ct2.even
			}
			mat = material(diffuse_light{emit = emit_col})
		case:
			albedo_fallback: RTexture = ConstantTexture{color = {0.5, 0.5, 0.5}}
			switch a in s.albedo {
			case ConstantTexture:    albedo_fallback = a
			case CheckerTexture:     albedo_fallback = a
			case core.NoiseTexture:  albedo_fallback = NoiseTexture(a)
			case core.MarbleTexture: albedo_fallback = MarbleTexture(a)
			case core.ImageTexture:  {}
			}
			mat = material(lambertian{albedo = albedo_fallback})
		}
		append(&world, Object(Sphere{
			center    = s.center,
			center1   = s.center1,
			radius    = s.radius,
			material  = mat,
			is_moving = s.is_moving,
		}))
	}

	return world
}

// collect_image_texture_cache extracts runtime image textures from a world so callers
// can rebuild SceneSphere->Object without losing ImageTextureRuntime pointers.
// Returned map should be deleted by the caller (it does not own Texture_Image pointers).
collect_image_texture_cache :: proc(world: []Object) -> map[string]^Texture_Image {
	cache := make(map[string]^Texture_Image)
	for obj in world {
		s, is_sphere := obj.(Sphere)
		if !is_sphere { continue }
		m, is_lambertian := s.material.(lambertian)
		if !is_lambertian { continue }
		if img_tex, has_image := m.albedo.(ImageTextureRuntime); has_image {
			if len(img_tex.path) > 0 && img_tex.image != nil {
				cache[img_tex.path] = img_tex.image
			}
		}
	}
	if len(cache) == 0 {
		delete(cache)
		return nil
	}
	return cache
}
