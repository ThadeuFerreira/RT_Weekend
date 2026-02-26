# util — CLI, RNG, system info

This package provides **command-line parsing**, **per-thread RNG**, and **system information**. It does **not** perform file or config I/O (that lives in **interfaces**).

## Purpose

- **CLI** — `Args`, `parse_args_with_short_flags` for `-w`, `-h`, `-s`, `-n`, `-c`, `-config`, `-scene`, `-save-config`, `-save-scene`.
- **RNG** — Xoshiro256++ per-thread RNG: `ThreadRNG`, `create_thread_rng`, `random_float`, `random_float_range`.
- **System info** — `System_Info`, `OS_Info`, `CPU_Info`, `RAM_Info`, `GPU_Info`, `get_system_info`, `get_number_of_physical_cores`, `print_system_info` (via `core:sys/info`).

## Files

- **cli.odin** — Args and parsing.
- **rng.odin** — ThreadRNG and helpers.
- **system_info.odin** — System/OS/CPU/RAM/GPU info.

## Dependency rule

**util** does not depend on editor, raytrace, or interfaces. Config and scene file load/save are in **interfaces**, not here.
