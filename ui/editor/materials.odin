package editor

import "RT_Weekend:scene"

// For now we keep a small mapping to the existing MaterialKind enum.
material_name :: proc(k: scene.MaterialKind) -> cstring {
	switch k {
	case .Lambertian: return "Lambertian"
	case .Metallic:   return "Metallic"
	case .Dielectric: return "Dielectric"
	}
	return "Unknown"
}

