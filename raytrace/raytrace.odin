package raytrace

import "core:fmt"
import "core:os"
import "core:strconv"
import "RT_Weekend:util"

TestPixelBuffer :: struct {
    width: int,
    height: int,
    pixels: [] [3]f32,
}

create_test_pixel_buffer :: proc(width: int, height: int) -> TestPixelBuffer {
    pixels := make([] [3]f32, width * height)
    return TestPixelBuffer{width = width, height = height, pixels = pixels}
}

set_pixel :: proc(buffer: ^TestPixelBuffer, x: int, y: int, color: [3]f32) {
    if x >= 0 && x < buffer.width && y >= 0 && y < buffer.height {
        buffer.pixels[y * buffer.width + x] = color
    }
}

write_buffer_to_ppm :: proc(buffer: ^TestPixelBuffer, file_name: string, camera: ^Camera) {
    f, err := os.open(file_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0644)
    if err != os.ERROR_NONE {
        fmt.fprint(os.stderr, "Error opening file: %s\n", err)
        return
    }
    defer os.close(f)

    output_buffer := [8]byte{}
    fmt.fprint(f, "P6\n")
    fmt.fprint(f, strconv.write_int(output_buffer[:], i64(buffer.width), 10))
    fmt.fprint(f, " ")
    fmt.fprint(f, strconv.write_int(output_buffer[:], i64(buffer.height), 10))
    fmt.fprint(f, "\n255\n")

    pixel_data := make([]u8, buffer.width * buffer.height * 3)
    defer delete(pixel_data)

    pixel_idx := 0
    i := Interval{0.0, 0.999}

    for y in 0..<buffer.height {
        for x in 0..<buffer.width {
            raw_color := buffer.pixels[y * buffer.width + x] * camera.pixel_samples_scale

            r := linear_to_gamma(raw_color[0])
            g := linear_to_gamma(raw_color[1])
            b := linear_to_gamma(raw_color[2])

            pixel_data[pixel_idx + 0] = u8(interval_clamp(i, r) * 255.0)
            pixel_data[pixel_idx + 1] = u8(interval_clamp(i, g) * 255.0)
            pixel_data[pixel_idx + 2] = u8(interval_clamp(i, b) * 255.0)

            pixel_idx += 3
        }
    }

    os.write(f, pixel_data)
}

setup_scene :: proc(image_width, image_height, samples_per_pixel, number_of_spheres: int) -> (^Camera, [dynamic]Object) {
    world := make([dynamic]Object, 0, number_of_spheres)

    scene_rng := util.create_thread_rng(54321)

    ground_material := material(lambertian{[3]f32{0.5, 0.5, 0.5}})
    append(&world, Sphere{[3]f32{0, -1000, 0}, 1000, ground_material})

    num_spheres := 0
    for a in -11..<11 {
        for b in -11..<11 {
            choose_mat := util.random_float(&scene_rng)
            center := [3]f32{f32(a) + 0.9*util.random_float(&scene_rng), 0.2, f32(b) + 0.9*util.random_float(&scene_rng)}
            center_to_check := [3]f32{center[0] - 4.0, center[1] - 0.2, center[2] - 0.0}
            if vector_length_squared(center_to_check) > 0.81 {
                if choose_mat < 0.8 {
                    albedo   := vector_random(&scene_rng) * vector_random(&scene_rng)
                    mat      := material(lambertian{albedo})
                    append(&world, Sphere{center, 0.2, mat})
                } else if choose_mat < 0.95 {
                    albedo   := vector_random_range(&scene_rng, 0.5, 1)
                    fuzz     := util.random_float_range(&scene_rng, 0, 0.5)
                    mat      := material(metallic{albedo, fuzz})
                    append(&world, Sphere{center, 0.2, mat})
                } else {
                    mat := material(dielectric{1.5})
                    append(&world, Sphere{center, 0.2, mat})
                }
                num_spheres += 1
            }
        }
        if num_spheres >= number_of_spheres {
            break
        }
    }

    material1 := material(dielectric{1.5})
    append(&world, Sphere{[3]f32{0, 1, 0}, 1.0, material1})

    material2 := material(lambertian{[3]f32{0.4, 0.2, 0.1}})
    append(&world, Sphere{[3]f32{-4, 1, 0}, 1.0, material2})

    material3 := material(metallic{[3]f32{0.7, 0.6, 0.5}, 0.0})
    append(&world, Sphere{[3]f32{4, 1, 0}, 1.0, material3})

    cam := make_camera(image_width, image_height, samples_per_pixel)
    init_camera(cam)

    return cam, world
}
