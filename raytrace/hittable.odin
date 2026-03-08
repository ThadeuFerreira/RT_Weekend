package raytrace

import "core:fmt"
import "core:math"

// Compile-time flag: use SAH BVH (default) or median-split (comparison baseline).
// Override with: -define:USE_SAH_BVH=false
USE_SAH_BVH :: #config(USE_SAH_BVH, true)

// Number of bins for binned SAH construction.
N_BINS :: 12

hit_record :: struct {
    p : [3]f32,
    normal : [3]f32,
    material : material,
    t : f32,
    front_face : bool,
    u: f32,
    v: f32,
}

Sphere :: struct {
    center:    [3]f32,
    center1:   [3]f32, // end position (t=1); only used when is_moving
    radius:    f32,
    material:  material,
    is_moving: bool,
}

sphere_center_at :: proc(s: Sphere, time: f32) -> [3]f32 {
    if !s.is_moving { return s.center }
    return s.center + time * (s.center1 - s.center)
}

// sphere_get_uv returns (u, v) texture coordinates for a unit-sphere surface point p.
// p is the normalized hit point relative to sphere center (outward_normal for a sphere).
// Follows Ray Tracing: The Next Week Ch.4: theta = acos(-p.y), phi = atan2(-p.z, p.x) + π.
sphere_get_uv :: proc(p: [3]f32) -> (u, v: f32) {
    theta := math.acos(-p.y)
    phi   := math.atan2(-p.z, p.x) + math.PI
    u = phi / (2.0 * math.PI)
    v = theta / math.PI
    return
}

Cube :: struct {
    center : [3]f32,
    radius : f32,
    material : material,
}

// cube_get_uv returns (u, v) in [0,1] using face-projected UV: dominant axis of the
// outward normal, then the two remaining axes normalized to the cube face extent.
// No per-face unwrap; suitable as a simple fallback for image textures.
cube_get_uv :: proc(p: [3]f32, outward_normal: [3]f32, center: [3]f32, radius: f32) -> (u, v: f32) {
    // Dominant axis of the outward normal (which face was hit).
    ax := 0
    if math.abs(outward_normal[1]) > math.abs(outward_normal[ax]) { ax = 1 }
    if math.abs(outward_normal[2]) > math.abs(outward_normal[ax]) { ax = 2 }
    // The two other axes for (u, v).
    axis_u: int = 1 if ax == 0 else 0
    axis_v: int = 2
    if ax == 1 {
        axis_u = 0
        axis_v = 2
    } else if ax == 2 {
        axis_u = 0
        axis_v = 1
    }
    half := 2.0 * radius
    u = (p[axis_u] - center[axis_u] + radius) / half
    v = (p[axis_v] - center[axis_v] + radius) / half
    u = math.clamp(u, 0.0, 1.0)
    v = math.clamp(v, 0.0, 1.0)
    return
}

Object :: union {
    Sphere,
    Cube,
}

AABB :: struct {
    x: Interval,
    y: Interval,
    z: Interval,
}

sphere_bounding_box :: proc(s: Sphere) -> AABB {
    r := s.radius
    box0 := AABB{
        x = Interval{s.center[0] - r, s.center[0] + r},
        y = Interval{s.center[1] - r, s.center[1] + r},
        z = Interval{s.center[2] - r, s.center[2] + r},
    }
    if !s.is_moving { return box0 }
    box1 := AABB{
        x = Interval{s.center1[0] - r, s.center1[0] + r},
        y = Interval{s.center1[1] - r, s.center1[1] + r},
        z = Interval{s.center1[2] - r, s.center1[2] + r},
    }
    return aabb_union(box0, box1)
}

object_bounding_box :: proc(obj: Object) -> AABB {
    switch o in obj {
    case Sphere:
        return sphere_bounding_box(o)
    case Cube:
        return sphere_bounding_box(Sphere{center = o.center, radius = o.radius})
    }
    return AABB{
        x = Interval{0, 0},
        y = Interval{0, 0},
        z = Interval{0, 0},
    }
}

aabb_union :: proc(box0: AABB, box1: AABB) -> AABB {
    return AABB{
        x = Interval{
            math.min(box0.x.min, box1.x.min),
            math.max(box0.x.max, box1.x.max),
        },
        y = Interval{
            math.min(box0.y.min, box1.y.min),
            math.max(box0.y.max, box1.y.max),
        },
        z = Interval{
            math.min(box0.z.min, box1.z.min),
            math.max(box0.z.max, box1.z.max),
        },
    }
}

// aabb_surface_area returns 2*(dx*dy + dy*dz + dz*dx).
// Returns 0 for empty / degenerate boxes (where any dimension is negative).
aabb_surface_area :: proc(box: AABB) -> f32 {
    dx := box.x.max - box.x.min
    dy := box.y.max - box.y.min
    dz := box.z.max - box.z.min
    if dx < 0 || dy < 0 || dz < 0 { return 0 }
    return 2.0 * (dx*dy + dy*dz + dz*dx)
}

aabb_hit :: proc(box: AABB, r: ray, ray_t: Interval) -> bool {
    tmin := ray_t.min
    tmax := ray_t.max

    for axis in 0..<3 {
        ax: Interval
        dir: f32
        origin: f32

        switch axis {
        case 0:
            ax = box.x
            dir = r.dir[0]
            origin = r.origin[0]
        case 1:
            ax = box.y
            dir = r.dir[1]
            origin = r.origin[1]
        case 2:
            ax = box.z
            dir = r.dir[2]
            origin = r.origin[2]
        }

        if math.abs(dir) < 1e-8 {
            if origin < ax.min || origin > ax.max {
                return false
            }
        } else {
            invD := 1.0 / dir
            t0 := (ax.min - origin) * invD
            t1 := (ax.max - origin) * invD

            if t0 > t1 {
                t0, t1 = t1, t0
            }

            tmin = math.max(tmin, t0)
            tmax = math.min(tmax, t1)

            if tmax <= tmin {
                return false
            }
        }
    }
    return true
}

BVHNode :: struct {
    bbox:      AABB,
    left:      ^BVHNode,
    right:     ^BVHNode,
    object:    Object,
    obj_index: int,   // original world-slice index (leaf only; -1 = unknown)
    is_leaf:   bool,
}

// aabb_hit_fast is like aabb_hit but uses a precomputed inverse direction,
// eliminating 3 divisions per AABB test.  Call once per ray before the BVH loop.
// Uses the ±Inf slab method — works correctly with IEEE 754 for non-degenerate rays.
aabb_hit_fast :: proc(box: AABB, inv_dir: [3]f32, origin: [3]f32, ray_t: Interval) -> bool {
    tmin := ray_t.min
    tmax := ray_t.max

    axes := [3]Interval{box.x, box.y, box.z}
    for axis in 0..<3 {
        invD := inv_dir[axis]
        o    := origin[axis]
        t0   := (axes[axis].min - o) * invD
        t1   := (axes[axis].max - o) * invD
        if t0 > t1 { t0, t1 = t1, t0 }
        tmin = math.max(tmin, t0)
        tmax = math.min(tmax, t1)
        if tmax <= tmin { return false }
    }
    return true
}

object_center :: proc(obj: Object, axis: int) -> f32 {
    switch o in obj {
    case Sphere:
        if o.is_moving { return (o.center[axis] + o.center1[axis]) * 0.5 }
        return o.center[axis]
    case Cube:
        return o.center[axis]
    }
    return 0.0
}

build_bvh :: proc(objects: []Object, allocator := context.allocator) -> ^BVHNode {
    if len(objects) == 0 {
        return nil
    }

    if len(objects) == 1 {
        bbox := object_bounding_box(objects[0])
        node := new(BVHNode, allocator)
        node^ = BVHNode{
            bbox      = bbox,
            left      = nil,
            right     = nil,
            object    = objects[0],
            obj_index = -1,   // unknown: _flatten_bvh_recurse falls back to O(n) search
            is_leaf   = true,
        }
        return node
    }

    bbox_all := object_bounding_box(objects[0])
    for i in 1..<len(objects) {
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

    objects_sorted := make([]Object, len(objects), allocator)
    copy(objects_sorted, objects)

    for i in 1..<len(objects_sorted) {
        key := objects_sorted[i]
        j := i - 1
        for j >= 0 && object_center(objects_sorted[j], axis) > object_center(key, axis) {
            objects_sorted[j + 1] = objects_sorted[j]
            j -= 1
        }
        objects_sorted[j + 1] = key
    }

    mid := len(objects_sorted) / 2
    left_objects := objects_sorted[:mid]
    right_objects := objects_sorted[mid:]

    left_node := build_bvh(left_objects, allocator)
    right_node := build_bvh(right_objects, allocator)

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
    return node
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

bvh_hit :: proc(node: ^BVHNode, r: ray, ray_t: Interval, rec: ^hit_record, closest_so_far: ^f32) -> bool {
    if node == nil {
        return false
    }

    if !aabb_hit(node.bbox, r, ray_t) {
        return false
    }

    if node.is_leaf {
        return hit(r, ray_t, rec, node.object, closest_so_far)
    }

    hit_left := false
    hit_right := false
    left_rec := hit_record{}
    right_rec := hit_record{}

    if node.left != nil {
        hit_left = bvh_hit(node.left, r, ray_t, &left_rec, closest_so_far)
    }

    if node.right != nil {
        updated_ray_t := ray_t
        if hit_left {
            updated_ray_t.max = left_rec.t
        }
        hit_right = bvh_hit(node.right, r, updated_ray_t, &right_rec, closest_so_far)
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

// ============================================================
// Linear BVH — flat, iterative traversal (Step 1)
// ============================================================
//
// flatten_bvh converts the recursive BVHNode tree into a flat
// []LinearBVHNode via depth-first traversal.  The resulting
// array is uploadable to a GPU SSBO (Step 4) and is traversed
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
        // Slow path (median builder): fall back to O(n) value search.
        obj_idx := i32(-1)
        if node.obj_index >= 0 {
            obj_idx = i32(node.obj_index)
        } else {
            for i in 0..<len(objects) {
                switch a in node.object {
                case Sphere:
                    if b, ok := objects[i].(Sphere); ok && a == b { obj_idx = i32(i) }
                case Cube:
                    if b, ok := objects[i].(Cube); ok && a == b { obj_idx = i32(i) }
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
        if !aabb_hit_fast(bbox, inv_dir, r.origin, Interval{ray_t.min, closest}) { continue }

        if node.left_idx == -1 {
            // Leaf node: test the actual object.
            obj_idx := int(-(node.right_or_obj_idx + 1))
            if obj_idx >= 0 && obj_idx < len(objects) {
                temp_rec := hit_record{}
                if hit(r, Interval{ray_t.min, closest}, &temp_rec, objects[obj_idx], &closest) {
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

// ============================================================

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

set_face_normal :: proc(rec : ^hit_record, r : ray, outward_normal : [3]f32) {
    rec.front_face = dot(r.dir, outward_normal) < 0
    if rec.front_face {
        rec.normal = outward_normal
    } else {
        rec.normal = -outward_normal
    }
}

hit :: proc(r : ray, ray_t : Interval, rec : ^hit_record, object : Object, closest_so_far : ^f32) -> bool{
    temp_rec := hit_record{}
    closest_so_far := closest_so_far
    switch s in object {
    case Sphere:
        if hit_sphere(s, r, Interval{ray_t.min, closest_so_far^}, &temp_rec) {
            rec^ = temp_rec
            closest_so_far^ = temp_rec.t
            return true
        }
    case Cube:
        if hit_cube(s, r, Interval{ray_t.min, closest_so_far^}, &temp_rec) {
            rec^ = temp_rec
            closest_so_far^ = temp_rec.t
            return true
        }
    }
    return false
}
