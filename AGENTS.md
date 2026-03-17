# Repository Guidelines

## Project Structure & Module Organization
`main.odin` is the entry point. Core rendering code lives in `raytrace/`, editor and Raylib UI code in `editor/`, shared scene data in `core/`, persistence and JSON loading in `persistence/`, and CLI/helpers in `util/`. Static assets are under `assets/` (`shaders/`, `textures/`, `fonts/`). Regression scenes and test scripts live in `tests/`, with generated outputs written to `tests/output/`.

## Build, Test, and Development Commands
Use the Makefile targets first:

- `make debug`: build a debug binary at `build/debug` with tracing and allocation tracking enabled.
- `make release`: build an optimized binary at `build/release`.
- `make run`: build debug and launch the interactive app.
- `make run_gpu`: launch the debug build with `-gpu`.
- `make test`: run Odin unit coverage plus headless render regression tests against `build/debug`.
- `make test-release`: run the same suite against `build/release`.

Manual builds must include the collection: `odin build . -collection:RT_Weekend=. -debug -out:build/debug`.

## Coding Style & Naming Conventions
Follow existing Odin style: 4-space indentation, `snake_case` for procedures and variables, `PascalCase` for structs, and `UPPER_SNAKE_CASE` for compile-time flags and constants such as `TRACE_CAPTURE_ENABLED`. Keep packages focused by domain and prefer small files grouped by feature, for example `editor/panel_*.odin` and `editor/ui_*.odin`. Match the current import style and keep comments brief and technical.

## Testing Guidelines
Primary checks run through [`tests/run_tests.sh`](tests/run_tests.sh). Unit tests currently live in [`tests/aabb_transform_tests.odin`](tests/aabb_transform_tests.odin); render regressions use JSON scenes in `tests/scenes/*.json`. Name new tests after the feature under test, keep them deterministic, and prefer headless coverage for renderer changes. If you change scene serialization, editor state, or GPU output, run `make test` before opening a PR.

## Commit & Pull Request Guidelines
Recent history favors short, imperative commit subjects such as `Add volume handling in ray tracing engine and editor`, often with issue references like `(#115)`. Keep commits narrowly scoped and describe observable behavior, not implementation trivia. Pull requests should include a concise summary, linked issue if applicable, test results, and screenshots for editor or rendering UI changes.

## Configuration Notes
Keep `ols.json` aligned with the `RT_Weekend` collection so editor tooling resolves imports correctly. Do not commit generated files from `tests/output/` or one-off render artifacts unless they are intentional fixtures.
