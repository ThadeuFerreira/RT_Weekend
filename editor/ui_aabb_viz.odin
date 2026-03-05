package editor

import rl   "vendor:raylib"
import rt   "RT_Weekend:raytrace"
import core "RT_Weekend:core"

// compute_scene_sphere_aabb returns the AABB for a SceneSphere (motion-blur aware);
// mirrors rt.sphere_bounding_box for rt.Sphere.
compute_scene_sphere_aabb :: proc(s: core.SceneSphere) -> rt.AABB {
	r := s.radius
	c := s.center
	box := rt.AABB{
		x = {c[0] - r, c[0] + r},
		y = {c[1] - r, c[1] + r},
		z = {c[2] - r, c[2] + r},
	}
	if s.is_moving {
		c1 := s.center1
		box1 := rt.AABB{
			x = {c1[0] - r, c1[0] + r},
			y = {c1[1] - r, c1[1] + r},
			z = {c1[2] - r, c1[2] + r},
		}
		box = rt.aabb_union(box, box1)
	}
	return box
}

// draw_aabb_wireframe draws the 12 edges of an AABB. Call inside BeginMode3D.
draw_aabb_wireframe :: proc(aabb: rt.AABB, color: rl.Color) {
	xn, xx := aabb.x.min, aabb.x.max
	yn, yx := aabb.y.min, aabb.y.max
	zn, zx := aabb.z.min, aabb.z.max
	p := [8]rl.Vector3{
		{xn, yn, zn}, {xx, yn, zn}, {xx, yx, zn}, {xn, yx, zn},
		{xn, yn, zx}, {xx, yn, zx}, {xx, yx, zx}, {xn, yx, zx},
	}
	// Bottom face
	rl.DrawLine3D(p[0], p[1], color)
	rl.DrawLine3D(p[1], p[2], color)
	rl.DrawLine3D(p[2], p[3], color)
	rl.DrawLine3D(p[3], p[0], color)
	// Top face
	rl.DrawLine3D(p[4], p[5], color)
	rl.DrawLine3D(p[5], p[6], color)
	rl.DrawLine3D(p[6], p[7], color)
	rl.DrawLine3D(p[7], p[4], color)
	// Vertical edges
	rl.DrawLine3D(p[0], p[4], color)
	rl.DrawLine3D(p[1], p[5], color)
	rl.DrawLine3D(p[2], p[6], color)
	rl.DrawLine3D(p[3], p[7], color)
}

// bvh_depth_color returns a semi-transparent color for BVH depth level.
bvh_depth_color :: proc(depth: int) -> rl.Color {
	colors := [?]rl.Color{
		{220, 220, 220, 130}, // 0 = root: white-gray
		{255, 200,   0, 130}, // 1: yellow
		{  0, 220, 100, 130}, // 2: green
		{  0, 180, 255, 130}, // 3: cyan
		{160,   0, 255, 130}, // 4: purple
	}
	return colors[min(depth, len(colors) - 1)]
}

// draw_bvh_node recursively draws BVH node AABBs; call inside BeginMode3D.
// max_depth < 0 means no limit.
draw_bvh_node :: proc(node: ^rt.BVHNode, depth, max_depth: int) {
	if node == nil { return }
	if max_depth >= 0 && depth > max_depth { return }
	draw_aabb_wireframe(node.bbox, bvh_depth_color(depth))
	if !node.is_leaf {
		draw_bvh_node(node.left,  depth + 1, max_depth)
		draw_bvh_node(node.right, depth + 1, max_depth)
	}
}
