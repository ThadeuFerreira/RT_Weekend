# Raylib texture mapping test (Odin)
# Place earth90.png in resources/ (e.g. from raylib examples or a 90°-rotated earth map).

ODIN  ?= odin
BUILD ?= build

.PHONY: all run debug release clean

all: debug

debug: $(BUILD)
	$(ODIN) build . -debug -out:$(BUILD)/texture_test

release: $(BUILD)
	$(ODIN) build . -o:speed -out:$(BUILD)/texture_test

$(BUILD):
	mkdir -p $(BUILD)

run: debug
	./$(BUILD)/texture_test

clean:
	rm -rf $(BUILD)
