package core

import "core:math"
import "core:strconv"

// entity_position returns the primary translation anchor for viewport drag and display.
entity_position :: proc(e: SceneEntity) -> [3]f32 {
	switch x in e {
	case SceneSphere:
		return x.center
	case SceneQuad:
		return x.Q
	case SceneVolume:
		return x.translate
	}
	return {}
}

// entity_set_position sets the primary position (sphere center, quad corner Q, volume translate).
// For moving spheres, preserves center1 relative to center.
entity_set_position :: proc(e: ^SceneEntity, pos: [3]f32) {
	switch &x in e {
	case SceneSphere:
		if x.is_moving {
			d := pos - x.center
			x.center = pos
			x.center1 += d
		} else {
			x.center = pos
		}
	case SceneQuad:
		x.Q = pos
	case SceneVolume:
		x.translate = pos
	}
}

// entity_translate offsets the entity by delta in world space.
entity_translate :: proc(e: ^SceneEntity, delta: [3]f32) {
	switch &x in e {
	case SceneSphere:
		x.center += delta
		if x.is_moving {
			x.center1 += delta
		}
	case SceneQuad:
		x.Q += delta
	case SceneVolume:
		x.translate += delta
	}
}

@(private)
aabb_expand_point :: proc(bmin, bmax: ^[3]f32, p: [3]f32) {
	bmin[0] = min(bmin[0], p[0])
	bmin[1] = min(bmin[1], p[1])
	bmin[2] = min(bmin[2], p[2])
	bmax[0] = max(bmax[0], p[0])
	bmax[1] = max(bmax[1], p[1])
	bmax[2] = max(bmax[2], p[2])
}

@(private)
volume_corner_world :: proc(v: SceneVolume, local: [3]f32) -> [3]f32 {
	rot := degrees_to_radians(v.rotate_y_deg)
	c := math.cos(rot)
	s := math.sin(rot)
	// rotate_y: x' = c*x + s*z, z' = -s*x + c*z
	p := [3]f32{
		c * local[0] + s * local[2],
		local[1],
		-s * local[0] + c * local[2],
	}
	return p + v.translate
}

// entity_bounds returns a world-space axis-aligned bounding box when ok is true.
entity_bounds :: proc(e: SceneEntity) -> (bmin, bmax: [3]f32, ok: bool) {
	switch x in e {
	case SceneSphere:
		if scene_sphere_is_ground(x) {
			return {}, {}, false
		}
		r := x.radius
		if x.is_moving {
			c0 := x.center
			c1 := x.center1
			bmin = {
				min(c0[0] - r, c1[0] - r),
				min(c0[1] - r, c1[1] - r),
				min(c0[2] - r, c1[2] - r),
			}
			bmax = {
				max(c0[0] + r, c1[0] + r),
				max(c0[1] + r, c1[1] + r),
				max(c0[2] + r, c1[2] + r),
			}
			return bmin, bmax, true
		}
		bmin = x.center - [3]f32{r, r, r}
		bmax = x.center + [3]f32{r, r, r}
		return bmin, bmax, true
	case SceneQuad:
		bmin = {1e30, 1e30, 1e30}
		bmax = {-1e30, -1e30, -1e30}
		p0 := x.Q
		p1 := x.Q + x.u
		p2 := x.Q + x.v
		p3 := x.Q + x.u + x.v
		aabb_expand_point(&bmin, &bmax, p0)
		aabb_expand_point(&bmin, &bmax, p1)
		aabb_expand_point(&bmin, &bmax, p2)
		aabb_expand_point(&bmin, &bmax, p3)
		return bmin, bmax, true
	case SceneVolume:
		corners := [8][3]f32{
			{x.box_min[0], x.box_min[1], x.box_min[2]},
			{x.box_max[0], x.box_min[1], x.box_min[2]},
			{x.box_min[0], x.box_max[1], x.box_min[2]},
			{x.box_max[0], x.box_max[1], x.box_min[2]},
			{x.box_min[0], x.box_min[1], x.box_max[2]},
			{x.box_max[0], x.box_min[1], x.box_max[2]},
			{x.box_min[0], x.box_max[1], x.box_max[2]},
			{x.box_max[0], x.box_max[1], x.box_max[2]},
		}
		bmin = {1e30, 1e30, 1e30}
		bmax = {-1e30, -1e30, -1e30}
		for i in 0 ..< 8 {
			w := volume_corner_world(x, corners[i])
			aabb_expand_point(&bmin, &bmax, w)
		}
		return bmin, bmax, true
	}
	return {}, {}, false
}

degrees_to_radians :: proc(deg: f32) -> f32 {
	return deg * (math.PI / 180.0)
}

// entity_kind_name returns a short type label for UI.
entity_kind_name :: proc(e: SceneEntity) -> string {
	switch v in e {
	case SceneSphere:
		return "Sphere"
	case SceneQuad:
		return "Quad"
	case SceneVolume:
		return "Volume"
	}
	return "?"
}

// entity_display_name_into writes a null-terminated label into buf (e.g. "O Sphere #1").
// Returns cstring into buf; needs at least 64 bytes for safety.
entity_display_name_into :: proc(buf: []u8, e: SceneEntity, idx: int) -> cstring {
	prefix: string
	switch v in e {
	case SceneSphere:
		prefix = "O Sphere #"
	case SceneQuad:
		prefix = "Q Quad #"
	case SceneVolume:
		prefix = "V Volume #"
	case:
		prefix = "? #"
	}
	w := 0
	for i in 0 ..< len(prefix) {
		if w >= len(buf) - 1 {
			break
		}
		buf[w] = prefix[i]
		w += 1
	}
	if w < len(buf) - 1 {
		rest := buf[w:]
		num_str := strconv.write_int(rest, i64(idx + 1), 10)
		w += len(num_str)
	}
	if w >= len(buf) {
		w = len(buf) - 1
	}
	buf[w] = 0
	return cstring(raw_data(buf[: w + 1]))
}

// entity_drag_plane_y returns the Y coordinate of the horizontal drag plane (XZ movement).
entity_drag_plane_y :: proc(e: SceneEntity) -> f32 {
	switch x in e {
	case SceneSphere:
		return x.center[1]
	case SceneQuad:
		return x.Q[1]
	case SceneVolume:
		if bmin, bmax, ok := entity_bounds(e); ok {
			return 0.5 * (bmin[1] + bmax[1])
		}
		return x.translate[1]
	}
	return 0
}

// entity_is_ground is true only for ground-marked spheres.
entity_is_ground :: proc(e: SceneEntity) -> bool {
	if s, ok := e.(SceneSphere); ok {
		return scene_sphere_is_ground(s)
	}
	return false
}
