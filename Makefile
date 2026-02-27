.PHONY: debug release test test-release test-all

debug:
	mkdir -p build
	odin build . -collection:RT_Weekend=. -debug -out:build/debug

release:
	mkdir -p build
	odin build . -collection:RT_Weekend=. \
		-o:speed \
		-no-bounds-check \
		-define:PROFILING_ENABLED=false \
		-define:VERBOSE_OUTPUT=false \
		-out:build/release

test: debug
	chmod +x tests/run_tests.sh && ./tests/run_tests.sh debug

test-release: release
	chmod +x tests/run_tests.sh && ./tests/run_tests.sh release

test-all: debug release
	chmod +x tests/run_tests.sh && ./tests/run_tests.sh all
