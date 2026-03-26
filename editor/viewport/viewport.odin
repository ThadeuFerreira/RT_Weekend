package viewport

import rl "vendor:raylib"

VIEWPORT_RESIZE_STABLE_FRAMES :: 2

viewport_init :: proc(width, height: int) -> Viewport {
	init_w := max(width, 1)
	init_h := max(height, 1)
	vp := Viewport{
		mode         = .Editor,
		width        = init_w,
		height       = init_h,
		needs_resize = false,
		pending_width = init_w,
		pending_height = init_h,
		resize_defer_frames = 0,
	}
	vp.editor_target = rl.LoadRenderTexture(i32(vp.width), i32(vp.height))
	return vp
}

viewport_resize :: proc(vp: ^Viewport, width, height: int) {
	if vp == nil { return }
	next_w := max(width, 1)
	next_h := max(height, 1)
	if vp.needs_resize {
		if vp.pending_width == next_w && vp.pending_height == next_h { return }
	} else if vp.width == next_w && vp.height == next_h {
		return
	}
	vp.pending_width = next_w
	vp.pending_height = next_h
	vp.needs_resize = true
	vp.resize_defer_frames = VIEWPORT_RESIZE_STABLE_FRAMES
}

viewport_update :: proc(vp: ^Viewport) {
	if vp == nil || !vp.needs_resize { return }
	if vp.resize_defer_frames > 0 {
		vp.resize_defer_frames -= 1
		return
	}
	if vp.width == vp.pending_width && vp.height == vp.pending_height {
		vp.needs_resize = false
		return
	}
	if vp.editor_target.id != 0 {
		rl.UnloadRenderTexture(vp.editor_target)
	}
	vp.editor_target = rl.LoadRenderTexture(i32(vp.pending_width), i32(vp.pending_height))
	vp.width = vp.pending_width
	vp.height = vp.pending_height
	vp.needs_resize = false
}

viewport_set_mode :: proc(vp: ^Viewport, mode: ViewportMode) {
	if vp == nil || vp.mode == mode { return }
	vp.mode = mode
}
