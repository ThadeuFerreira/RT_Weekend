package raytrace

import "core:fmt"
import "core:math"
import "core:sync"
import "RT_Weekend:core"
when !VERBOSE_OUTPUT {
	@(private)
	_use_verbose_imports_texture :: proc() {
		_, _ = fmt.printf, sync.atomic_add
	}
}

IMAGE_TEXTURE_DEBUG_SAMPLES :: 16

ConstantTexture :: core.ConstantTexture
CheckerTexture :: core.CheckerTexture
ImageTexture :: core.ImageTexture
NoiseTexture :: core.NoiseTexture
MarbleTexture :: core.MarbleTexture
Texture :: core.Texture

// RTexture is the runtime texture used by Lambertian: constant, checker, image, or procedural noise.
// ImageTextureRuntime holds path (for round-trip with core) and loaded pixel data.
ImageTextureRuntime :: struct {
	path:  string,
	image: ^Texture_Image,
}

RTexture :: union {
	ConstantTexture,
	CheckerTexture,
	ImageTextureRuntime,
	NoiseTexture,
	MarbleTexture,
}

@(private)
image_texture_debug_sample_count: i32

// image_texture_debug_reset clears the per-render sample counter so each render logs up to IMAGE_TEXTURE_DEBUG_SAMPLES. Call at start of each render.
image_texture_debug_reset :: proc() {
	when VERBOSE_OUTPUT {
		image_texture_debug_sample_count = 0
	}
}

// Shared texture sampling helpers — used by both texture_value and texture_value_runtime.

@(private)
_sample_constant :: proc(t: ConstantTexture) -> [3]f32 {
	return t.color
}

@(private)
_sample_checker :: proc(t: CheckerTexture, p: [3]f32) -> [3]f32 {
	safe_scale := math.abs(t.scale) > 1e-8 ? t.scale : 1.0
	inv_scale := 1.0 / safe_scale
	xi := int(math.floor(inv_scale * p[0]))
	yi := int(math.floor(inv_scale * p[1]))
	zi := int(math.floor(inv_scale * p[2]))
	sum := xi + yi + zi
	is_even := (sum % 2 + 2) % 2 == 0
	return is_even ? t.even : t.odd
}

@(private)
_sample_noise :: proc(t: NoiseTexture, p: [3]f32) -> [3]f32 {
	safe_scale := math.abs(t.scale) > 1e-6 ? t.scale : 1.0
	n := perlin_fbm({safe_scale * p[0], safe_scale * p[1], safe_scale * p[2]})
	val := math.clamp(0.5 * (1.0 + n), 0.0, 1.0)
	return {val, val, val}
}

@(private)
_sample_marble :: proc(t: MarbleTexture, p: [3]f32) -> [3]f32 {
	safe_scale := math.abs(t.scale) > 1e-6 ? t.scale : 1.0
	turb := perlin_turbulence(p)
	val := math.clamp(0.5 * (1.0 + math.sin(safe_scale * p[2] + 10.0 * turb)), 0.0, 1.0)
	return {val, val, val}
}

texture_value :: proc(tex: Texture, u, v: f32, p: [3]f32) -> [3]f32 {
	switch t in tex {
	case ConstantTexture:
		return _sample_constant(t)
	case CheckerTexture:
		return _sample_checker(t, p)
	case ImageTexture:
		// Core Texture has no pixel data; use texture_value_runtime with RTexture at render time.
		return [3]f32{0.5, 0.5, 0.5}
	case NoiseTexture:
		return _sample_noise(t, p)
	case MarbleTexture:
		return _sample_marble(t, p)
	}
	return [3]f32{0, 0, 0}
}

// texture_value_runtime samples RTexture (used by Lambertian). For image textures,
// u,v in [0,1] map to pixel (x,y); image origin top-left, v=0 top.
texture_value_runtime :: proc(tex: RTexture, u, v: f32, p: [3]f32) -> [3]f32 {
	switch t in tex {
	case ConstantTexture:
		return _sample_constant(t)
	case CheckerTexture:
		return _sample_checker(t, p)
	case NoiseTexture:
		return _sample_noise(t, p)
	case MarbleTexture:
		return _sample_marble(t, p)
	case ImageTextureRuntime:
		if t.image == nil {
			when VERBOSE_OUTPUT {
				fmt.printf("[Texture] ImageTextureRuntime has nil image path=%q; returning gray fallback\n", t.path)
			}
			return [3]f32{0.5, 0.5, 0.5}
		}
		w := texture_image_width(t.image)
		h := texture_image_height(t.image)
		if w <= 0 || h <= 0 {
			when VERBOSE_OUTPUT {
				fmt.printf("[Texture] Invalid image dimensions path=%q size=%dx%d; returning gray fallback\n", t.path, w, h)
			}
			return [3]f32{0.5, 0.5, 0.5}
		}
		// Sphere UV: u = longitude [0,1], v = 0 at south pole, v = 1 at north pole (sphere_get_uv).
		// Equirectangular image: row 0 = north, row h-1 = south → flip v so sphere north maps to image top.
		ux := math.clamp(u, 0, 1)
		vx := math.clamp(v, 0, 1)
		px := int(ux * f32(w))
		if px >= w do px = w - 1
		py := int((1.0 - vx) * f32(h))
		if py >= h do py = h - 1
		if py < 0 do py = 0
		ptr := texture_image_pixel_data(t.image, px, py)
		if ptr == nil {
			when VERBOSE_OUTPUT {
				fmt.printf("[Texture] Nil pixel pointer path=%q uv=(%.4f, %.4f) px=(%d,%d); returning gray fallback\n", t.path, ux, vx, px, py)
			}
			return [3]f32{0.5, 0.5, 0.5}
		}
		// LDR bytes -> linear [0,1] (simple scale; pipeline gamma-corrects at output).
		pix := ([^]u8)(ptr)
		color := [3]f32{f32(pix[0]) / 255.0, f32(pix[1]) / 255.0, f32(pix[2]) / 255.0}
		when VERBOSE_OUTPUT {
			debug_idx := sync.atomic_add(&image_texture_debug_sample_count, 1)
			if debug_idx < IMAGE_TEXTURE_DEBUG_SAMPLES {
				fmt.printf("[Texture] Sample #%d path=%q uv=(%.4f, %.4f) px=(%d,%d)/(%d,%d) rgb=(%d,%d,%d)\n",
					debug_idx + 1, t.path, ux, vx, px, py, w, h, pix[0], pix[1], pix[2])
			}
		}
		return color
	}
	return [3]f32{0, 0, 0}
}
