package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:flags"

ray_trace_world :: proc(output_file_name : string) {
    
    output := Output{image_file_name = output_file_name}
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
    cam.image_width = 800
    cam.samples_per_pixel = 80
    cam.max_depth = 20

    cam.vfov = 20.0
    cam.lookfrom = [3]f32{13, 2, 3}
    cam.lookat = [3]f32{0, 0, 0}
    cam.vup = [3]f32{0, 1, 0}

    cam.defocus_angle = 0.6
    cam.focus_dist = 10.0

    init_camera(cam)
    render(cam, output, world)
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

Args :: struct {
    //InputFile  : string `args:"name=input"`,
    OutputFile : string `args:"name=output"`, 
  }

  
  
main :: proc() {
    args := Args{}
    flags.parse(&args, os.args, .Unix)
    //fmt.print(args.InputFile)
    fmt.print(args.OutputFile)
    if len(args.OutputFile) > 0 {
        fmt.print("Output file is set")
    }else{
        fmt.print("Output file is not set- using default")
        args.OutputFile = "output.ppm"
    }
    ray_trace_world(args.OutputFile)
    
}