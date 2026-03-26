package viewport

import rl "vendor:raylib"

Viewport :: struct {
	mode: ViewportMode,

	// Current allocated texture size.
	width:  int,
	height: int,

	// Deferred resize request consumed by viewport_update.
	needs_resize: bool,
	pending_width:  int,
	pending_height: int,
	resize_defer_frames: int,

	editor_target:  rl.RenderTexture2D,
	// Stage-1 scaffolding: reserved for the raytrace output texture in Stage 2.
	render_texture: rl.Texture2D,
}
