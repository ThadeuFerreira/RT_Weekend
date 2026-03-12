.PHONY: debug debug-tsan release run run_gpu test test-release test-all

debug:
	mkdir -p build
	odin build . -collection:RT_Weekend=. -debug -define:TRACE_CAPTURE_ENABLED=true -define:TRACK_ALLOCATIONS=true -out:build/debug

debug-tsan:
	mkdir -p build
	odin build . -collection:RT_Weekend=. -debug -sanitize:thread -define:TRACE_CAPTURE_ENABLED=true -define:TRACK_ALLOCATIONS=true -out:build/debug-tsan

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

run_tsan: debug-tsan
	./build/debug-tsan -gpu

test: debug
	chmod +x tests/run_tests.sh && ./tests/run_tests.sh debug

test-release: release
	chmod +x tests/run_tests.sh && ./tests/run_tests.sh release

test-all: debug release
	chmod +x tests/run_tests.sh && ./tests/run_tests.sh all
