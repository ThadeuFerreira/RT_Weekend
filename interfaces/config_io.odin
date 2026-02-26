package interfaces

import "core:encoding/json"
import "core:fmt"
import "core:os"

// RectF is a rectangle for JSON (panel position/size). Maps to/from rl.Rectangle.
RectF :: struct {
	x:      f32,
	y:      f32,
	width:  f32,
	height: f32,
}

// PanelState holds persisted state for one floating panel.
PanelState :: struct {
	rect:       RectF,
	visible:    bool,
	maximized:  bool,
	saved_rect: RectF,
}

// EditorLayout holds the panel states for the config file, keyed by panel ID string.
EditorLayout :: struct {
	panels: map[string]PanelState,
}

// LayoutPreset is a named snapshot of an editor layout (panel visibility/rects).
LayoutPreset :: struct {
	name:   string,
	layout: EditorLayout,
}

// RenderConfig is the full config file: render settings and optional editor layout.
RenderConfig :: struct {
	width:             int            `json:"width,omitempty"`,
	height:            int            `json:"height,omitempty"`,
	samples_per_pixel: int            `json:"samples_per_pixel,omitempty"`,
	editor:            ^EditorLayout  `json:"editor,omitempty"`,
	presets:           []LayoutPreset `json:"presets,omitempty"`,
}

// load_config reads a config file and returns the parsed config. Returns false on error or missing file.
// Omitted or zero width/height/samples_per_pixel should be treated as "use default" by the caller.
load_config :: proc(path: string) -> (config: RenderConfig, ok: bool) {
	data, read_ok := os.read_entire_file(path)
	if !read_ok {
		return {}, false
	}
	defer delete(data)

	err := json.unmarshal(data, &config)
	if err != nil {
		fmt.fprintf(os.stderr, "Config parse error: %v\n", err)
		return {}, false
	}
	return config, true
}

// save_config writes the config to a JSON file. Returns false on write error.
save_config :: proc(path: string, config: RenderConfig) -> bool {
	data, err := json.marshal(config)
	if err != nil {
		fmt.fprintf(os.stderr, "Config marshal error: %v\n", err)
		return false
	}
	defer delete(data)

	f, open_err := os.open(path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o644)
	if open_err != os.ERROR_NONE {
		fmt.fprintf(os.stderr, "Config write error: %s\n", path)
		return false
	}
	defer os.close(f)
	_, _ = os.write(f, data)
	return true
}
