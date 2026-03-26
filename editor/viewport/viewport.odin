package viewport

import rl "vendor:raylib"

viewport_init :: proc(width, height: int) -> Viewport {
	vp := Viewport{
		mode         = .Editor,
		width        = max(width, 1),
		height       = max(height, 1),
		needs_resize = false,
	}
	vp.editor_target = rl.LoadRenderTexture(i32(vp.width), i32(vp.height))
	return vp
}

viewport_resize :: proc(vp: ^Viewport, width, height: int) {
	if vp == nil { return }
	next_w := max(width, 1)
	next_h := max(height, 1)
	if vp.width == next_w && vp.height == next_h { return }
	vp.width = next_w
	vp.height = next_h
	vp.needs_resize = true
}

viewport_update :: proc(vp: ^Viewport) {
	if vp == nil || !vp.needs_resize { return }
	if vp.editor_target.id != 0 {
		rl.UnloadRenderTexture(vp.editor_target)
	}
	vp.editor_target = rl.LoadRenderTexture(i32(vp.width), i32(vp.height))
	vp.needs_resize = false
}

viewport_set_mode :: proc(vp: ^Viewport, mode: ViewportMode) {
	if vp == nil || vp.mode == mode { return }
	vp.mode = mode
}
