package raytrace

import "core:math"
import "RT_Weekend:core"

ConstantTexture :: core.ConstantTexture
CheckerTexture :: core.CheckerTexture
ImageTexture :: core.ImageTexture
Texture :: core.Texture

// RTexture is the runtime texture used by Lambertian: constant, checker, or image.
// ImageTextureRuntime holds path (for round-trip with core) and loaded pixel data.
ImageTextureRuntime :: struct {
	path:  string,
	image: ^Texture_Image,
}

RTexture :: union {
	ConstantTexture,
	CheckerTexture,
	ImageTextureRuntime,
}

texture_value :: proc(tex: Texture, u, v: f32, p: [3]f32) -> [3]f32 {
	switch t in tex {
	case ConstantTexture:
		return t.color
	case CheckerTexture:
		safe_scale := math.abs(t.scale) > 1e-8 ? t.scale : 1.0
		inv_scale := 1.0 / safe_scale
		xi := int(math.floor(inv_scale * p[0]))
		yi := int(math.floor(inv_scale * p[1]))
		zi := int(math.floor(inv_scale * p[2]))
		sum := xi + yi + zi
		is_even := (sum % 2 + 2) % 2 == 0
		return is_even ? t.even : t.odd
	case ImageTexture:
		// Core Texture has no pixel data; use texture_value_runtime with RTexture at render time.
		return [3]f32{0.5, 0.5, 0.5}
	}
	return [3]f32{0, 0, 0}
}

// texture_value_runtime samples RTexture (used by Lambertian). For image textures,
// u,v in [0,1] map to pixel (x,y); image origin top-left, v=0 top.
texture_value_runtime :: proc(tex: RTexture, u, v: f32, p: [3]f32) -> [3]f32 {
	switch t in tex {
	case ConstantTexture:
		return t.color
	case CheckerTexture:
		safe_scale := math.abs(t.scale) > 1e-8 ? t.scale : 1.0
		inv_scale := 1.0 / safe_scale
		xi := int(math.floor(inv_scale * p[0]))
		yi := int(math.floor(inv_scale * p[1]))
		zi := int(math.floor(inv_scale * p[2]))
		sum := xi + yi + zi
		is_even := (sum % 2 + 2) % 2 == 0
		return is_even ? t.even : t.odd
	case ImageTextureRuntime:
		if t.image == nil do return [3]f32{0.5, 0.5, 0.5}
		w := texture_image_width(t.image)
		h := texture_image_height(t.image)
		if w <= 0 || h <= 0 do return [3]f32{0.5, 0.5, 0.5}
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
		if ptr == nil do return [3]f32{0.5, 0.5, 0.5}
		// LDR bytes -> linear [0,1] (simple scale; pipeline gamma-corrects at output).
		p := ([^]u8)(ptr)
		return [3]f32{f32(p[0]) / 255.0, f32(p[1]) / 255.0, f32(p[2]) / 255.0}
	}
	return [3]f32{0, 0, 0}
}
