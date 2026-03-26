package viewport

import rl "vendor:raylib"
import imgui "RT_Weekend:vendor/odin-imgui"

ViewportDisplayTexture :: struct {
	valid:      bool,
	texture_id: imgui.TextureID,
	width:      i32,
	height:     i32,
	uv0:        [2]f32,
	uv1:        [2]f32,
}

ViewportTextureProvider :: struct {
	update: proc(provider: ^ViewportTextureProvider, app: rawptr),
	get_texture: proc(provider: ^ViewportTextureProvider, app: rawptr) -> ViewportDisplayTexture,
	resize: proc(provider: ^ViewportTextureProvider, app: rawptr, width, height: int),
}

_provider_noop_update :: proc(provider: ^ViewportTextureProvider, app: rawptr) {
	_ = provider
	_ = app
}

_provider_noop_get_texture :: proc(provider: ^ViewportTextureProvider, app: rawptr) -> ViewportDisplayTexture {
	_ = provider
	_ = app
	return ViewportDisplayTexture{}
}

_provider_noop_resize :: proc(provider: ^ViewportTextureProvider, app: rawptr, width, height: int) {
	_ = provider
	_ = app
	_ = width
	_ = height
}

make_noop_texture_provider :: proc() -> ViewportTextureProvider {
	return ViewportTextureProvider{
		update = _provider_noop_update,
		get_texture = _provider_noop_get_texture,
		resize = _provider_noop_resize,
	}
}

make_editor_texture_provider :: proc() -> ViewportTextureProvider {
	return make_noop_texture_provider()
}

make_raytrace_texture_provider :: proc() -> ViewportTextureProvider {
	return make_noop_texture_provider()
}
