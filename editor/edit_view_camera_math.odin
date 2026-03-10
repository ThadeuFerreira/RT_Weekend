package editor

import "core:math"
import rt "RT_Weekend:raytrace"

// _compute_camera_basis builds the orthonormal right/up0 basis from view direction (singularity handling in one place).
// ok = false if lookfrom/lookat are degenerate (e.g. coincident or looking straight up/down with fallback also degenerate).
_compute_camera_basis :: proc(lookfrom, lookat: [3]f32) -> (right, up0: [3]f32, ok: bool) {
	fwd := [3]f32{lookat[0] - lookfrom[0], lookat[1] - lookfrom[1], lookat[2] - lookfrom[2]}
	len_sq := fwd[0]*fwd[0] + fwd[1]*fwd[1] + fwd[2]*fwd[2]
	if len_sq < 1e-10 { return {}, {}, false }
	fwd = rt.unit_vector(fwd)
	world_up := [3]f32{0, 1, 0}
	right = rt.cross(fwd, world_up)
	right_len_sq := right[0]*right[0] + right[1]*right[1] + right[2]*right[2]
	if right_len_sq < 1e-10 {
		right = rt.cross(fwd, [3]f32{1, 0, 0})
		right_len_sq = right[0]*right[0] + right[1]*right[1] + right[2]*right[2]
		if right_len_sq < 1e-10 { return {}, {}, false }
	}
	right = rt.unit_vector(right)
	up0 = rt.unit_vector(rt.cross(right, fwd))
	return right, up0, true
}

// compute_vup_from_forward_and_roll returns a normalized up vector from view direction and roll (radians).
// forward = lookat - lookfrom; roll rotates the up vector around the view axis (0 = world up).
compute_vup_from_forward_and_roll :: proc(lookfrom, lookat: [3]f32, roll: f32) -> (vup: [3]f32) {
	right, up0, ok := _compute_camera_basis(lookfrom, lookat)
	if !ok { return {0, 1, 0} }
	vup = {
		math.cos(roll)*up0[0] + math.sin(roll)*right[0],
		math.cos(roll)*up0[1] + math.sin(roll)*right[1],
		math.cos(roll)*up0[2] + math.sin(roll)*right[2],
	}
	return rt.unit_vector(vup)
}

// cam_forward_angles returns yaw, pitch, dist of the camera's forward direction
// (lookat - lookfrom). Rotation is always relative to the camera's own center.
cam_forward_angles :: proc(lookfrom, lookat: [3]f32) -> (yaw, pitch, dist: f32) {
	d := [3]f32{lookat[0]-lookfrom[0], lookat[1]-lookfrom[1], lookat[2]-lookfrom[2]}
	dist = math.sqrt(d[0]*d[0] + d[1]*d[1] + d[2]*d[2])
	if dist < 0.001 { dist = 0.001 }
	pitch = math.asin(clamp(d[1]/dist, f32(-1), f32(1)))
	yaw   = math.atan2(d[0], d[2])
	return
}

// roll_from_vup returns the roll angle (radians) that would produce the given vup from lookfrom/lookat.
// vup = cos(roll)*up0 + sin(roll)*right => roll = atan2(dot(vup, right), dot(vup, up0)).
roll_from_vup :: proc(lookfrom, lookat, vup: [3]f32) -> f32 {
	right, up0, ok := _compute_camera_basis(lookfrom, lookat)
	if !ok { return 0 }
	return math.atan2(
		right[0]*vup[0] + right[1]*vup[1] + right[2]*vup[2],
		up0[0]*vup[0] + up0[1]*vup[1] + up0[2]*vup[2],
	)
}

// lookat_from_angles computes only the lookat point from position and forward angles (yaw, pitch, dist).
// Does not touch vup — use when changing yaw/pitch/distance so roll stays independent.
lookat_from_angles :: proc(lookfrom: [3]f32, yaw, pitch, dist: f32) -> [3]f32 {
	return [3]f32{
		lookfrom[0] + dist * math.cos(pitch) * math.sin(yaw),
		lookfrom[1] + dist * math.sin(pitch),
		lookfrom[2] + dist * math.cos(pitch) * math.cos(yaw),
	}
}

// lookat_from_forward computes lookat and vup from camera position, forward angles, distance, and roll.
// Use only when roll is being applied; for yaw/pitch/dist changes use lookat_from_angles and leave vup unchanged.
lookat_from_forward :: proc(lookfrom: [3]f32, yaw, pitch, dist, roll: f32) -> (lookat, vup: [3]f32) {
	lookat = lookat_from_angles(lookfrom, yaw, pitch, dist)
	vup = compute_vup_from_forward_and_roll(lookfrom, lookat, roll)
	return
}
