package main

import "core:math"
import "core:fmt"
import "core:strings"
import "core:math/rand"

infinity := math.inf_f32(1)

degrees_to_radians :: proc(degrees : f32) -> f32 {
    return degrees * math.PI / 180.0
}

random_float :: proc() -> f32 {
    return rand.float32()
}

random_float_range :: proc(min : f32, max : f32) -> f32 {
    return min + (max - min) * random_float()
}

linear_to_gamma :: proc(linear : f32) -> f32 {
    if linear > 0{
        return math.sqrt_f32(linear)
    }
    return 0
}


write_color :: proc(sb : ^strings.Builder, pixel_color : [3]f32) {
    // Write the translated [0,255] value of each color component.
    r := linear_to_gamma(pixel_color[0])
    g := linear_to_gamma(pixel_color[1])  
    b := linear_to_gamma(pixel_color[2])

    i := Interval{0.0, 0.999}

    fmt.sbprint(sb, int(interval_clamp(i,r)*255))
    fmt.sbprint(sb, " ")
    fmt.sbprint(sb, int(interval_clamp(i,g)*255))
    fmt.sbprint(sb, " ")
    fmt.sbprint(sb, int(interval_clamp(i,b)*255))
    fmt.sbprint(sb, "\n")
}