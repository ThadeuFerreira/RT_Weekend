package main

import "core:math"
import "core:fmt"
import "core:strings"
import "core:os"
import "core:strconv"

infinity := math.inf_f32(1)

degrees_to_radians :: proc(degrees : f32) -> f32 {
    return degrees * math.PI / 180.0
}

// Xoshiro256++ PRNG implementation
Xoshiro256pp :: struct {
    s: [4]u64,  // State array
}

// SplitMix64 for seeding Xoshiro256++
splitmix64 :: proc(seed: ^u64) -> u64 {
    seed^ += 0x9e3779b97f4a7c15
    z := seed^
    z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ~ (z >> 27)) * 0x94d049bb133111eb
    return z ~ (z >> 31)
}

// Seed Xoshiro256++ using SplitMix64
seed_xoshiro256pp :: proc(rng: ^Xoshiro256pp, seed: u64) {
    sm_state := seed
    rng.s[0] = splitmix64(&sm_state)
    rng.s[1] = splitmix64(&sm_state)
    rng.s[2] = splitmix64(&sm_state)
    rng.s[3] = splitmix64(&sm_state)
}

// Rotate left operation
rotl :: proc(x: u64, k: int) -> u64 {
    return (x << u64(k)) | (x >> u64(64 - k))
}

// Generate next random u64
xoshiro256pp_next :: proc(rng: ^Xoshiro256pp) -> u64 {
    result := rotl(rng.s[0] + rng.s[3], 23) + rng.s[0]
    
    t := rng.s[1] << 17
    
    // State update - must use old values
    s0 := rng.s[0]
    s1 := rng.s[1]
    s2 := rng.s[2]
    s3 := rng.s[3]
    
    rng.s[2] = s2 ~ s0
    rng.s[3] = s3 ~ s1
    rng.s[1] = s1 ~ rng.s[2]  // Uses new s[2]
    rng.s[0] = s0 ~ rng.s[3]  // Uses new s[3]
    
    rng.s[2] ~= t
    
    rng.s[3] = rotl(rng.s[3], 45)
    
    return result
}

// Generate random f32 in [0, 1)
xoshiro256pp_float :: proc(rng: ^Xoshiro256pp) -> f32 {
    // Generate 32 random bits and convert to float
    bits := u32(xoshiro256pp_next(rng) >> 32)
    // Convert to float in [0, 1)
    return f32(bits) / f32(0xFFFFFFFF)
}

// Create Xoshiro256++ instance with seed
create_xoshiro256pp :: proc(seed: u64) -> Xoshiro256pp {
    rng := Xoshiro256pp{}
    seed_xoshiro256pp(&rng, seed)
    return rng
}

// Thread-safe RNG wrapper
ThreadRNG :: struct {
    xoshiro: Xoshiro256pp,
}

// Create thread RNG with seed
create_thread_rng :: proc(seed: u64) -> ThreadRNG {
    return ThreadRNG{xoshiro = create_xoshiro256pp(seed)}
}

// Generate random float in [0, 1)
random_float :: proc(rng: ^ThreadRNG) -> f32 {
    return xoshiro256pp_float(&rng.xoshiro)
}

// Generate random float in [min, max)
random_float_range :: proc(rng: ^ThreadRNG, min: f32, max: f32) -> f32 {
    return min + (max - min) * random_float(rng)
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
    Width           : int,
    Height          : int,
    Samples         : int,
    NumberOfSpheres : int,
    TestMode        : bool,
    OutputFile      : string,
}

print_usage :: proc(program_name: string) {
    fmt.printf("Usage: %s [OPTIONS]\n\n", program_name)
    fmt.println("Options:")
    fmt.println("  -w, --width <int>        Image width in pixels (default: 800)")
    fmt.println("  -h, --height <int>       Image height in pixels (default: calculated from aspect ratio)")
    fmt.println("  -s, --samples <int>      Number of samples per pixel (default: 80)")
    fmt.println("  -o, --output <string>    Output file name (default: output.ppm)")
    fmt.println("  -n, --number_of_spheres <int> Number of small spheres in the scene (default: 100)")
    fmt.println("  -t, --test_mode          Run in test mode (default: false)")
    fmt.println("  --help                   Show this help message")
    fmt.println("\nExample:")
    fmt.printf("  %s -w 100 -h 100 -s 10 -o output.ppm\n", program_name)
}

parse_args_with_short_flags :: proc(args: ^Args) -> bool {
    i := 1
    for i < len(os.args) {
        arg := os.args[i]
        
        // Check for help flag (only --help, not -h which is for height)
        if arg == "--help" || arg == "-help" {
            print_usage(os.args[0])
            return false
        }
        
        // Handle short flags (-w, -h, -s, -o)
        if len(arg) == 2 && arg[0] == '-' {
            switch arg[1] {
            case 'w':
                if i + 1 < len(os.args) {
                    width, ok := strconv.parse_int(os.args[i + 1])
                    if ok {
                        args.Width = width
                    }
                    i += 2
                    continue
                }
            case 'h':
                if i + 1 < len(os.args) {
                    height, ok := strconv.parse_int(os.args[i + 1])
                    if ok {
                        args.Height = height
                    }
                    i += 2
                    continue
                }
            case 's':
                if i + 1 < len(os.args) {
                    samples, ok := strconv.parse_int(os.args[i + 1])
                    if ok {
                        args.Samples = samples
                    }
                    i += 2
                    continue
                }
            case 'o':
                if i + 1 < len(os.args) {
                    args.OutputFile = os.args[i + 1]
                    i += 2
                    continue
                }
            case 'n':
                if i + 1 < len(os.args) {
                    number_of_spheres, ok := strconv.parse_int(os.args[i + 1])
                    if ok {
                        args.NumberOfSpheres = number_of_spheres
                    }
                    i += 2
                    continue
                }
            case 't':
                args.TestMode = true
                i += 1
                continue
            }
        }
        
        // Handle long flags (--width, --height, --samples, --output)
        if len(arg) > 2 && arg[0] == '-' && arg[1] == '-' {
            flag_name := arg[2:]
            if i + 1 < len(os.args) {
                value := os.args[i + 1]
                switch flag_name {
                case "width":
                    width, ok := strconv.parse_int(value)
                    if ok {
                        args.Width = width
                    }
                case "height":
                    height, ok := strconv.parse_int(value)
                    if ok {
                        args.Height = height
                    }
                case "samples":
                    samples, ok := strconv.parse_int(value)
                    if ok {
                        args.Samples = samples
                    }
                case "number_of_spheres":
                    number_of_spheres, ok := strconv.parse_int(value)
                    if ok {
                        args.NumberOfSpheres = number_of_spheres
                    }
                case "test_mode":
                    args.TestMode = true
                case "output":
                    args.OutputFile = value
                }
                i += 2
                continue
            }
        }
        
        i += 1
    }
    
    return true
}
