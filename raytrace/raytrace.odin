package raytrace

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:c"
import "RT_Weekend:core"
import "RT_Weekend:util"
import stbi "vendor:stb/image"

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

write_buffer_to_ppm :: proc(buffer: ^TestPixelBuffer, file_name: string, r_camera: ^Camera) {
    f, err := os.open(file_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o644)
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
            raw_color := buffer.pixels[y * buffer.width + x] * r_camera.pixel_samples_scale

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

write_buffer_to_png :: proc(buffer: ^TestPixelBuffer, file_name: string, r_camera: ^Camera) -> bool {
    pixel_data := make([]u8, buffer.width * buffer.height * 3)
    defer delete(pixel_data)

    pixel_idx := 0
    clamp_interval := Interval{0.0, 0.999}

    for y in 0..<buffer.height {
        for x in 0..<buffer.width {
            raw_color := buffer.pixels[y * buffer.width + x] * r_camera.pixel_samples_scale
            r := linear_to_gamma(raw_color[0])
            g := linear_to_gamma(raw_color[1])
            b := linear_to_gamma(raw_color[2])
            pixel_data[pixel_idx + 0] = u8(interval_clamp(clamp_interval, r) * 255.0)
            pixel_data[pixel_idx + 1] = u8(interval_clamp(clamp_interval, g) * 255.0)
            pixel_data[pixel_idx + 2] = u8(interval_clamp(clamp_interval, b) * 255.0)
            pixel_idx += 3
        }
    }

    cname := strings.clone_to_cstring(file_name)
    defer delete(cname)
    result := stbi.write_png(cname, c.int(buffer.width), c.int(buffer.height), 3,
                             raw_data(pixel_data), c.int(buffer.width * 3))
    return result != 0
}

// Legacy: ground_texture is ^Texture for optional; elsewhere (e.g. build_world_from_scene) textures are passed by value.
setup_scene :: proc(image_width, image_height, samples_per_pixel, number_of_spheres: int, ground_texture: ^Texture = nil) -> (^Camera, [dynamic]Object) {
    world := make([dynamic]Object, 0, number_of_spheres)

    scene_rng := util.create_thread_rng(54321)

    ground_rtex: RTexture = ConstantTexture{color = {0.5, 0.5, 0.5}}
    if ground_texture != nil {
        switch g in ground_texture^ {
        case ConstantTexture:   ground_rtex = g
        case CheckerTexture:    ground_rtex = g
        case core.ImageTexture: {}
        }
    }
    ground_material := material(lambertian{albedo = ground_rtex})
    append(&world, Sphere{center = {0, -1000, 0}, radius = 1000, material = ground_material})

    num_spheres := 0
    for a in -11..<11 {
        for b in -11..<11 {
            choose_mat := util.random_float(&scene_rng)
            center := [3]f32{f32(a) + 0.9*util.random_float(&scene_rng), 0.2, f32(b) + 0.9*util.random_float(&scene_rng)}
            center_to_check := [3]f32{center[0] - 4.0, center[1] - 0.2, center[2] - 0.0}
            if vector_length_squared(center_to_check) > 0.81 {
                if choose_mat < 0.8 {
                    albedo   := vector_random(&scene_rng) * vector_random(&scene_rng)
                    mat      := material(lambertian{albedo = RTexture(ConstantTexture{color = albedo})})
                    append(&world, Sphere{center = center, radius = 0.2, material = mat})
                } else if choose_mat < 0.95 {
                    albedo   := vector_random_range(&scene_rng, 0.5, 1)
                    fuzz     := util.random_float_range(&scene_rng, 0, 0.5)
                    mat      := material(metallic{albedo, fuzz})
                    append(&world, Sphere{center = center, radius = 0.2, material = mat})
                } else {
                    mat := material(dielectric{1.5})
                    append(&world, Sphere{center = center, radius = 0.2, material = mat})
                }
                num_spheres += 1
            }
        }
        if num_spheres >= number_of_spheres {
            break
        }
    }

    material1 := material(dielectric{1.5})
    append(&world, Sphere{center = {0, 1, 0}, radius = 1.0, material = material1})

    material2 := material(lambertian{albedo = RTexture(ConstantTexture{color = {0.4, 0.2, 0.1}})})
    append(&world, Sphere{center = {-4, 1, 0}, radius = 1.0, material = material2})

    material3 := material(metallic{[3]f32{0.7, 0.6, 0.5}, 0.0})
    append(&world, Sphere{center = {4, 1, 0}, radius = 1.0, material = material3})

    cam := make_camera(image_width, image_height, samples_per_pixel)
    init_camera(cam)

    return cam, world
}

// Hard-coded earth scene: one sphere with image texture, camera from RTW "earth()".
// earth_path is the key used in the image cache (e.g. "assets/images/earthmap1k.jpg").
// Caller must keep earth_img alive for the duration of rendering; defer texture_image_destroy(earth_img) when done.
setup_earth_scene :: proc(image_width, image_height, samples_per_pixel: int, earth_path: string, earth_img: ^Texture_Image) -> (^Camera, [dynamic]Object) {
    scene := []core.SceneSphere{
        {
            center        = {0, 0, 0},
            radius        = 2,
            material_kind = .Lambertian,
            albedo        = core.ImageTexture{path = earth_path},
        },
    }
    cache: map[string]^Texture_Image
    cache[earth_path] = earth_img
    world := build_world_from_scene(scene, ConstantTexture{color = {0.5, 0.5, 0.5}}, cache)
    delete(cache)

    cam := make_camera(image_width, image_height, samples_per_pixel)
    cam.vfov = 20
    cam.lookfrom = [3]f32{0, 0, 12}
    cam.lookat = [3]f32{0, 0, 0}
    cam.vup = [3]f32{0, 1, 0}
    cam.defocus_angle = 0
    init_camera(cam)

    return cam, world
}
