package util

import "core:fmt"
import "core:os"
import "core:strconv"
import si "core:sys/info"

Args :: struct {
	Width:            int,
	Height:           int,
	Samples:          int,
	NumberOfSpheres:  int,
	ThreadCount:      int,
	ConfigPath:       string,
	ScenePath:        string,
	SaveConfigPath:   string,
	SaveScenePath:    string,
}

// Parse -w, -h, -s, -n, -c and -config, -scene, -save-config, -save-scene from os.args. Returns false on parse error or -help.
parse_args_with_short_flags :: proc(args: ^Args) -> bool {
	i := 1
	for i < len(os.args) {
		arg := os.args[i]
		if arg == "-help" || arg == "--help" {
			fmt.println("Usage: raytracer [-w width] [-h height] [-s samples] [-n spheres] [-c threads]")
			fmt.println("                [-config path] [-scene path] [-save-config path] [-save-scene path]")
			return false
		}
		if arg == "--" {
			i += 1
			continue
		}
		// Long-form options that take a path (string)
		if len(arg) >= 2 && arg[0] == '-' {
			if arg == "-config" || arg == "-scene" || arg == "-save-config" || arg == "-save-scene" {
				if i + 1 >= len(os.args) {
					fmt.fprintf(os.stderr, "Missing path for %s\n", arg)
					return false
				}
				path_val := os.args[i + 1]
				i += 2
				switch arg {
				case "-config":       args.ConfigPath = path_val
				case "-scene":       args.ScenePath = path_val
				case "-save-config": args.SaveConfigPath = path_val
				case "-save-scene":  args.SaveScenePath = path_val
				case:
				}
				continue
			}
			// Single-letter flags that take an integer
			if len(arg) == 2 {
				flag := arg[1]
				if i + 1 >= len(os.args) {
					fmt.fprintf(os.stderr, "Missing value for -%c\n", flag)
					return false
				}
				val_str := os.args[i + 1]
				i += 2
				val, ok := strconv.parse_int(val_str)
				if !ok {
					fmt.fprintf(os.stderr, "Invalid number for -%c: %s\n", flag, val_str)
					return false
				}
				switch flag {
				case 'w': args.Width = val
				case 'h': args.Height = val
				case 's': args.Samples = val
				case 'n': args.NumberOfSpheres = val
				case 'c': args.ThreadCount = val
				case:
					fmt.fprintf(os.stderr, "Unknown flag: -%c\n", flag)
					return false
				}
				continue
			}
		}
		i += 1
	}
	return true
}

get_number_of_logical_cores :: proc() -> int {
    return si.cpu.logical_cores
}
get_number_of_physical_cores :: proc() -> int {
    return si.cpu.physical_cores
}
get_total_ram :: proc() -> int {
    return si.ram.total_ram
}
get_gpu_info :: proc() -> string {
    return si.gpus[0].model_name
}

print_system_info :: proc() {
    fmt.printfln("Odin:      %v",      ODIN_VERSION)
	fmt.printfln("OS:        %v",      si.os_version.as_string)
	fmt.printfln("CPU:       %v",      si.cpu.name)
	fmt.printfln("CPU cores: %vc/%vt", si.cpu.physical_cores, si.cpu.logical_cores)
	fmt.printfln("RAM:       %#.1M",   si.ram.total_ram)

	fmt.println()
	for gpu, i in si.gpus {
		fmt.printfln("GPU #%v:", i)
		fmt.printfln("\tVendor: %v",    gpu.vendor_name)
		fmt.printfln("\tModel:  %v",    gpu.model_name)
		fmt.printfln("\tVRAM:   %#.1M", gpu.total_ram)
	}
}
