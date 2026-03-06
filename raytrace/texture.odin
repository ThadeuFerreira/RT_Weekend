package raytrace

import "core:math"

ConstantTexture :: struct {
	color: [3]f32,
}

CheckerTexture :: struct {
	scale: f32,
	even:  [3]f32,
	odd:   [3]f32,
}

Texture :: union {
	ConstantTexture,
	CheckerTexture,
}

texture_value :: proc(tex: Texture, u, v: f32, p: [3]f32) -> [3]f32 {
	switch t in tex {
	case ConstantTexture:
		return t.color
	case CheckerTexture:
		inv_scale := 1.0 / t.scale
		xi := int(math.floor(inv_scale * p[0]))
		yi := int(math.floor(inv_scale * p[1]))
		zi := int(math.floor(inv_scale * p[2]))
		sum := xi + yi + zi
		is_even := (sum % 2 + 2) % 2 == 0
		return is_even ? t.even : t.odd
	}
	return [3]f32{0, 0, 0}
}
