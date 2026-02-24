package util

import si "core:sys/info"

SystemInfo :: struct {
	OdinVersion: string,
	OS: OSInfo,
	CPU: CPUInfo,
	RAM: RAMInfo,
	GPUs: [dynamic]GPUInfo,
}

OSInfo :: struct {
	Name: string,
	Version: string,
}
CPUInfo :: struct {
	Name: string,
	Cores: int,
	LogicalCores: int,
}

RAMInfo :: struct {
	Total: int,
}

GPUInfo :: struct {
	Vendor: string,
	Model: string,
	VRAM: int,
}

get_system_info :: proc() -> SystemInfo {
	cpu_name := "Unknown"
	if name, ok := si.cpu.name.?; ok {
		cpu_name = name
	}

    os_info := OSInfo{
        Name = si.os_version.as_string,
        Version = si.os_version.as_string,
    }
    cpu_info := CPUInfo{
        Name = cpu_name,
        Cores = si.cpu.physical_cores,
        LogicalCores = si.cpu.logical_cores,
    }
    ram_info := RAMInfo{
        Total = si.ram.total_ram,
    }
    
    gpus := make([dynamic]GPUInfo, 0, len(si.gpus))
    for gpu in si.gpus {
        append(&gpus, GPUInfo{
            Vendor = gpu.vendor_name,
            Model = gpu.model_name,
            VRAM = gpu.total_ram,
        })
    }
    defer delete(gpus)

    return SystemInfo{
        OdinVersion = ODIN_VERSION,
        OS = os_info,
        CPU = cpu_info,
        RAM = ram_info,
        GPUs = gpus,
    }
}