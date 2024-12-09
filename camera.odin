package main

import "core:fmt"
import "core:math"
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
    u : [3]f32,
    v : [3]f32,
    w : [3]f32,
    viewport_upper_left : [3]f32,
    pixel00_loc : [3]f32,

    samples_per_pixel : int,
    pixel_samples_scale : f32,

    
    vfov : f32, // Point camera is looking from
    lookfrom : [3]f32,// Vertical view angle (field of view)
    lookat : [3]f32,// Point camera is looking at
    vup : [3]f32,// Camera-relative "up" direction
    
    // double defocus_angle = 0;  // Variation angle of rays through each pixel
    // double focus_dist = 10;    // Distance from camera lookfrom point to plane of perfect focus
    defocus_angle : f32,
    focus_dist : f32,

    defocus_disk_u : [3]f32,
    defocus_disk_v : [3]f32,

    max_depth : int,
}

Output :: struct{
    image_file_name : string,
    f : os.Handle,
}

make_camera :: proc() -> ^Camera {

    c := new(Camera)

    c.aspect_ratio = 16.0 / 9.0
    c.image_width = 600
    c.image_height = int(f32(c.image_width) / c.aspect_ratio)
    c.vfov = 20.0
    c.samples_per_pixel = 50
    c.pixel_samples_scale = 1.0/f32(c.samples_per_pixel)
    c.max_depth = 50

    c.lookfrom = [3]f32{-2.0, 2.0, 1.0}
    c.lookat = [3]f32{0.0, 0.0, -1.0}
    c.vup = [3]f32{0.0, 1.0, 0.0}

    c.defocus_angle = 10
    c.focus_dist = 3.4
    
    
    return c
}

init_camera :: proc(c :^Camera){

    c.center = c.lookfrom

    theta := degrees_to_radians(c.vfov)
    h := math.tan(theta/2)
    c.viewport_height = 2*h*c.focus_dist
    c.viewport_width = c.viewport_height*(f32(c.image_width) / f32(c.image_height))

    // Calculate the u,v,w unit basis vectors for the camera coordinate frame.
    c.w = unit_vector(c.lookfrom - c.lookat)
    c.u = unit_vector(cross(c.vup, c.w))
    c.v = cross(c.w, c.u)

    // Calculate the vectors across the horizontal and down the vertical viewport edges.
    c.viewport_u = c.viewport_width * c.u
    c.viewport_v = -c.viewport_height * c.v
    
    // Calculate the horizontal and vertical delta vectors from pixel to pixel.
    c.pixel_delta_u = c.viewport_u / f32(c.image_width)
    c.pixel_delta_v = c.viewport_v / f32(c.image_height)

    // Calculate the location of the upper left pixel.  
    c.viewport_upper_left = c.center - (c.focus_dist * c.w) - 0.5*(c.viewport_u + c.viewport_v)
    c.pixel00_loc = c.viewport_upper_left + 0.5*(c.pixel_delta_u + c.pixel_delta_v)

    // Calculate the defocus disk vectors
    defocus_radius := c.focus_dist*math.tan(degrees_to_radians(c.defocus_angle*0.5))
    c.defocus_disk_u = defocus_radius * c.u
    c.defocus_disk_v = defocus_radius * c.v
}

render :: proc(camera : ^Camera, output : Output, world : [dynamic]Object){
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
    // Construct a camera ray originating from the defocus disk and directed at a randomly
    // sampled point around the pixel location i, j.
    offset := sample_square()
    pixel_sample := camera.pixel00_loc + (u+offset[0])*camera.pixel_delta_u + (v + offset[1])*camera.pixel_delta_v

    ray_origin := (camera.defocus_angle <= 0)? camera.center : defocus_disk_sample(camera)
    ray_direction := pixel_sample - ray_origin

    return ray{ray_origin, ray_direction}
}

defocus_disk_sample :: proc(c : ^Camera) -> [3]f32 {
    p := vector_random_in_unit_disk()
    return c.center +(p[0]*c.defocus_disk_u) + (p[1]*c.defocus_disk_v)
}

sample_square :: proc() -> [3]f32 {
    return [3]f32{random_float() -0.5, random_float() -0.5, 0}
}