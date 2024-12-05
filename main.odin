package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"





hello_world :: proc() {
    
    camera := make_camera()
    output := Output{image_file_name = "hello_image.ppm"}
    f, err := os.open(output.image_file_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0644)
    if err != os.ERROR_NONE {
        // handle error
        fmt.fprint(os.stderr, "Error opening file: %s\n", err)
    }
    output.f = f

    // auto material_ground = make_shared<lambertian>(color(0.8, 0.8, 0.0));
    material_ground := material(lambertian{[3]f32{0.8, 0.8, 0.0}})
    // auto material_center = make_shared<lambertian>(color(0.1, 0.2, 0.5));
    material_center := material(lambertian{[3]f32{0.1, 0.2, 0.5}})
    // auto material_left   = make_shared<metal>(color(0.8, 0.8, 0.8));
    material_left := material(metalic{[3]f32{0.8, 0.8, 0.8}, 0.3})
    // auto material_right  = make_shared<metal>(color(0.8, 0.6, 0.2));
    material_right := material(metalic{[3]f32{0.8, 0.6, 0.2}, 0.3})

    world := []Object{
        Sphere{[3]f32{0, 0, -1.2}, 0.5, &material_center},
        Sphere{[3]f32{0, -100.5, -1}, 100, &material_ground},
        Sphere{[3]f32{-1, 0, -1}, 0.5, &material_left},
        Sphere{[3]f32{1, 0, -1}, 0.5, &material_right},
        Sphere{[3]f32{0, -0.5, -0.5}, 0.1, &material_right},
    }

    render(camera, output, world)
}

main :: proc() {
    hello_world()
    
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