package util

import si "core:sys/info"
import "core:fmt"

System_Info :: struct {
	OdinVersion: string,
	OS: OS_Info,
	CPU: CPU_Info,
	RAM: RAM_Info,
	GPUs: [dynamic]GPU_Info,
}

OS_Info :: struct {
	Name: string,
}
CPU_Info :: struct {
	Name: string,
	Cores: int,
	LogicalCores: int,
}

RAM_Info :: struct {
	Total: int,
}

GPU_Info :: struct {
	Vendor: string,
	Model: string,
	VRAM: int,
}

get_system_info :: proc() -> System_Info {
	cpu_name := "Unknown"
	if name, ok := si.cpu.name.?; ok {
		cpu_name = name
	}

    os_info := OS_Info{
        Name = si.os_version.as_string,
    }
    cpu_info := CPU_Info{
        Name = cpu_name,
        Cores = si.cpu.physical_cores,
        LogicalCores = si.cpu.logical_cores,
    }
    ram_info := RAM_Info{
        Total = si.ram.total_ram,
    }
    
    gpus := make([dynamic]GPU_Info, 0, len(si.gpus))
    for gpu in si.gpus {
        append(&gpus, GPU_Info{
            Vendor = gpu.vendor_name,
            Model = gpu.model_name,
            VRAM = gpu.total_ram,
        })
    }
    defer delete(gpus)

    return System_Info{
        OdinVersion = ODIN_VERSION,
        OS = os_info,
        CPU = cpu_info,
        RAM = ram_info,
        GPUs = gpus,
    }
}