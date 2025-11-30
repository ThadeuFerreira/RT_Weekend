package main

import "core:fmt"
import "core:os"
import "core:strings"


ray_trace_world :: proc(output_file_name : string, image_width : int, image_height : int, samples_per_pixel : int, number_of_spheres : int) {
    
    output := Output{image_file_name = output_file_name}
    f, err := os.open(output.image_file_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0644)
    if err != os.ERROR_NONE {
        // handle error
        fmt.fprint(os.stderr, "Error opening file: %s\n", err)
        return
    }
    output.f = f

    world := make([dynamic]Object, 0, number_of_spheres)

    // Create RNG for scene generation
    scene_rng := create_thread_rng(54321)  // Fixed seed for deterministic scene generation

    ground_material := material(lambertian{[3]f32{0.5, 0.5, 0.5}})
    append(&world, Sphere{[3]f32{0, -1000, 0}, 1000, ground_material})

    for a in -11..<11 {
        for b in -11..<11 {
            choose_mat := random_float(&scene_rng)
            center := [3]f32{f32(a) + 0.9*random_float(&scene_rng), 0.2, f32(b) + 0.9*random_float(&scene_rng)}
            if vector_length(center - [3]f32{4, 0.2, 0}) > 0.9 {
                if choose_mat < 0.8 {
                    // diffuse
                    albedo := vector_random(&scene_rng) * vector_random(&scene_rng)
                    fmt.println(albedo)
                    material := material(lambertian{albedo})
                    append(&world, Sphere{center, 0.2, material})
                } else if choose_mat < 0.95 {
                    // metal
                    albedo := vector_random_range(&scene_rng, 0.5, 1)
                    fuzz := random_float_range(&scene_rng, 0, 0.5)
                    fmt.println(albedo)
                    material := material(metalic{albedo, fuzz})
                    append(&world, Sphere{center, 0.2, material})
                } else {
                    // glass
                    material := material(dieletric{1.5})
                    append(&world, Sphere{center, 0.2, material})
                }
            }
        }
    }

    for i in 0..<len(world) {

        obj := world[i]
        switch o in obj {
            case Sphere:
            mat := o.material
            //print pointer
            fmt.println(mat)
            fmt.println(&mat)
            case Cube:
                fmt.print("Cube")
        }
        
    }

    material1 := material(dieletric{1.5})
    append(&world, Sphere{[3]f32{0, 1, 0}, 1.0, material1})

    material2 := material(lambertian{[3]f32{0.4, 0.2, 0.1}})
    append(&world, Sphere{[3]f32{-4, 1, 0}, 1.0, material2})

    material3 := material(metalic{[3]f32{0.7, 0.6, 0.5}, 0.0})
    append(&world, Sphere{[3]f32{4, 1, 0}, 1.0, material3})

    cam := make_camera()

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

    init_camera(cam)
    
    // Start timing
    timer := start_timer()
    fmt.println("Starting rendering...")
    
    // Render the scene
    render(cam, output, world)
    
    // Stop timing and display statistics
    stop_timer(&timer)
    print_timing_stats(timer, image_width, image_height, samples_per_pixel)
}

//Generate a random noise texture and output it to file_name+test.ppm
test_mode :: proc(file_name : string, width : int, height : int) {
    output := Output{image_file_name = fmt.tprintf("%s_test.ppm", file_name)}
    f, err := os.open(output.image_file_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0644)
    if err != os.ERROR_NONE {
        // handle error
        fmt.fprint(os.stderr, "Error opening file: %s\n", err)
        return
    }
    output.f = f

    prng := create_thread_rng(54321)
    
    sb := strings.Builder{}
    for y in 0..<height {
        for x in 0..<width {
            random_r := random_float(&prng)
            random_g := random_float(&prng)
            random_b := random_float(&prng)
            color := [3]f32{random_r, random_g, random_b}
            write_color(&sb, color)
        }
    }
    
    fmt.fprint(output.f, strings.to_string(sb))
    os.close(output.f)
}