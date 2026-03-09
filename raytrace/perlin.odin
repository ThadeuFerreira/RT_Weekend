package raytrace

import "core:math"

// Perlin noise implementation matching the stb_perlin / Ken Perlin algorithm.
// Uses the classic 256-entry permutation table and 12 gradient directions,
// providing consistent results across the CPU renderer.
//
// Two noise functions are exposed:
//   perlin_fbm(p, lacunarity, gain, octaves) — fractional Brownian motion (like GenImagePerlinNoise)
//   perlin_turbulence(p, depth)              — multi-octave |noise| sum (for marble)

// Classic Ken Perlin permutation table (256 entries, doubled to 512 for easy indexing).
@(private)
_perm: [512]u8 = {
	151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,
	140,36,103,30,69,142,8,99,37,240,21,10,23,190,6,148,
	247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,
	57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,
	74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,
	60,211,133,230,220,105,92,41,55,46,245,40,244,102,143,54,
	65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,
	200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,
	52,217,226,250,124,123,5,202,38,147,118,126,255,82,85,212,
	207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,
	119,248,152,2,44,154,163,70,221,153,101,155,167,43,172,9,
	129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,
	218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,241,
	81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,157,
	184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,
	222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180,
	// duplicated second half for wrap-free indexing
	151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,
	140,36,103,30,69,142,8,99,37,240,21,10,23,190,6,148,
	247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,
	57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,
	74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,
	60,211,133,230,220,105,92,41,55,46,245,40,244,102,143,54,
	65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,
	200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,
	52,217,226,250,124,123,5,202,38,147,118,126,255,82,85,212,
	207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,
	119,248,152,2,44,154,163,70,221,153,101,155,167,43,172,9,
	129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,
	218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,241,
	81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,157,
	184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,
	222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180,
}

// _perlin_fade is the quintic smoothstep (C2 continuity): 6t^5 - 15t^4 + 10t^3.
@(private)
_perlin_fade :: #force_inline proc(t: f32) -> f32 {
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

// _perlin_grad maps a hash value to one of 12 gradient directions (cube edges).
@(private)
_perlin_grad :: #force_inline proc(h: u8, x, y, z: f32) -> f32 {
	hh := h & 15
	u := hh < 8 ? x : y
	v := hh < 4 ? y : (hh == 12 || hh == 14) ? x : z
	su := (hh & 1) != 0 ? -u : u
	sv := (hh & 2) != 0 ? -v : v
	return su + sv
}

// perlin_noise returns a single-octave gradient Perlin noise value in approximately [-1, 1].
// The input point is evaluated in continuous 3D space; the function tiles every 256 units.
perlin_noise :: proc(p: [3]f32) -> f32 {
	// Integer cell coordinates (masked to [0,255])
	ix := int(math.floor(p[0])) & 255
	iy := int(math.floor(p[1])) & 255
	iz := int(math.floor(p[2])) & 255
	// Fractional part
	fx := p[0] - math.floor(p[0])
	fy := p[1] - math.floor(p[1])
	fz := p[2] - math.floor(p[2])
	// Smooth interpolation weights
	u := _perlin_fade(fx)
	v := _perlin_fade(fy)
	w := _perlin_fade(fz)
	// Hash the 8 corners
	A  := int(_perm[ix    ]) + iy
	AA := int(_perm[A     ]) + iz;  AB := int(_perm[A + 1]) + iz
	B  := int(_perm[ix + 1]) + iy
	BA := int(_perm[B     ]) + iz;  BB := int(_perm[B + 1]) + iz
	// Trilinear interpolation of gradient dot products
	x0 := math.lerp(_perlin_grad(_perm[AA    ], fx,   fy,   fz  ),
	                _perlin_grad(_perm[BA    ], fx-1, fy,   fz  ), u)
	x1 := math.lerp(_perlin_grad(_perm[AB    ], fx,   fy-1, fz  ),
	                _perlin_grad(_perm[BB    ], fx-1, fy-1, fz  ), u)
	x2 := math.lerp(_perlin_grad(_perm[AA + 1], fx,   fy,   fz-1),
	                _perlin_grad(_perm[BA + 1], fx-1, fy,   fz-1), u)
	x3 := math.lerp(_perlin_grad(_perm[AB + 1], fx,   fy-1, fz-1),
	                _perlin_grad(_perm[BB + 1], fx-1, fy-1, fz-1), u)
	return math.lerp(math.lerp(x0, x1, v), math.lerp(x2, x3, v), w)
}

// perlin_fbm computes fractional Brownian motion (multi-octave signed Perlin noise).
// Matches the parameters used by GenImagePerlinNoise (lacunarity=2, gain=0.5, octaves=6).
// Returns a value in approximately [-1, 1] before the caller maps it to [0, 1].
perlin_fbm :: proc(p: [3]f32, lacunarity: f32 = 2.0, gain: f32 = 0.5, octaves: int = 6) -> f32 {
	result: f32
	amplitude: f32 = 1.0
	freq := p
	for _ in 0..<octaves {
		result    += amplitude * perlin_noise(freq)
		amplitude *= gain
		freq       = {freq[0] * lacunarity, freq[1] * lacunarity, freq[2] * lacunarity}
	}
	return result
}

// perlin_turbulence returns a multi-octave sum of |noise| in approximately [0, ~2].
// Used for marble: sin(scale * z + 10 * turb(p)).
perlin_turbulence :: proc(p: [3]f32, depth: int = 7) -> f32 {
	accum:  f32
	weight: f32 = 1.0
	freq := p
	for _ in 0..<depth {
		accum  += weight * math.abs(perlin_noise(freq))
		weight *= 0.5
		freq    = {freq[0] * 2, freq[1] * 2, freq[2] * 2}
	}
	return accum
}
