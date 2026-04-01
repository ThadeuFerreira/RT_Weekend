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
	case isotropic:
		ss.material_kind = .Isotropic
		ss.albedo = core.ConstantTexture{color = m.albedo}
	case:
		ss.material_kind = .Lambertian
		ss.albedo = core.ConstantTexture{color = {0.5, 0.5, 0.5}}
	}
	return ss
}

// scene_material_bucket holds the shared material fields used by SceneSphere and SceneQuad for rt.material conversion.
scene_material_bucket :: struct {
	material_kind:     core.MaterialKind,
	albedo:            core.Texture,
	texture_kind:      core.TextureKind,
	checker_scale:     f32,
	checker_color_odd: [3]f32,
	image_path:        string,
	fuzz:              f32,
	ref_idx:           f32,
}

sphere_to_bucket :: proc(s: core.SceneSphere) -> scene_material_bucket {
	return scene_material_bucket{
		material_kind     = s.material_kind,
		albedo            = s.albedo,
		texture_kind      = s.texture_kind,
		checker_scale     = s.checker_scale,
		checker_color_odd = s.checker_color_odd,
		image_path        = s.image_path,
		fuzz              = s.fuzz,
		ref_idx           = s.ref_idx,
	}
}

quad_to_bucket :: proc(q: core.SceneQuad) -> scene_material_bucket {
	return scene_material_bucket{
		material_kind     = q.material_kind,
		albedo            = q.albedo,
		texture_kind      = q.texture_kind,
		checker_scale     = q.checker_scale,
		checker_color_odd = q.checker_color_odd,
		image_path        = q.image_path,
		fuzz              = q.fuzz,
		ref_idx           = q.ref_idx,
	}
}

// material_from_scene_bucket builds rt.material from shared scene material fields (sphere or quad).
material_from_scene_bucket :: proc(b: scene_material_bucket, image_cache: ^map[string]^Texture_Image) -> material {
	MAGENTA_FALLBACK :: [3]f32{1, 0, 1}
	mat: material
	switch b.material_kind {
	case .Lambertian:
		albedo_rtex: RTexture
		switch b.texture_kind {
		case .Constant:
			switch a in b.albedo {
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
			switch a in b.albedo {
			case ConstantTexture:
				even = a.color
			case CheckerTexture:
				even = a.even
			case core.NoiseTexture, core.MarbleTexture, core.ImageTexture:
				{}
			case:
				{}
			}
			scale := b.checker_scale
			if scale <= 0 { scale = 1.0 }
			albedo_rtex = CheckerTexture{scale = scale, even = even, odd = b.checker_color_odd}
		case .Image:
			path := b.image_path
			if len(path) == 0 {
				if a, ok := b.albedo.(core.ImageTexture); ok { path = a.path }
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
			switch a in b.albedo {
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
		fuzz := b.fuzz
		if fuzz <= 0 { fuzz = 0.1 }
		metal_col := [3]f32{0.5, 0.5, 0.5}
		if ct, ok := b.albedo.(core.ConstantTexture); ok {
			metal_col = ct.color
		} else if ct2, ok := b.albedo.(core.CheckerTexture); ok {
			metal_col = ct2.even
		}
		mat = material(metallic{albedo = metal_col, fuzz = fuzz})
	case .Dielectric:
		ref_idx := b.ref_idx
		if ref_idx <= 0 { ref_idx = 1.5 }
		mat = material(dielectric{ref_idx = ref_idx})
	case .DiffuseLight:
		emit_col := [3]f32{1, 1, 1}
		if ct, ok := b.albedo.(core.ConstantTexture); ok {
			emit_col = ct.color
		} else if ct2, ok := b.albedo.(core.CheckerTexture); ok {
			emit_col = ct2.even
		}
		mat = material(diffuse_light{emit = emit_col})
	case .Isotropic:
		albedo_col := [3]f32{0.5, 0.5, 0.5}
		if ct, ok := b.albedo.(core.ConstantTexture); ok {
			albedo_col = ct.color
		} else if ct2, ok := b.albedo.(core.CheckerTexture); ok {
			albedo_col = ct2.even
		}
		mat = material(isotropic{albedo = albedo_col})
	case:
		albedo_fallback: RTexture = ConstantTexture{color = {0.5, 0.5, 0.5}}
		switch a in b.albedo {
		case ConstantTexture:
			albedo_fallback = a
		case CheckerTexture:
			albedo_fallback = a
		case core.NoiseTexture:
			albedo_fallback = NoiseTexture(a)
		case core.MarbleTexture:
			albedo_fallback = MarbleTexture(a)
		case core.ImageTexture:
			{}
		}
		mat = material(lambertian{albedo = albedo_fallback})
	}
	return mat
}

// scene_sphere_to_object converts one scene sphere to a raytrace Object (Sphere).
scene_sphere_to_object :: proc(s: core.SceneSphere, image_cache: ^map[string]^Texture_Image) -> Object {
	mat := material_from_scene_bucket(sphere_to_bucket(s), image_cache)
	return Object(Sphere{
		center    = s.center,
		center1   = s.center1,
		radius    = s.radius,
		material  = mat,
		is_moving = s.is_moving,
	})
}

// scene_quad_to_rt_quad builds rt.Quad from core.SceneQuad.
scene_quad_to_rt_quad :: proc(sq: core.SceneQuad, image_cache: ^map[string]^Texture_Image) -> Quad {
	mat := material_from_scene_bucket(quad_to_bucket(sq), image_cache)
	q := make_quad(sq.Q, sq.u, sq.v, mat)
	return q
}

// rt_quad_to_scene_quad extracts core.SceneQuad from rt.Quad (material mapping mirrors sphere_to_scene_sphere).
rt_quad_to_scene_quad :: proc(q: Quad) -> core.SceneQuad {
	sq := core.SceneQuad{Q = q.Q, u = q.u, v = q.v}
	switch m in q.material {
	case lambertian:
		sq.material_kind = .Lambertian
		switch a in m.albedo {
		case ConstantTexture:
			sq.texture_kind = .Constant
			sq.albedo = core.Texture(a)
		case CheckerTexture:
			sq.texture_kind = .Checker
			sq.checker_scale = a.scale
			sq.checker_color_odd = a.odd
			sq.albedo = core.Texture(a)
		case ImageTextureRuntime:
			sq.texture_kind = .Image
			sq.image_path = a.path
			sq.albedo = core.ImageTexture{path = a.path}
		case NoiseTexture:
			sq.texture_kind = .Constant
			sq.albedo = core.Texture(core.NoiseTexture(a))
		case MarbleTexture:
			sq.texture_kind = .Constant
			sq.albedo = core.Texture(core.MarbleTexture(a))
		}
	case metallic:
		sq.material_kind = .Metallic
		sq.albedo = ConstantTexture{color = m.albedo}
		sq.fuzz = m.fuzz
	case dielectric:
		sq.material_kind = .Dielectric
		sq.ref_idx = m.ref_idx
	case diffuse_light:
		sq.material_kind = .DiffuseLight
		sq.albedo = core.ConstantTexture{color = m.emit}
	case isotropic:
		sq.material_kind = .Isotropic
		sq.albedo = core.ConstantTexture{color = m.albedo}
	case:
		sq.material_kind = .Lambertian
		sq.albedo = core.ConstantTexture{color = {0.5, 0.5, 0.5}}
	}
	return sq
}

// scene_entity_to_rt_object dispatches SceneEntity to rt.Object (sphere, quad, or volume).
scene_entity_to_rt_object :: proc(e: core.SceneEntity, image_cache: ^map[string]^Texture_Image) -> Object {
	switch x in e {
	case core.SceneSphere:
		return scene_sphere_to_object(x, image_cache)
	case core.SceneQuad:
		return Object(scene_quad_to_rt_quad(x, image_cache))
	case core.SceneVolume:
		return build_volume_from_scene_volume(x)
	}
	unreachable()
}

// build_world_from_scene_entities builds Objects from a unified entity list (ground optional).
build_world_from_scene_entities :: proc(
	entities: []core.SceneEntity,
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
	for e in entities {
		append(&world, scene_entity_to_rt_object(e, image_cache))
	}
	return world
}

// collect_image_texture_cache extracts runtime image textures from a world so callers
// can rebuild SceneSphere->Object without losing ImageTextureRuntime pointers.
// Returned map should be deleted by the caller (it does not own Texture_Image pointers).
collect_image_texture_cache :: proc(world: []Object) -> map[string]^Texture_Image {
	cache := make(map[string]^Texture_Image)
	for obj in world {
		if s, is_sphere := obj.(Sphere); is_sphere {
			m, is_lambertian := s.material.(lambertian)
			if is_lambertian {
				if img_tex, has_image := m.albedo.(ImageTextureRuntime); has_image {
					if len(img_tex.path) > 0 && img_tex.image != nil {
						cache[img_tex.path] = img_tex.image
					}
				}
			}
		} else if q, is_quad := obj.(Quad); is_quad {
			m, is_lambertian := q.material.(lambertian)
			if is_lambertian {
				if img_tex, has_image := m.albedo.(ImageTextureRuntime); has_image {
					if len(img_tex.path) > 0 && img_tex.image != nil {
						cache[img_tex.path] = img_tex.image
					}
				}
			}
		}
	}
	if len(cache) == 0 {
		delete(cache)
		return nil
	}
	return cache
}
