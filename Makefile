.PHONY: debug release

debug:
	odin build . -collection:RT_Weekend=. -debug -out:build/debug

release:
	odin build . -collection:RT_Weekend=. \
		-o:speed \
		-no-bounds-check \
		-define:PROFILING_ENABLED=false \
		-define:VERBOSE_OUTPUT=false \
		-out:build/release
