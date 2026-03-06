package raytrace

import "core:math"
import "RT_Weekend:core"

ConstantTexture :: core.ConstantTexture
CheckerTexture :: core.CheckerTexture
Texture :: core.Texture



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
	}
	return [3]f32{0, 0, 0}
}
