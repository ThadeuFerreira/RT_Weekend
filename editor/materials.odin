package editor

import "RT_Weekend:core"

// For now we keep a small mapping to the existing MaterialKind enum.
material_name :: proc(k: core.Core_MaterialKind) -> cstring {
	switch k {
	case .Lambertian: return "Lambertian"
	case .Metallic:   return "Metallic"
	case .Dielectric: return "Dielectric"
	}
	return "Unknown"
}
