package raytrace

import "core:fmt"
import "core:math"

hit_record :: struct {
    p : [3]f32,
    normal : [3]f32,
    material : material,
    t : f32,
    front_face : bool,
}


Sphere :: struct {
    center : [3]f32,
    radius : f32,
    material : material,
}

Cube :: struct {
    center : [3]f32,
    radius : f32,
    material : material,
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
    return AABB{
        x = Interval{s.center[0] - s.radius, s.center[0] + s.radius},
        y = Interval{s.center[1] - s.radius, s.center[1] + s.radius},
        z = Interval{s.center[2] - s.radius, s.center[2] + s.radius},
    }
}

object_bounding_box :: proc(obj: Object) -> AABB {
    switch o in obj {
    case Sphere:
        return sphere_bounding_box(o)
    case Cube:
        return sphere_bounding_box(Sphere{o.center, o.radius, material{}})
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

aabb_hit :: proc(box: AABB, r: ray, ray_t: Interval) -> bool {
    tmin := ray_t.min
    tmax := ray_t.max

    for axis in 0..<3 {
        ax: Interval
        dir: f32
        orig: f32

        switch axis {
        case 0:
            ax = box.x
            dir = r.dir[0]
            orig = r.orig[0]
        case 1:
            ax = box.y
            dir = r.dir[1]
            orig = r.orig[1]
        case 2:
            ax = box.z
            dir = r.dir[2]
            orig = r.orig[2]
        }

        if math.abs(dir) < 1e-8 {
            if orig < ax.min || orig > ax.max {
                return false
            }
        } else {
            invD := 1.0 / dir
            t0 := (ax.min - orig) * invD
            t1 := (ax.max - orig) * invD

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
    bbox: AABB,
    left: ^BVHNode,
    right: ^BVHNode,
    object: Object,
    is_leaf: bool,
}

object_center :: proc(obj: Object, axis: int) -> f32 {
    switch o in obj {
    case Sphere:
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
            bbox = bbox,
            left = nil,
            right = nil,
            object = objects[0],
            is_leaf = true,
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
        return false
    }
    return false
}
