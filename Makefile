.PHONY: debug release run run_gpu test test-release test-all imgui shaders vk-smoke

# Build Dear ImGui static library from the odin-imgui submodule.
# Run once after cloning, or after updating the submodule.
imgui:
	cd vendor/odin-imgui && python3 build.py

debug:
	mkdir -p build
	odin build . -collection:RT_Weekend=. -debug -define:TRACE_CAPTURE_ENABLED=true -define:TRACK_ALLOCATIONS=true -out:build/debug

release:
	mkdir -p build
	odin build . -collection:RT_Weekend=. \
		-o:speed \
		-no-bounds-check \
		-define:PROFILING_ENABLED=false \
		-define:VERBOSE_OUTPUT=false \
		-define:TRACE_CAPTURE_ENABLED=false \
		-define:TRACK_ALLOCATIONS=false \
		-out:build/release

run: debug
	./build/debug

run_gpu: debug
	./build/debug -gpu

test: debug
	chmod +x tests/run_tests.sh && ./tests/run_tests.sh debug

test-release: release
	chmod +x tests/run_tests.sh && ./tests/run_tests.sh release

test-all: debug release
	chmod +x tests/run_tests.sh && ./tests/run_tests.sh all

# Compile Vulkan GLSL shaders to SPIR-V.
# Run after modifying assets/shaders/raytrace_vk.comp or hello_triangle_vk.{vert,frag}.
# The .spv files are committed so builds don't require the Vulkan SDK.
shaders:
	glslangValidator -V assets/shaders/raytrace_vk.comp -o assets/shaders/raytrace_vk.comp.spv
	glslangValidator -V -S vert assets/shaders/hello_triangle_vk.vert -o assets/shaders/hello_triangle_vk.vert.spv
	glslangValidator -V -S frag assets/shaders/hello_triangle_vk.frag -o assets/shaders/hello_triangle_vk.frag.spv

# Vulkan bootstrap smoke test (package vk_ctx + GLFW; not linked into main app).
vk-smoke:
	mkdir -p build
	odin build tools/vk_smoke -collection:RT_Weekend=. -debug -out:build/vk_smoke
