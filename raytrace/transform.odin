package raytrace

import "core:math"

Mat4 :: struct {
	m: [16]f32, // row-major
}

ObjectTransform :: struct {
	object_to_world: Mat4,
	world_to_object: Mat4,
}

TransformStack :: struct {
	stack: [dynamic]Mat4,
}

mat4_identity :: proc() -> Mat4 {
	return Mat4{m = [16]f32{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}}
}

mat4_mul :: proc(a, b: Mat4) -> Mat4 {
	out := Mat4{}
	for r in 0..<4 {
		for c in 0..<4 {
			out.m[r*4+c] = a.m[r*4+0]*b.m[c+0] + a.m[r*4+1]*b.m[c+4] + a.m[r*4+2]*b.m[c+8] + a.m[r*4+3]*b.m[c+12]
		}
	}
	return out
}

mat4_translate :: proc(t: [3]f32) -> Mat4 {
	m := mat4_identity()
	m.m[3] = t[0]
	m.m[7] = t[1]
	m.m[11] = t[2]
	return m
}

mat4_scale :: proc(s: [3]f32) -> Mat4 {
	m := mat4_identity()
	m.m[0] = s[0]
	m.m[5] = s[1]
	m.m[10] = s[2]
	return m
}

mat4_rotate_x :: proc(angle_rad: f32) -> Mat4 {
	s := math.sin(angle_rad)
	c := math.cos(angle_rad)
	return Mat4{m = [16]f32{
		1, 0, 0, 0,
		0, c, -s, 0,
		0, s, c, 0,
		0, 0, 0, 1,
	}}
}

mat4_rotate_y :: proc(angle_rad: f32) -> Mat4 {
	s := math.sin(angle_rad)
	c := math.cos(angle_rad)
	return Mat4{m = [16]f32{
		c, 0, s, 0,
		0, 1, 0, 0,
		-s, 0, c, 0,
		0, 0, 0, 1,
	}}
}

mat4_rotate_z :: proc(angle_rad: f32) -> Mat4 {
	s := math.sin(angle_rad)
	c := math.cos(angle_rad)
	return Mat4{m = [16]f32{
		c, -s, 0, 0,
		s, c, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}}
}

mat4_transform_point :: proc(m: Mat4, p: [3]f32) -> [3]f32 {
	return [3]f32{
		m.m[0]*p[0] + m.m[1]*p[1] + m.m[2]*p[2] + m.m[3],
		m.m[4]*p[0] + m.m[5]*p[1] + m.m[6]*p[2] + m.m[7],
		m.m[8]*p[0] + m.m[9]*p[1] + m.m[10]*p[2] + m.m[11],
	}
}

mat4_transform_vector :: proc(m: Mat4, v: [3]f32) -> [3]f32 {
	return [3]f32{
		m.m[0]*v[0] + m.m[1]*v[1] + m.m[2]*v[2],
		m.m[4]*v[0] + m.m[5]*v[1] + m.m[6]*v[2],
		m.m[8]*v[0] + m.m[9]*v[1] + m.m[10]*v[2],
	}
}

mat4_from_trs :: proc(translation, rotation_xyz_rad, scale_xyz: [3]f32) -> Mat4 {
	s := mat4_scale(scale_xyz)
	rx := mat4_rotate_x(rotation_xyz_rad[0])
	ry := mat4_rotate_y(rotation_xyz_rad[1])
	rz := mat4_rotate_z(rotation_xyz_rad[2])
	t := mat4_translate(translation)
	return mat4_mul(t, mat4_mul(rz, mat4_mul(ry, mat4_mul(rx, s))))
}

mat4_inverse_trs :: proc(translation, rotation_xyz_rad, scale_xyz: [3]f32) -> Mat4 {
	inv_scale := [3]f32{1.0 / scale_xyz[0], 1.0 / scale_xyz[1], 1.0 / scale_xyz[2]}
	s_inv := mat4_scale(inv_scale)
	rx_inv := mat4_rotate_x(-rotation_xyz_rad[0])
	ry_inv := mat4_rotate_y(-rotation_xyz_rad[1])
	rz_inv := mat4_rotate_z(-rotation_xyz_rad[2])
	t_inv := mat4_translate(-translation)
	return mat4_mul(s_inv, mat4_mul(rx_inv, mat4_mul(ry_inv, mat4_mul(rz_inv, t_inv))))
}

make_object_transform_trs :: proc(translation, rotation_xyz_rad, scale_xyz: [3]f32) -> ObjectTransform {
	return ObjectTransform{
		object_to_world = mat4_from_trs(translation, rotation_xyz_rad, scale_xyz),
		world_to_object = mat4_inverse_trs(translation, rotation_xyz_rad, scale_xyz),
	}
}

transform_stack_init :: proc(ts: ^TransformStack) {
	ts.stack = make([dynamic]Mat4)
	append(&ts.stack, mat4_identity())
}

transform_stack_destroy :: proc(ts: ^TransformStack) {
	if ts.stack != nil {
		delete(ts.stack)
		ts.stack = nil
	}
}

transform_stack_current :: proc(ts: ^TransformStack) -> Mat4 {
	if len(ts.stack) == 0 {
		return mat4_identity()
	}
	return ts.stack[len(ts.stack)-1]
}

transform_stack_push_mul :: proc(ts: ^TransformStack, m: Mat4) {
	cur := transform_stack_current(ts)
	append(&ts.stack, mat4_mul(cur, m))
}

transform_stack_pop :: proc(ts: ^TransformStack) {
	if len(ts.stack) <= 1 {
		return
	}
	pop(&ts.stack)
}
