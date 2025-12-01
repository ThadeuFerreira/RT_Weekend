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

make_camera :: proc(image_width : int, image_height : int, samples_per_pixel : int) -> ^Camera {

    cam := new(Camera)
    // Use provided parameters
    cam.aspect_ratio = f32(image_width) / f32(image_height)
    cam.image_width = image_width
    cam.image_height = image_height
    cam.samples_per_pixel = samples_per_pixel
    cam.pixel_samples_scale = 1.0 / f32(samples_per_pixel)
    cam.max_depth = 20

    cam.vfov = 20.0
    cam.lookfrom = [3]f32{13, 2, 3}
    cam.lookat = [3]f32{0, 0, 0}
    cam.vup = [3]f32{0, 1, 0}

    cam.defocus_angle = 0.6
    cam.focus_dist = 10.0
    
    
    return cam
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
    fmt.fprint(f, strconv.write_int(buffer[:], i64(camera.image_width), 10))
    fmt.fprint(f, " ")
    fmt.fprint(f, strconv.write_int(buffer[:], i64(camera.image_height), 10))
    fmt.fprint(f, "\n255\n")

    // Create RNG instance for rendering
    rng := create_thread_rng(12345)  // Fixed seed for deterministic results

    sb := strings.Builder{}
    for j in 0..<camera.image_height {
        //Progress bar
        v := j*20/camera.image_height
        print_progress_bar(v, 20)
        for i in 0..<camera.image_width {
            pixel_color := [3]f32{0, 0, 0}
            for s in 0..<camera.samples_per_pixel {
                r := get_ray(camera, f32(i),f32(j), &rng)
                pixel_color += ray_color(r, camera.max_depth, world, &rng)
            }
            pixel_color = pixel_color * camera.pixel_samples_scale
            write_color(&sb, pixel_color)
        }
    }


    fmt.fprint(f, strings.to_string(sb))
    os.close(f)
}

get_ray :: proc(camera : ^Camera, u : f32, v : f32, rng: ^ThreadRNG) -> ray {
    // Construct a camera ray originating from the defocus disk and directed at a randomly
    // sampled point around the pixel location i, j.
    offset := sample_square(rng)
    pixel_sample := camera.pixel00_loc + (u+offset[0])*camera.pixel_delta_u + (v + offset[1])*camera.pixel_delta_v

    ray_origin := (camera.defocus_angle <= 0)? camera.center : defocus_disk_sample(camera, rng)
    ray_direction := pixel_sample - ray_origin

    return ray{ray_origin, ray_direction}
}

defocus_disk_sample :: proc(c : ^Camera, rng: ^ThreadRNG) -> [3]f32 {
    p := vector_random_in_unit_disk(rng)
    return c.center +(p[0]*c.defocus_disk_u) + (p[1]*c.defocus_disk_v)
}

sample_square :: proc(rng: ^ThreadRNG) -> [3]f32 {
    return [3]f32{random_float(rng) -0.5, random_float(rng) -0.5, 0}
}