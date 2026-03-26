package viewport

import rl "vendor:raylib"

Viewport :: struct {
	mode: ViewportMode,

	width:  int,
	height: int,

	needs_resize: bool,

	editor_target:  rl.RenderTexture2D,
	render_texture: rl.Texture2D,
}
