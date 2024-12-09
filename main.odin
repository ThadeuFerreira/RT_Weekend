package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:flags"





ray_trace_world :: proc() {
    
    output := Output{image_file_name = "hello_image.ppm"}
    f, err := os.open(output.image_file_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0644)
    if err != os.ERROR_NONE {
        // handle error
        fmt.fprint(os.stderr, "Error opening file: %s\n", err)
    }
    output.f = f

    world := make([dynamic]Object, 0, 1000)

    ground_material := material(lambertian{[3]f32{0.5, 0.5, 0.5}})
    append(&world, Sphere{[3]f32{0, -1000, 0}, 1000, ground_material})

    for a in -11..<11 {
        for b in -11..<11 {
            choose_mat := random_float()
            center := [3]f32{f32(a) + 0.9*random_float(), 0.2, f32(b) + 0.9*random_float()}
            if vector_length(center - [3]f32{4, 0.2, 0}) > 0.9 {
                if choose_mat < 0.8 {
                    // diffuse
                    albedo := vector_random() * vector_random()
                    fmt.println(albedo)
                    material := material(lambertian{albedo})
                    append(&world, Sphere{center, 0.2, material})
                } else if choose_mat < 0.95 {
                    // metal
                    albedo := vector_random_range(0.5, 1)
                    fuzz := random_float_range(0, 0.5)
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

    cam.aspect_ratio = 16.0 / 9.0
    cam.image_width = 300
    cam.samples_per_pixel = 10
    cam.max_depth = 10

    cam.vfov = 20.0
    cam.lookfrom = [3]f32{13, 2, 3}
    cam.lookat = [3]f32{0, 0, 0}
    cam.vup = [3]f32{0, 1, 0}

    cam.defocus_angle = 0.6
    cam.focus_dist = 10.0

    init_camera(cam)

    // // auto material_ground = make_shared<lambertian>(color(0.8, 0.8, 0.0));
    // material_ground := material(lambertian{[3]f32{0.8, 0.8, 0.0}})
    // // auto material_center = make_shared<lambertian>(color(0.1, 0.2, 0.5));
    // material_center := material(lambertian{[3]f32{0.1, 0.2, 0.5}})
    // // auto material_left   = make_shared<metal>(color(0.8, 0.8, 0.8));
    // //material_left := material(metalic{[3]f32{0.8, 0.8, 0.8}, 0.3})
    // material_left := material(dieletric{1.5})
    // material_bubble := material(dieletric{1/1.5})
    // // auto material_right  = make_shared<metal>(color(0.8, 0.6, 0.2));
    // material_right := material(metalic{[3]f32{0.8, 0.6, 0.2}, 1.0})

    // world := []Object{
    //     Sphere{[3]f32{0, 0, -1.2}, 0.5, &material_center},
    //     Sphere{[3]f32{0, -100.5, -1}, 100, &material_ground},
    //     Sphere{[3]f32{-1, 0, -1}, 0.5, &material_left},
    //     Sphere{[3]f32{-1, 0, -1}, 0.4, &material_bubble},
    //     Sphere{[3]f32{1, 0, -1}, 0.5, &material_right},
    //     Sphere{[3]f32{0, -0.5, -0.5}, 0.1, &material_right},
    // }

    render(cam, output, world)
}

Args :: struct {
    InputFile  : string `args:"name=input"`,
    OutputFile : string `args:"name=output"`, 
  }

main :: proc() {
    args := Args{}
    flags.parse_or_exit(&args, os.args, .Unix)
    fmt.print(args.InputFile)
    fmt.print(args.OutputFile)
    ray_trace_world()
    
}


print_progress_bar :: proc(count : int, max : int) {
    prefix := "Progress: ["
    suffix := "]"
    prefix_length := len(prefix)
    suffix_length := len(suffix)
    buffer := strings.builder_make()
    //strings.builder_init_len_cap(&buffer,prefix_length + suffix_length + 1, max + prefix_length + suffix_length + 1)
    strings.write_string(&buffer, prefix)
    for i in 0..<max {
        if i < count {
            strings.write_byte(&buffer, '#')
        } else {
            strings.write_byte(&buffer, ' ')
        }
    }
    strings.write_string(&buffer, suffix)
    output := strings.to_string(buffer)

    // printf("\033[s");  // Save cursor position
    // printf("\033[K");  // Clear line
    fmt.printf("\033[s")
    fmt.printf("\033[K")

    fmt.printfln("\r%s", output)
}