package raytrace

import "core:math"
import "RT_Weekend:util"

// Compile-time flag: use SAH BVH (default) or median-split (comparison baseline).
// Override with: -define:USE_SAH_BVH=false
USE_SAH_BVH :: #config(USE_SAH_BVH, true)

// Number of bins for binned SAH construction.
N_BINS :: 12

BVHNode :: struct {
    bbox:      AABB,
    left:      ^BVHNode,
    right:     ^BVHNode,
    object:    Object,
    obj_index: int,   // original world-slice index (leaf only; -1 = unknown)
    is_leaf:   bool,
}

object_center :: proc(obj: Object, axis: int) -> f32 {
	switch o in obj {
	case Sphere:
		if o.is_moving { return (o.center[axis] + o.center1[axis]) * 0.5 }
		return o.center[axis]
	case Quad:
		return o.Q[axis] + (o.u[axis] + o.v[axis]) * 0.5
	case ConstantMedium:
		if o.boundary_bvh != nil {
			bb := o.boundary_bvh.bbox
			switch axis {
			case 0: return (bb.x.min + bb.x.max) * 0.5
			case 1: return (bb.y.min + bb.y.max) * 0.5
			case 2: return (bb.z.min + bb.z.max) * 0.5
			}
		}
		return 0.0
	}
	return 0.0
}

@(private)
_build_bvh_median :: proc(objects: []Object, indices: []int, allocator := context.allocator) -> ^BVHNode {
    n := len(objects)
    if n == 0 { return nil }
    if n != len(indices) { return nil }

    if n == 1 {
        bbox := object_bounding_box(objects[0])
        node := new(BVHNode, allocator)
        node^ = BVHNode{
            bbox      = bbox,
            left      = nil,
            right     = nil,
            object    = objects[0],
            obj_index = indices[0],
            is_leaf   = true,
        }
        return node
    }

    bbox_all := object_bounding_box(objects[0])
    for i in 1..<n {
        bbox_all = aabb_union(bbox_all, object_bounding_box(objects[i]))
    }

    dx := bbox_all.x.max - bbox_all.x.min
    dy := bbox_all.y.max - bbox_all.y.min
    dz := bbox_all.z.max - bbox_all.z.min

    axis := 0
    if dy > dx && dy > dz {
        axis = 1
    } else if dz > dx && dz > dy {
        axis = 2
    }

    objects_sorted := make([]Object, n, allocator)
    indices_sorted := make([]int, n, allocator)
    copy(objects_sorted, objects)
    copy(indices_sorted, indices)

    for i in 1..<n {
        key_obj := objects_sorted[i]
        key_idx := indices_sorted[i]
        j := i - 1
        for j >= 0 && object_center(objects_sorted[j], axis) > object_center(key_obj, axis) {
            objects_sorted[j + 1] = objects_sorted[j]
            indices_sorted[j + 1] = indices_sorted[j]
            j -= 1
        }
        objects_sorted[j + 1] = key_obj
        indices_sorted[j + 1] = key_idx
    }

    mid := n / 2
    left_node  := _build_bvh_median(objects_sorted[:mid], indices_sorted[:mid], allocator)
    right_node := _build_bvh_median(objects_sorted[mid:], indices_sorted[mid:], allocator)

    bbox := left_node.bbox
    if right_node != nil {
        bbox = aabb_union(bbox, right_node.bbox)
    }

    node := new(BVHNode, allocator)
    node^ = BVHNode{
        bbox = bbox,
        left = left_node,
        right = right_node,
        is_leaf = false,
    }

    delete(objects_sorted)
    delete(indices_sorted)
    return node
}

build_bvh :: proc(objects: []Object, allocator := context.allocator) -> ^BVHNode {
    if len(objects) == 0 {
        return nil
    }
    indices := make([]int, len(objects), allocator)
    for i in 0..<len(indices) {
        indices[i] = i
    }
    defer delete(indices)
    return _build_bvh_median(objects, indices, allocator)
}

// ============================================================
// SAH BVH — Surface Area Heuristic construction
// ============================================================
//
// build_bvh_sah builds a BVH using binned SAH for large partitions
// and falls back to median split for small ones (n ≤ 4).
//
// It allocates one working copy of objects + a parallel index array,
// partitions them in place (like quicksort), then frees them after
// the tree is built. Each leaf stores obj_index so flatten_bvh
// can look up the original world-slice index in O(1).
//
// Enable/disable via: -define:USE_SAH_BVH=false (median split)

@(private)
BVHSAHBin :: struct {
    bbox:  AABB,
    count: int,
}

@(private)
_build_bvh_sah :: proc(objects: []Object, indices: []int, allocator := context.allocator) -> ^BVHNode {
    n := len(objects)
    if n == 0 { return nil }

    node := new(BVHNode, allocator)

    // Compute bounding box of all objects in this partition.
    parent_bbox := object_bounding_box(objects[0])
    for i in 1..<n {
        parent_bbox = aabb_union(parent_bbox, object_bounding_box(objects[i]))
    }
    node.bbox = parent_bbox

    if n == 1 {
        node.is_leaf   = true
        node.object    = objects[0]
        node.obj_index = indices[0]   // O(1): tracked through partitioning
        return node
    }

    // Compute centroid range for SAH axis selection.
    centroid_min := [3]f32{
        object_center(objects[0], 0),
        object_center(objects[0], 1),
        object_center(objects[0], 2),
    }
    centroid_max := centroid_min
    for i in 1..<n {
        for ax in 0..<3 {
            c := object_center(objects[i], ax)
            centroid_min[ax] = math.min(centroid_min[ax], c)
            centroid_max[ax] = math.max(centroid_max[ax], c)
        }
    }

    parent_area := aabb_surface_area(parent_bbox)

    best_cost  := f32(n)   // leaf cost: no split pays n intersection tests
    best_axis  := -1
    best_split := 0

    // Binned SAH: only worth it for n > 4.
    if n > 4 && parent_area > 0 {
        empty_iv := Interval{math.inf_f32(1), math.inf_f32(-1)}

        for axis in 0..<3 {
            cmin   := centroid_min[axis]
            cmax   := centroid_max[axis]
            extent := cmax - cmin
            if extent < 1e-6 { continue }   // degenerate axis: all centroids equal

            // Initialise bins.
            bins: [N_BINS]BVHSAHBin
            for i in 0..<N_BINS {
                bins[i] = BVHSAHBin{
                    bbox  = AABB{x = empty_iv, y = empty_iv, z = empty_iv},
                    count = 0,
                }
            }

            // Assign each object to a bin by its centroid.
            for i in 0..<n {
                c := object_center(objects[i], axis)
                bi := int((c - cmin) / extent * N_BINS)
                if bi >= N_BINS { bi = N_BINS - 1 }
                bins[bi].count += 1
                bins[bi].bbox   = aabb_union(bins[bi].bbox, object_bounding_box(objects[i]))
            }

            // Forward sweep: left area and count for split after bin k.
            left_area:  [N_BINS - 1]f32
            left_count: [N_BINS - 1]int
            running_bbox  := bins[0].bbox
            running_count := bins[0].count
            for k in 0..<N_BINS - 1 {
                left_area[k]  = aabb_surface_area(running_bbox)
                left_count[k] = running_count
                if k + 1 < N_BINS {
                    running_bbox  = aabb_union(running_bbox, bins[k + 1].bbox)
                    running_count += bins[k + 1].count
                }
            }

            // Backward sweep: evaluate SAH cost for each split plane.
            right_bbox := bins[N_BINS - 1].bbox
            right_cnt  := bins[N_BINS - 1].count
            for k := N_BINS - 2; k >= 0; k -= 1 {
                cost := (left_area[k] * f32(left_count[k]) +
                         aabb_surface_area(right_bbox) * f32(right_cnt)) / parent_area + 1.0
                if cost < best_cost {
                    best_cost  = cost
                    best_axis  = axis
                    best_split = k
                }
                right_bbox = aabb_union(right_bbox, bins[k].bbox)
                right_cnt += bins[k].count
            }
        }
    }

    // Partition objects and indices in place.
    mid := n / 2   // default: median
    if best_axis >= 0 {
        // SAH split: divide at the boundary between bin best_split and best_split+1.
        cmin      := centroid_min[best_axis]
        cmax      := centroid_max[best_axis]
        extent    := cmax - cmin
        split_val := cmin + (f32(best_split + 1) / f32(N_BINS)) * extent

        i := 0
        for j in 0..<n {
            if object_center(objects[j], best_axis) < split_val {
                objects[i], objects[j] = objects[j], objects[i]
                indices[i], indices[j] = indices[j], indices[i]
                i += 1
            }
        }
        if i == 0 || i == n { i = n / 2 }   // degenerate partition → median fallback
        mid = i
    } else {
        // n ≤ 4 or no SAH improvement: median split on longest axis.
        dx := parent_bbox.x.max - parent_bbox.x.min
        dy := parent_bbox.y.max - parent_bbox.y.min
        dz := parent_bbox.z.max - parent_bbox.z.min
        axis := 0
        if dy > dx && dy > dz { axis = 1 } else if dz > dx && dz > dy { axis = 2 }

        // Insertion sort (cheap for n ≤ 4; also used as fallback).
        for i in 1..<n {
            key_obj := objects[i]
            key_idx := indices[i]
            j := i - 1
            for j >= 0 && object_center(objects[j], axis) > object_center(key_obj, axis) {
                objects[j + 1] = objects[j]
                indices[j + 1] = indices[j]
                j -= 1
            }
            objects[j + 1] = key_obj
            indices[j + 1] = key_idx
        }
        mid = n / 2
    }

    node.is_leaf = false
    node.left    = _build_bvh_sah(objects[:mid], indices[:mid], allocator)
    node.right   = _build_bvh_sah(objects[mid:], indices[mid:], allocator)
    return node
}

// build_bvh_sah is the SAH entry point. It allocates a working copy
// of objects and a parallel index array (O(n) total), then delegates
// to _build_bvh_sah which partitions in place — no per-level alloc.
build_bvh_sah :: proc(objects: []Object, allocator := context.allocator) -> ^BVHNode {
    if len(objects) == 0 { return nil }

    objects_work := make([]Object, len(objects))
    indices      := make([]int,    len(objects))
    defer delete(objects_work)
    defer delete(indices)

    copy(objects_work, objects)
    for i in 0..<len(indices) { indices[i] = i }

    return _build_bvh_sah(objects_work, indices, allocator)
}

// collect_quads_from_bvh appends all Quad leaves from the BVH tree to out.
// Used by the GPU path to export volume boundary geometry (6 quads per ConstantMedium).
collect_quads_from_bvh :: proc(node: ^BVHNode, out: ^[dynamic]Quad) {
	if node == nil { return }
	if node.is_leaf {
		if q, ok := node.object.(Quad); ok {
			append(out, q)
		}
		return
	}
	collect_quads_from_bvh(node.left, out)
	collect_quads_from_bvh(node.right, out)
}

bvh_hit :: proc(node: ^BVHNode, r: ray, ray_t: Interval, rec: ^hit_record, closest_so_far: ^f32, rng: ^util.ThreadRNG = nil) -> bool {
	if node == nil {
		return false
	}

	if !aabb_hit(node.bbox, r, ray_t) {
		return false
	}

	if node.is_leaf {
		return hit(r, ray_t, rec, node.object, closest_so_far, rng)
	}

    hit_left := false
    hit_right := false
    left_rec := hit_record{}
    right_rec := hit_record{}

	if node.left != nil {
		hit_left = bvh_hit(node.left, r, ray_t, &left_rec, closest_so_far, rng)
	}

	if node.right != nil {
		updated_ray_t := ray_t
		if hit_left {
			updated_ray_t.max = left_rec.t
		}
		hit_right = bvh_hit(node.right, r, updated_ray_t, &right_rec, closest_so_far, rng)
	}

    if hit_left && hit_right {
        if left_rec.t < right_rec.t {
            rec^ = left_rec
        } else {
            rec^ = right_rec
        }
        return true
    } else if hit_left {
        rec^ = left_rec
        return true
    } else if hit_right {
        rec^ = right_rec
        return true
    }

    return false
}

free_bvh :: proc(node: ^BVHNode, allocator := context.allocator) {
    if node == nil {
        return
    }
    if node.left != nil {
        free_bvh(node.left, allocator)
    }
    if node.right != nil {
        free_bvh(node.right, allocator)
    }
    free(node)
}
