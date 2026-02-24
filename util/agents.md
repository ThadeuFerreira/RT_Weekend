# util — Package Agent Notes

## Purpose

The `util` package provides **generic operations** that other components of the project use. It is the shared layer for:

- **Basic math and RNG** — per-thread random number generation used by the ray tracer and any code that needs deterministic, thread-safe randomness.
- **System calls and system info** — querying CPU cores, OS version, RAM, and GPU information via Odin’s `core:sys/info` (and related facilities) so that `main`, `ui`, and `raytrace` can adapt to the host without duplicating platform logic.
- **Configuration** — loading and saving render settings and editor layout (paths, JSON I/O). Callers decide *what* to configure; `util` provides the read/write and parsing.

No other package should reimplement CLI parsing, system-info queries, config file I/O, or the project’s standard RNG. Those live here. The `util` package does **not** depend on `ui` or `raytrace`; it may use only the Odin standard library and `core:*` packages.

---

## What Belongs in util

| Category | Description | Examples |
|----------|-------------|----------|
| **CLI** | Parsing process arguments and filling a structured `Args` (or similar). | `-w`, `-h`, `-s`, `-n`, `-c`, `-config`, `-scene`, `-save-config`, `-save-scene`, `-help`. |
| **System info** | Detecting CPU core count, OS name/version, RAM, GPUs. Used for default thread count, about dialogs, and tuning. | `get_number_of_physical_cores`, `get_system_info`, `SystemInfo`, `CPUInfo`, etc. |
| **Configuration** | Reading/writing config files (paths, JSON shape). No UI or render logic. | `load_config`, `save_config`, `RenderConfig`, `EditorLayout`, `PanelState`. |
| **RNG / basic math** | Shared PRNG and small numeric helpers used across packages. | `ThreadRNG`, `create_thread_rng`, `random_float`, `random_float_range` (Xoshiro256++). |

If a routine is “generic infrastructure” used by more than one of `main`, `ui`, and `raytrace`, and it fits one of the categories above, it belongs in `util`. Domain-specific math (e.g. ray/vector logic) stays in `raytrace`; UI-only helpers stay in `ui`.

---

## File Layout

| File | Responsibility |
|------|----------------|
| `util/cli.odin` | `Args` struct; `parse_args_with_short_flags`; `get_number_of_physical_cores` (via `core:sys/info`); help text. |
| `util/system_info.odin` | `SystemInfo`, `OSInfo`, `CPUInfo`, `RAMInfo`, `GPUInfo`; `get_system_info()` using `core:sys/info`. |
| `util/config.odin` | `RenderConfig`, `EditorLayout`, `PanelState`, `RectF`; `load_config`, `save_config` (JSON). |
| `util/rng.odin` | `ThreadRNG` (Xoshiro256++); `create_thread_rng`, `random_float`, `random_float_range`. |

New generic helpers (e.g. more math, file path helpers, or additional system queries) should be added to the most relevant existing file or a new `util/<topic>.odin` if they form a coherent group.

---

## Core Types and Procedures

### CLI (`cli.odin`)

- **`Args`** — Width, height, samples, sphere count, thread count, config/scene paths, save paths. Filled by `parse_args_with_short_flags`.
- **`parse_args_with_short_flags(args: ^Args) -> bool`** — Returns `false` on `-help` or parse error; otherwise fills `args` and returns `true`.
- **`get_number_of_physical_cores() -> int`** — Used for default `-c` (thread count).

### System info (`system_info.odin`)

- **`SystemInfo`** — Aggregates `OdinVersion`, `OS`, `CPU`, `RAM`, `GPUs`.
- **`get_system_info() -> SystemInfo`** — One-shot query; used by UI or startup for display/tuning.

### Configuration (`config.odin`)

- **`RenderConfig`** — Width, height, samples, optional `EditorLayout`.
- **`EditorLayout`** — `panels: map[string]PanelState` — persisted state for all floating panels, keyed by panel ID string (e.g. `"render_preview"`, `"stats"`, `"log"`). The map is heap-allocated by `json.unmarshal`; callers must `delete(layout.panels)` and `free(layout)` after use.
- **`PanelState`** — `rect`, `visible`, `maximized`, `saved_rect` for one panel.
- **`load_config(path) -> (RenderConfig, bool)`** — Read and parse JSON; `false` on missing file or parse error.
- **`save_config(path, config) -> bool`** — Write JSON; `false` on write error.

### RNG (`rng.odin`)

- **`ThreadRNG`** — Opaque state for Xoshiro256++.
- **`create_thread_rng(seed: u64) -> ThreadRNG`** — One RNG per thread; each thread should use its own instance.
- **`random_float(rng: ^ThreadRNG) -> f32`** — `[0, 1)`.
- **`random_float_range(rng: ^ThreadRNG, lo, hi: f32) -> f32`** — `[lo, hi)`.

---

## Dependencies and Boundaries

- **util** must not import `ui` or `raytrace`. It may use `core:*` (e.g. `core:fmt`, `core:os`, `core:sys/info`, `core:encoding/json`, `core:math`).
- **main** imports `util` for CLI, defaults (e.g. core count), and config paths.
- **ui** may import `util` for system info display, config load/save, and any shared helpers (e.g. layout types).
- **raytrace** may import `util` for RNG and, if needed, config or system info (e.g. thread count).

When adding a new “generic” capability (e.g. another system query or a small math helper), prefer putting it in `util` and reusing it from the other packages rather than duplicating logic.
