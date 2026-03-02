# util — CLI, RNG, system info

This package provides **command-line parsing**, **per-thread RNG**, and **system information**. It does **not** perform file or config I/O (that lives in **persistence**).

## Purpose

- **CLI** — `Args`, `parse_args_with_short_flags` for `-w`, `-h`, `-s`, `-n`, `-c`, `-config`, `-scene`, `-save-config`, `-save-scene`.
- **RNG** — Xoshiro256++ per-thread RNG: `ThreadRNG`, `create_thread_rng`, `random_float`, `random_float_range`.
- **System info** — `System_Info`, `OS_Info`, `CPU_Info`, `RAM_Info`, `GPU_Info`, `get_system_info`, `get_number_of_physical_cores`, `print_system_info` (via `core:sys/info`).
- **Trace capture** — Chrome Trace JSON event capture: `trace_start_capture`, `trace_stop_capture`, `trace_scope_begin`, `trace_scope_end`, `trace_register_thread`, `trace_set_metadata`, `trace_is_capturing`.

## Files

- **cli.odin** — Args and parsing.
- **rng.odin** — ThreadRNG and helpers.
- **system_info.odin** — System/OS/CPU/RAM/GPU info.
- **trace.odin** — in-memory trace event collection and JSON export data generation (no file writes).

## Dependency rule

**util** does not depend on editor, raytrace, or persistence. Config and scene file load/save are in **persistence**, not here.
