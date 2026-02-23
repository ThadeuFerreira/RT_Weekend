package util

import "core:math"

// Xoshiro256++ state (four 64-bit words). Per-thread RNG for parallel rendering.
ThreadRNG :: struct {
	s: [4]u64,
}

// Splitmix64 used to seed the state from a single u64.
@(private)
splitmix64 :: proc(x: ^u64) -> u64 {
	x^ += 0x9e3779b97f4a7c15
	z := x^
	z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	return z ~ (z >> 31)
}

// Create a thread-local RNG seeded with the given value.
create_thread_rng :: proc(seed: u64) -> ThreadRNG {
	rng: ThreadRNG
	sm := seed
	rng.s[0] = splitmix64(&sm)
	rng.s[1] = splitmix64(&sm)
	rng.s[2] = splitmix64(&sm)
	rng.s[3] = splitmix64(&sm)
	return rng
}

// Rotate left.
@(private)
rotl :: proc(x: u64, k: u32) -> u64 {
	return (x << k) | (x >> (64 - k))
}

// Xoshiro256++ next: returns next 64-bit value and advances state.
@(private)
next_u64 :: proc(rng: ^ThreadRNG) -> u64 {
	result := rotl(rng.s[0] + rng.s[3], 23) + rng.s[0]
	t := rng.s[1] << 17
	rng.s[2] ~= rng.s[0]
	rng.s[3] ~= rng.s[1]
	rng.s[1] ~= rng.s[2]
	rng.s[0] ~= rng.s[3]
	rng.s[2] ~= t
	rng.s[3] = rotl(rng.s[3], 45)
	return result
}

// Returns a random f32 in [0, 1).
random_float :: proc(rng: ^ThreadRNG) -> f32 {
	u := next_u64(rng)
	// 53-bit resolution for [0, 1)
	return f32(f64(u >> 11) * (1.0 / (1 << 53)))
}

// Returns a random f32 in [low, high).
random_float_range :: proc(rng: ^ThreadRNG, low, high: f32) -> f32 {
	return low + (high - low) * random_float(rng)
}
