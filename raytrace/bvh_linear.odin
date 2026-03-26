package raytrace

import "core:math"
import "RT_Weekend:util"

// ============================================================
// Linear BVH — flat, iterative traversal
// ============================================================
//
// flatten_bvh converts the recursive BVHNode tree into a flat
// []LinearBVHNode via depth-first traversal.  The resulting
// array is uploadable to a GPU SSBO and is traversed
// by bvh_hit_linear without any pointer chasing.
//
// Encoding:
//   Internal node: left_idx = left child index,
//                  right_or_obj_idx = right child index
//   Leaf node:     left_idx = -1,
//                  right_or_obj_idx = -(sphere_index + 1)
//
// object_index_map maps each Object pointer back to its index
// in the original objects slice so leaf nodes can store the
// correct sphere index for bvh_hit_linear.

@(private)
_flatten_bvh_recurse :: proc(
    node: ^BVHNode,
    nodes: ^[dynamic]LinearBVHNode,
    objects: []Object,
) -> int {
    if node == nil { return -1 }

    my_index := len(nodes)
    append(nodes, LinearBVHNode{})   // placeholder; filled in below

        if node.is_leaf {
        // Find which index in objects matches this leaf's object.
        // Fast path (SAH builder): obj_index is stored in the node — O(1).
        // Slow path (median builder): fall back to O(n) search; for Quad use geometry-only match.
        obj_idx := i32(-1)
        if node.obj_index >= 0 {
            obj_idx = i32(node.obj_index)
        } else {
            for i in 0..<len(objects) {
                switch a in node.object {
                case Sphere:
                    if b, ok := objects[i].(Sphere); ok && a == b { obj_idx = i32(i) }
                case Quad:
                    if b, ok := objects[i].(Quad); ok {
                        if a == b { obj_idx = i32(i) }
                        else if quad_geometry_equal(a, b) { obj_idx = i32(i) }
                    }
                case ConstantMedium:
                    if b, ok := objects[i].(ConstantMedium); ok && a.boundary_bvh == b.boundary_bvh && a.density == b.density && a.albedo == b.albedo { obj_idx = i32(i) }
                }
            }
        }
        nodes[my_index] = LinearBVHNode{
            aabb_min        = [3]f32{node.bbox.x.min, node.bbox.y.min, node.bbox.z.min},
            aabb_max        = [3]f32{node.bbox.x.max, node.bbox.y.max, node.bbox.z.max},
            left_idx        = -1,
            right_or_obj_idx = -(obj_idx + 1),   // negative encodes the sphere index
        }
        return my_index
    }

    // Internal node: recurse left then right.
    left_idx  := _flatten_bvh_recurse(node.left,  nodes, objects)
    right_idx := _flatten_bvh_recurse(node.right, nodes, objects)

    nodes[my_index] = LinearBVHNode{
        aabb_min        = [3]f32{node.bbox.x.min, node.bbox.y.min, node.bbox.z.min},
        aabb_max        = [3]f32{node.bbox.x.max, node.bbox.y.max, node.bbox.z.max},
        left_idx        = i32(left_idx),
        right_or_obj_idx = i32(right_idx),
    }
    return my_index
}

// flatten_bvh returns a heap-allocated []LinearBVHNode.
// Index 0 is always the root. Caller must delete(result).
flatten_bvh :: proc(root: ^BVHNode, objects: []Object) -> []LinearBVHNode {
    if root == nil { return nil }
    nodes := make([dynamic]LinearBVHNode, 0, 2 * len(objects))
    _flatten_bvh_recurse(root, &nodes, objects)
    return nodes[:]
}

// flatten_bvh_for_gpu produces a LinearBVHNode array for the GPU: leaves use
// LEAF_SPHERE/LEAF_QUAD/LEAF_VOLUME and right_or_obj_idx = -(gpu_array_index + 1).
// world_to_sphere_gpu[i] = GPU sphere index for objects[i] or -1; world_to_quad_gpu and world_to_volume_gpu likewise.
// Caller must delete(result).
@(private)
_flatten_bvh_for_gpu_recurse :: proc(
    node: ^BVHNode,
    nodes: ^[dynamic]LinearBVHNode,
    objects: []Object,
    world_to_sphere_gpu: []int,
    world_to_quad_gpu: []int,
    world_to_volume_gpu: []int,
) -> int {
    if node == nil { return -1 }
    my_index := len(nodes)
    append(nodes, LinearBVHNode{})
    if node.is_leaf {
        obj_idx := node.obj_index
        if obj_idx < 0 {
            for i in 0..<len(objects) {
                switch a in node.object {
                case Sphere:
                    if b, ok := objects[i].(Sphere); ok && a == b { obj_idx = i; break }
                case Quad:
                    if b, ok := objects[i].(Quad); ok && (a == b || quad_geometry_equal(a, b)) { obj_idx = i; break }
                case ConstantMedium:
                    if b, ok := objects[i].(ConstantMedium); ok && a.boundary_bvh == b.boundary_bvh && a.density == b.density && a.albedo == b.albedo { obj_idx = i; break }
                }
            }
        }
        left_val := LEAF_SPHERE
        right_val: i32 = -1
        if obj_idx >= 0 && obj_idx < len(objects) {
            if vg := world_to_volume_gpu[obj_idx]; vg >= 0 {
                left_val  = LEAF_VOLUME
                right_val = -i32(vg + 1)
            } else if sg := world_to_sphere_gpu[obj_idx]; sg >= 0 {
                left_val  = LEAF_SPHERE
                right_val = -i32(sg + 1)
            } else if qg := world_to_quad_gpu[obj_idx]; qg >= 0 {
                left_val  = LEAF_QUAD
                right_val = -i32(qg + 1)
            }
        }
        nodes[my_index] = LinearBVHNode{
            aabb_min        = [3]f32{node.bbox.x.min, node.bbox.y.min, node.bbox.z.min},
            aabb_max        = [3]f32{node.bbox.x.max, node.bbox.y.max, node.bbox.z.max},
            left_idx        = left_val,
            right_or_obj_idx = right_val,
        }
        return my_index
    }
    left_idx  := _flatten_bvh_for_gpu_recurse(node.left,  nodes, objects, world_to_sphere_gpu, world_to_quad_gpu, world_to_volume_gpu)
    right_idx := _flatten_bvh_for_gpu_recurse(node.right, nodes, objects, world_to_sphere_gpu, world_to_quad_gpu, world_to_volume_gpu)
    nodes[my_index] = LinearBVHNode{
        aabb_min        = [3]f32{node.bbox.x.min, node.bbox.y.min, node.bbox.z.min},
        aabb_max        = [3]f32{node.bbox.x.max, node.bbox.y.max, node.bbox.z.max},
        left_idx        = i32(left_idx),
        right_or_obj_idx = i32(right_idx),
    }
    return my_index
}

flatten_bvh_for_gpu :: proc(root: ^BVHNode, objects: []Object, world_to_sphere_gpu: []int, world_to_quad_gpu: []int, world_to_volume_gpu: []int) -> []LinearBVHNode {
    if root == nil { return nil }
    if len(world_to_sphere_gpu) != len(objects) || len(world_to_quad_gpu) != len(objects) || len(world_to_volume_gpu) != len(objects) {
        return nil
    }
    nodes := make([dynamic]LinearBVHNode, 0, 2 * len(objects))
    _flatten_bvh_for_gpu_recurse(root, &nodes, objects, world_to_sphere_gpu, world_to_quad_gpu, world_to_volume_gpu)
    return nodes[:]
}

// bvh_hit_linear traverses the flat LinearBVH iteratively using
// an explicit integer stack — no recursion, no pointer chasing.
//
// This is the same algorithm as bvh_hit but:
//   • sequential memory access → better cache behaviour
//   • no function-call overhead per node
//   • the same node array can be uploaded to the GPU unchanged
//
// Extensibility note:
//   To support triangle leaves, add a second sentinel (e.g. left_idx = -2)
//   and add a hit_triangle branch alongside the existing hit_sphere call.
bvh_hit_linear :: proc(
    nodes:   []LinearBVHNode,
    objects: []Object,
    r:       ray,
    ray_t:   Interval,
    rng:     ^util.ThreadRNG = nil,
) -> (HitRecord: hit_record, Hit: bool) {
    if len(nodes) == 0 { return }

    // Precompute reciprocal direction once — eliminates 3 divisions per AABB test.
    inv_dir := [3]f32{1.0 / r.dir[0], 1.0 / r.dir[1], 1.0 / r.dir[2]}

    // Stack holds indices of nodes yet to be tested.
    // Max BVH depth for N objects is ceil(log2(N)) + 1 ≤ 64.
    stack: [64]int
    stack_ptr := 0
    stack[stack_ptr] = 0   // start at root (index 0)
    stack_ptr += 1

    rec          := hit_record{}
    hit_anything := false
    closest      := ray_t.max

    for stack_ptr > 0 {
        stack_ptr -= 1
        idx := stack[stack_ptr]
        if idx < 0 || idx >= len(nodes) { continue }

        node := nodes[idx]

        // Test AABB — skip node if ray misses the bounding box.
        bbox := AABB{
            x = Interval{node.aabb_min[0], node.aabb_max[0]},
            y = Interval{node.aabb_min[1], node.aabb_max[1]},
            z = Interval{node.aabb_min[2], node.aabb_max[2]},
        }
        if !aabb_hit_fast(bbox, r.dir, inv_dir, r.origin, Interval{ray_t.min, closest}) { continue }

		if node.left_idx == -1 {
			// Leaf node: test the actual object (Sphere, Quad, or ConstantMedium).
			obj_idx := int(-(node.right_or_obj_idx + 1))
			if obj_idx >= 0 && obj_idx < len(objects) {
				temp_rec := hit_record{}
				if hit(r, Interval{ray_t.min, closest}, &temp_rec, objects[obj_idx], &closest, rng) {
					rec          = temp_rec
					hit_anything = true
				}
			}
		} else {
            // Internal node: push both children; test closer one last (LIFO).
            if int(node.right_or_obj_idx) >= 0 && stack_ptr < 63 {
                stack[stack_ptr] = int(node.right_or_obj_idx)
                stack_ptr += 1
            }
            if int(node.left_idx) >= 0 && stack_ptr < 63 {
                stack[stack_ptr] = int(node.left_idx)
                stack_ptr += 1
            }
        }
    }

    return rec, hit_anything
}
