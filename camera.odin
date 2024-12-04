package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"

Camera :: struct{
    aspect_ratio : f32,
    image_width : int,
    image_height : int,
    focal_length : f32,
    viewport_height : f32,
    viewport_width : f32,
    center : [3]f32,
    viewport_u : [3]f32,
    viewport_v : [3]f32,
    pixel_delta_u : [3]f32,
    pixel_delta_v : [3]f32,
    viewport_upper_left : [3]f32,
    pixel00_loc : [3]f32,

    samples_per_pixel : int,
    pixel_samples_scale : f32,

    max_depth : int,
}

Output :: struct{
    image_file_name : string,
    f : os.Handle,
}

make_camera :: proc() -> ^Camera {

    c := new(Camera)

    c.aspect_ratio = 16.0 / 9.0
    c.image_width = 400
    c.image_height = int(f32(c.image_width) / c.aspect_ratio)
    c.center = [3]f32{0.0, 0.0, 0.0}
    c.focal_length = 1.0
    c.viewport_height = 2.0
    c.viewport_width = c.viewport_height*(f32(c.image_width) / f32(c.image_height))
    c.viewport_u = [3]f32{c.viewport_width, 0.0, 0.0}
    c.viewport_v = [3]f32{0.0, -c.viewport_height, 0.0}
    c.pixel_delta_u = c.viewport_u / f32(c.image_width)
    c.pixel_delta_v = c.viewport_v / f32(c.image_height)
    c.viewport_upper_left = c.center - [3]f32{0, 0, c.focal_length} - (c.viewport_u/2) - (c.viewport_v/2)
    c.pixel00_loc = c.viewport_upper_left + 0.5*(c.pixel_delta_u + c.pixel_delta_v)

    c.samples_per_pixel = 100
    c.pixel_samples_scale = 1.0/f32(c.samples_per_pixel)
    c.max_depth = 50

    return c
}

render :: proc(camera : ^Camera, output : Output, world : []Object){
    f := output.f
    buffer := [8]byte{}
    fmt.fprint(f, "P3\n")
    fmt.fprint(f, strconv.itoa(buffer[:], camera.image_width))
    fmt.fprint(f, " ")
    fmt.fprint(f, strconv.itoa(buffer[:], camera.image_height))
    fmt.fprint(f, "\n255\n")

    sb := strings.Builder{}
    for j in 0..<camera.image_height {
        //Progress bar
        v := j*20/camera.image_height
        print_progress_bar(v, 20)
        for i in 0..<camera.image_width {
            pixel_color := [3]f32{0, 0, 0}
            for s in 0..<camera.samples_per_pixel {
                r := get_ray(camera, f32(i),f32(j))
                pixel_color += ray_color(r, camera.max_depth, world)
            }
            pixel_color = pixel_color * camera.pixel_samples_scale
            color_pixel := camera.pixel_samples_scale * pixel_color
            write_color(&sb, pixel_color)
        }
    }


    fmt.fprint(f, strings.to_string(sb))
}

get_ray :: proc(camera : ^Camera, u : f32, v : f32) -> ray {
    offset := sample_square()
    pixel_sample := camera.pixel00_loc + (u+offset[0])*camera.pixel_delta_u + (v + offset[1])*camera.pixel_delta_v

    ray_origin := camera.center
    ray_direction := pixel_sample - camera.center

    return ray{ray_origin, ray_direction}
}

sample_square :: proc() -> [3]f32 {
    return [3]f32{random_float() -0.5, random_float() -0.5, 0}
}